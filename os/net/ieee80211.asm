; ==============================================================================
; x86-24scope OS - 802.11 / Ethernet Frame Encapsulation & Dispatcher
; ==============================================================================
bits 64
default rel

section .text

global net_handle_packet
global eth_send_packet

extern wifi_send_packet
extern wifi_get_mac
extern arp_handle_packet
extern ip_handle_packet
extern con_puts
extern serial_puts

; Handle incoming raw frame from WiFi driver
; RCX = Packet buffer pointer
; RDX = Packet length
net_handle_packet:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi
    push rcx
    push rdx

    mov rsi, rcx                    ; rsi = packet buffer
    mov rdi, rdx                    ; rdi = packet length

    ; Check if packet is too small to contain even an Ethernet header (14 bytes)
    cmp rdi, 14
    jb .done

    ; Note: on AX211, raw WiFi data frames are converted to standard 802.3 Ethernet frames
    ; by the firmware/driver wrapper. So the packet we receive from wifi_recv_packet
    ; starts directly with a standard Ethernet header!
    ; Ethernet Header:
    ; Offset 0..5:   Dest MAC (6 bytes)
    ; Offset 6..11:  Src MAC (6 bytes)
    ; Offset 12..13: EtherType (2 bytes, big endian)

    movzx eax, word [rsi + 12]      ; Read EtherType
    xchg al, ah                     ; Convert from big endian to CPU endian (little)

    ; Dispatch based on EtherType
    cmp ax, 0x0806                  ; ARP
    je .handle_arp
    cmp ax, 0x0800                  ; IPv4
    je .handle_ip
    jmp .done                       ; Ignore other protocols

.handle_arp:
    ; arp_handle_packet(rsi + 14, rdi - 14, rsi + 6)
    ; Pass packet payload, length, and source MAC address
    lea rcx, [rsi + 14]
    mov rdx, rdi
    sub rdx, 14
    lea r8, [rsi + 6]               ; Src MAC
    call arp_handle_packet
    jmp .done

.handle_ip:
    ; ip_handle_packet(rsi + 14, rdi - 14)
    lea rcx, [rsi + 14]
    mov rdx, rdi
    sub rdx, 14
    call ip_handle_packet

.done:
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    pop rbp
    ret

; Send a standard Ethernet frame
; RCX = Destination MAC address (6 bytes)
; RDX = EtherType (2 bytes, little endian)
; R8  = Payload pointer
; R9  = Payload length
eth_send_packet:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 2048                   ; Temporary buffer to build Ethernet frame

    mov r12, r8                     ; Payload
    mov r13, r9                     ; Payload length

    ; 1. Build Ethernet Header
    lea rdi, [rsp + 0]              ; Frame start
    
    ; Dest MAC (6 bytes)
    mov rsi, rcx
    mov rcx, 6
    rep movsb

    ; Src MAC (6 bytes)
    mov rbx, rdi                    ; Save position to write Src MAC
    lea rcx, [rbx]
    call wifi_get_mac               ; Write our MAC directly into header
    add rdi, 6                      ; Advance past Src MAC

    ; EtherType (2 bytes, convert to big endian)
    mov eax, edx
    xchg al, ah
    mov [rdi], ax
    add rdi, 2                      ; Header finished (14 bytes total)

    ; 2. Copy Payload
    mov rsi, r12
    mov rcx, r13
    rep movsb

    ; Calculate total frame size
    mov rdx, r13
    add rdx, 14                     ; Header + Payload

    ; 3. Send via WiFi driver
    lea rcx, [rsp + 0]              ; Buffer
    ; rdx = total size
    call wifi_send_packet

    add rsp, 2048
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret
