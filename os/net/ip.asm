; ==============================================================================
; x86-24scope OS - IPv4 and ICMP Protocol Driver
; ==============================================================================
bits 64
default rel

section .text

global ip_handle_packet
global ip_send
global ip_get_checksum

extern eth_send_packet
extern arp_resolve
extern dhcp_get_our_ip
extern udp_handle_packet
extern tcp_handle_packet
extern con_puts
extern con_put_hex
extern con_newline
extern serial_puts
extern serial_put_hex

; IP Header Offsets
IP_VER_IHL          equ 0
IP_TOS              equ 1
IP_TOT_LEN          equ 2
IP_ID               equ 4
IP_FLAGS_FRAG       equ 6
IP_TTL              equ 8
IP_PROTO            equ 9
IP_HDR_CHKSUM       equ 10
IP_SRC_IP           equ 12
IP_DST_IP           equ 16

; Handle incoming IPv4 packets
; RCX = Payload pointer (start of IP header)
; RDX = Payload length
ip_handle_packet:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov rsi, rcx                    ; rsi = IP header
    mov r12, rdx                    ; r12 = length

    ; Check minimum length (20 bytes for standard IP header)
    cmp r12, 20
    jb .done

    ; Verify Version (must be 4) and IHL (must be >= 5)
    mov al, [rsi + IP_VER_IHL]
    mov ah, al
    shr al, 4                       ; Version
    cmp al, 4
    jne .done
    
    and ah, 0x0F                    ; IHL (in dwords)
    cmp ah, 5
    jb .done

    movzx ebx, ah
    shl ebx, 2                      ; ebx = Header length in bytes (IHL * 4)

    ; Verify destination IP matches our IP (or broadcast)
    mov r8d, [rsi + IP_DST_IP]
    call dhcp_get_our_ip            ; eax = our IP
    cmp r8d, eax
    je .our_packet
    cmp r8d, 0xFFFFFFFF             ; Broadcast
    je .our_packet
    
    ; Check if destination is 0.0.0.0 (used during DHCP init)
    test r8d, r8d
    jnz .done

.our_packet:
    ; Protocol dispatch
    movzx eax, byte [rsi + IP_PROTO]
    
    movzx eax, word [rsi + IP_TOT_LEN]
    xchg al, ah                     ; Convert big endian to little endian
    movzx r9d, ax
    sub r9d, ebx                    ; r9d = Payload size (Total - Header)

    ; Calculate start of payload
    lea rcx, [rsi + rbx]            ; rcx = start of payload
    mov rdx, r9                     ; rdx = payload size

    cmp al, 1                       ; ICMP
    je .handle_icmp
    cmp al, 17                      ; UDP
    je .handle_udp
    cmp al, 6                       ; TCP
    je .handle_tcp
    jmp .done

.handle_icmp:
    ; Pass packet pointer, size, and source IP
    mov r8d, [rsi + IP_SRC_IP]      ; Src IP
    call icmp_handle_packet
    jmp .done

.handle_udp:
    mov r8d, [rsi + IP_SRC_IP]      ; Src IP
    mov r9d, [rsi + IP_DST_IP]      ; Dst IP
    call udp_handle_packet
    jmp .done

.handle_tcp:
    mov r8d, [rsi + IP_SRC_IP]      ; Src IP
    mov r9d, [rsi + IP_DST_IP]      ; Dst IP
    call tcp_handle_packet

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; Parse ICMP Packets
; RCX = ICMP payload pointer
; RDX = Length
; R8d = Sender IP address
icmp_handle_packet:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 2048                   ; Temp buffer

    mov rsi, rcx                    ; rsi = ICMP start
    mov r12, rdx                    ; r12 = length
    mov r13d, r8d                   ; r13d = sender IP

    ; Check minimum length (8 bytes for ICMP Echo)
    cmp r12, 8
    jb .done

    ; Check type: 8 = Echo Request
    mov al, [rsi]
    cmp al, 8
    jne .done

    ; Build ICMP Echo Reply (Type = 0, Code = 0)
    lea rdi, [rsp + 0]
    
    ; Copy entire payload (contains ID, Sequence, and Data)
    mov rcx, r12
    rep movsb

    ; Set Type = 0 (Echo Reply)
    mov byte [rsp + 0], 0
    ; Clear Checksum field
    mov word [rsp + 2], 0

    ; Recalculate ICMP Checksum
    lea rcx, [rsp + 0]
    mov rdx, r12
    call ip_get_checksum            ; AX = Checksum
    mov [rsp + 2], ax

    ; Send ICMP Echo Reply via IP layer
    mov ecx, r13d                   ; Dest IP
    mov edx, 1                      ; Protocol = 1 (ICMP)
    lea r8, [rsp + 0]               ; Payload
    mov r9, r12                     ; Length
    call ip_send

.done:
    add rsp, 2048
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; Construct and send an IPv4 packet
; RCX = Destination IP Address
; RDX = Protocol (1 = ICMP, 6 = TCP, 17 = UDP)
; R8  = Payload pointer
; R9  = Payload length
ip_send:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 2048                   ; Buffer for IP Header + Payload

    mov r12d, ecx                   ; Dest IP
    mov r13d, edx                   ; Protocol
    mov r14, r8                     ; Payload
    mov r15, r9                     ; Payload length

    ; Determine Target MAC Address
    cmp r12d, 0xFFFFFFFF            ; Broadcast
    je .use_broadcast

    ; Resolve MAC address via ARP
    mov ecx, r12d
    call arp_resolve
    test rax, rax
    jz .error                       ; ARP resolution failed, drop packet

    mov rbx, rax                    ; rbx = Pointer to 6-byte MAC address
    jmp .build_packet

.use_broadcast:
    lea rbx, [ip_broadcast_mac]

.build_packet:
    ; Build 20-byte IP header
    lea rdi, [rsp + 0]
    
    ; Ver/IHL = 0x45
    mov byte [rdi + IP_VER_IHL], 0x45
    ; TOS = 0
    mov byte [rdi + IP_TOS], 0
    
    ; Total Length = payload_length + 20
    mov rax, r15
    add rax, 20
    xchg al, ah                     ; Convert to big endian
    mov [rdi + IP_TOT_LEN], ax

    ; Identification (incremented counter)
    lock inc word [ip_id_counter]
    mov ax, [ip_id_counter]
    xchg al, ah
    mov [rdi + IP_ID], ax

    ; Flags/Fragment Offset = 0x0000 (Don't Fragment)
    mov word [rdi + IP_FLAGS_FRAG], 0x0040 ; Set Don't Fragment bit (0x4000 big endian)

    ; TTL = 64
    mov byte [rdi + IP_TTL], 64

    ; Protocol
    mov al, r13b
    mov byte [rdi + IP_PROTO], al

    ; Header Checksum = 0
    mov word [rdi + IP_HDR_CHKSUM], 0

    ; Source IP
    call dhcp_get_our_ip
    mov [rdi + IP_SRC_IP], eax

    ; Destination IP
    mov [rdi + IP_DST_IP], r12d

    ; Compute IP Header Checksum (standard ones' complement)
    mov rcx, rdi
    mov rdx, 20                     ; Header length is 20 bytes
    call ip_get_checksum
    mov [rdi + IP_HDR_CHKSUM], ax

    ; Copy Payload immediately after header
    add rdi, 20
    mov rsi, r14
    mov rcx, r15
    rep movsb

    ; Send Ethernet frame
    mov rcx, rbx                    ; Dest MAC
    mov edx, 0x0800                 ; EtherType = IPv4
    lea r8, [rsp + 0]               ; Payload
    mov r9, r15
    add r9, 20                      ; Size = Header + Payload
    call eth_send_packet
    
    mov rax, 1                      ; Success
    jmp .done

.error:
    xor rax, rax                    ; Failure

.done:
    add rsp, 2048
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; Standard Internet Checksum (16-bit ones' complement sum of data)
; RCX = Buffer pointer
; RDX = Size in bytes
ip_get_checksum:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi

    mov rsi, rcx
    mov rcx, rdx
    shr rcx, 1                      ; Size in words
    xor eax, eax                    ; Clear sum

.loop:
    test rcx, rcx
    jz .odd_byte
    
    movzx ebx, word [rsi]
    add eax, ebx
    add rsi, 2
    dec rcx
    jmp .loop

.odd_byte:
    ; If size is odd, add last byte
    test rdx, 1
    jz .finalize
    movzx ebx, byte [rsi]
    add eax, ebx

.finalize:
    ; Fold 32-bit sum into 16 bits
.fold:
    mov ebx, eax
    shr ebx, 16
    and eax, 0xFFFF
    add eax, ebx
    cmp eax, 0xFFFF
    ja .fold

    ; Ones' complement
    not ax
    
    pop rsi
    pop rbx
    pop rbp
    ret

section .data
align 8
ip_broadcast_mac db 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
ip_id_counter dw 0
