; ==============================================================================
; x86-24scope OS - Address Resolution Protocol (ARP)
; ==============================================================================
bits 64
default rel

section .text

global arp_init
global arp_handle_packet
global arp_resolve
global arp_cache_add

extern eth_send_packet
extern wifi_get_mac
extern dhcp_get_our_ip
extern get_ticks
extern sleep_ms
extern con_puts
extern con_put_hex
extern con_newline
extern serial_puts
extern serial_put_hex

; ARP Cache structure: 16 entries
; Each entry is 16 bytes:
; Offset 0..3:   IP Address (4 bytes)
; Offset 4..9:   MAC Address (6 bytes)
; Offset 10:     Flags (1 = Active)
; Offset 11..15: Padding

CACHE_SIZE equ 16
ENTRY_SIZE equ 16

arp_init:
    push rdi
    push rcx
    push rax

    ; Clear ARP cache
    lea rdi, [arp_cache]
    mov rcx, CACHE_SIZE * ENTRY_SIZE
    xor rax, rax
    rep stosb

    pop rax
    pop rcx
    pop rdi
    ret

; Parse incoming ARP packets
; RCX = Payload pointer (start of ARP header)
; RDX = Payload length
; R8  = Src MAC pointer from Ethernet header
arp_handle_packet:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov rsi, rcx                    ; rsi = ARP header

    ; Verify ARP Header Fields
    ; Hardware Type = 1 (Ethernet)
    movzx eax, word [rsi + 0]
    cmp ax, 0x0100                  ; Big endian 1
    jne .done
    
    ; Protocol Type = 0x0800 (IPv4)
    movzx eax, word [rsi + 2]
    cmp ax, 0x0008                  ; Big endian 0x0800
    jne .done

    ; Opcode (1 = Request, 2 = Reply)
    movzx ebx, word [rsi + 6]
    xchg bl, bh                     ; ebx = opcode (little endian)

    ; Extract IPs and MACs
    ; Sender MAC: offset 8
    ; Sender IP:  offset 14
    ; Target MAC: offset 18
    ; Target IP:  offset 24
    
    mov r10d, [rsi + 14]            ; Sender IP
    mov r11d, [rsi + 24]            ; Target IP

    ; Add sender to our ARP cache
    lea rcx, [rsi + 8]              ; Sender MAC
    mov edx, r10d                   ; Sender IP
    call arp_cache_add

    ; Check if target IP matches our IP
    call dhcp_get_our_ip            ; EAX = our IP
    cmp r11d, eax
    jne .done

    ; Target IP matches our IP!
    cmp ebx, 1                      ; Is it an ARP Request?
    jne .done

    ; Send ARP Reply
    sub rsp, 128                    ; Temp stack buffer for ARP packet
    mov rdi, rsp                    ; rdi points to new ARP header
    
    ; Hardware Type = 1
    mov word [rdi + 0], 0x0100
    ; Protocol Type = 0x0800
    mov word [rdi + 2], 0x0008
    ; HW size = 6, Protocol size = 4
    mov byte [rdi + 4], 6
    mov byte [rdi + 5], 4
    ; Opcode = 2 (Reply)
    mov word [rdi + 6], 0x0200

    ; Sender MAC (us)
    lea rcx, [rdi + 8]
    call wifi_get_mac

    ; Sender IP (us)
    call dhcp_get_our_ip
    mov [rdi + 14], eax

    ; Target MAC (sender of request)
    lea rdx, [rsi + 8]              ; Target MAC = sender MAC
    mov rax, [rdx]
    mov [rdi + 18], ax
    mov eax, [rdx + 2]
    mov [rdi + 20], eax

    ; Target IP (sender of request)
    mov eax, [rsi + 14]
    mov [rdi + 24], eax

    ; Send Ethernet packet
    lea rcx, [rsi + 8]              ; Dest MAC = sender MAC
    mov edx, 0x0806                 ; EtherType = ARP
    mov r8, rdi                     ; Payload
    mov r9, 28                      ; Length = 28 bytes
    call eth_send_packet
    add rsp, 128

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; Add or update entry in ARP cache
; RCX = MAC pointer (6 bytes)
; RDX = IP address (4 bytes)
arp_cache_add:
    push rbx
    push rsi
    push rdi

    ; 1. Search if IP is already in cache
    lea rbx, [arp_cache]
    xor r8, r8                      ; Index counter

.search_loop:
    cmp r8, CACHE_SIZE
    jae .add_new

    mov rcx, r8
    shl rcx, 4                      ; rcx = r8 * 16
    mov eax, [rbx + rcx + 0]
    cmp eax, edx
    je .update_entry

    inc r8
    jmp .search_loop

.update_entry:
    ; Update MAC address of entry r8
    mov rdi, rbx
    mov rsi, rcx
    mov rdx, r8
    imul rdx, ENTRY_SIZE
    add rdi, rdx
    add rdi, 4                      ; Offset 4 = MAC
    mov rcx, 6
    rep movsb
    jmp .done

.add_new:
    ; Find an inactive or oldest entry to overwrite
    ; For simplicity, we just use a round-robin index
    movzx r8d, byte [cache_next_index]
    
    mov rdi, rbx
    mov rsi, rcx
    mov rcx, r8
    imul rcx, ENTRY_SIZE
    add rdi, rcx                    ; rdi = start of target entry

    mov [rdi + 0], edx              ; IP
    
    add rdi, 4                      ; MAC
    mov rcx, 6
    rep movsb

    mov byte [rdi], 1               ; Flags = Active (rdi is already at offset 10 of entry)

    ; Increment round-robin index
    inc r8d
    and r8d, 15                     ; wrap to 0..15
    mov [cache_next_index], r8b

.done:
    pop rdi
    pop rsi
    pop rbx
    ret

; Resolve IP address to MAC address (API for IP layer)
; RCX = Target IP Address
; Returns RAX = Pointer to 6-byte MAC Address (or 0 if resolution failed)
arp_resolve:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    mov r12d, ecx                   ; r12d = Target IP

    ; 1. Search in cache
    lea rbx, [arp_cache]
    xor rsi, rsi

.cache_search:
    cmp rsi, CACHE_SIZE
    jae .not_in_cache

    mov rcx, rsi
    shl rcx, 4                      ; rcx = rsi * 16
    mov eax, [rbx + rcx + 0]
    cmp eax, r12d
    jne .next_cache

    mov al, [rbx + rcx + 10]        ; Active flag
    cmp al, 1
    je .found

.next_cache:
    inc rsi
    jmp .cache_search

.found:
    ; Found in cache! Return address of MAC
    mov rax, rbx
    mov rcx, rsi
    imul rcx, ENTRY_SIZE
    add rax, rcx
    add rax, 4                      ; Pointer to MAC
    jmp .done

.not_in_cache:
    ; Send ARP Request
    sub rsp, 128
    mov rdi, rsp                    ; rdi = new ARP header

    mov word [rdi + 0], 0x0100      ; HW Type = Ethernet
    mov word [rdi + 2], 0x0008      ; Proto = IPv4
    mov byte [rdi + 4], 6           ; HW Size
    mov byte [rdi + 5], 4           ; Proto Size
    mov word [rdi + 6], 0x0100      ; Opcode = 1 (Request)

    ; Sender MAC (us)
    lea rcx, [rdi + 8]
    call wifi_get_mac

    ; Sender IP (us)
    call dhcp_get_our_ip
    mov [rdi + 14], eax

    ; Target MAC (00-00-00-00-00-00 for request)
    xor rax, rax
    mov [rdi + 18], ax
    mov [rdi + 20], eax

    ; Target IP
    mov [rdi + 24], r12d

    ; Broadcast Ethernet packet (Dest MAC = FF-FF-FF-FF-FF-FF)
    lea rcx, [arp_broadcast_mac]
    mov edx, 0x0806                 ; ARP
    mov r8, rdi                     ; Payload
    mov r9, 28                      ; Length
    call eth_send_packet
    add rsp, 128

    ; Poll ARP cache for resolution (up to 500ms)
    call get_ticks
    mov r13, rax
    add r13, 500                    ; Target timeout tick

.poll_loop:
    call get_ticks
    cmp rax, r13
    jae .timeout

    ; Search cache again
    lea rbx, [arp_cache]
    xor rsi, rsi
.poll_search:
    cmp rsi, CACHE_SIZE
    jae .poll_sleep
    
    mov rcx, rsi
    shl rcx, 4                      ; rcx = rsi * 16
    mov eax, [rbx + rcx + 0]
    cmp eax, r12d
    jne .next_poll
    mov al, [rbx + rcx + 10]
    cmp al, 1
    je .found                       ; Resolved!

.next_poll:
    inc rsi
    jmp .poll_search

.poll_sleep:
    mov rcx, 10
    call sleep_ms
    jmp .poll_loop

.timeout:
    xor rax, rax                    ; Resolution failed

.done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

section .data
align 8
arp_broadcast_mac db 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
cache_next_index db 0

section .bss
align 16
arp_cache resb CACHE_SIZE * ENTRY_SIZE
