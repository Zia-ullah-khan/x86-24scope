; ==============================================================================
; x86-24scope OS - UDP Protocol Handler
; ==============================================================================
bits 64
default rel

section .text

global udp_handle_packet
global udp_send

extern ip_send
extern dhcp_handle_packet
extern con_puts
extern serial_puts

; UDP Header Offsets
UDP_SRC_PORT        equ 0
UDP_DST_PORT        equ 2
UDP_LEN             equ 4
UDP_CHKSUM          equ 6

; Handle incoming UDP packets
; RCX = Payload pointer (start of UDP header)
; RDX = Length of UDP segment
; R8d = Source IP
; R9d = Destination IP
udp_handle_packet:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov rsi, rcx                    ; rsi = UDP header
    mov r12, rdx                    ; r12 = length

    ; Check minimum length
    cmp r12, 8
    jb .done

    ; Extract Destination Port
    movzx eax, word [rsi + UDP_DST_PORT]
    xchg al, ah                     ; Convert to little endian (CPU)
    
    ; Extract Source Port
    movzx ebx, word [rsi + UDP_SRC_PORT]
    xchg bl, bh

    ; Extract Length
    movzx edx, word [rsi + UDP_LEN]
    xchg dl, dh                     ; edx = total length
    sub edx, 8                      ; edx = payload length

    ; Calculate start of payload
    lea rcx, [rsi + 8]              ; payload pointer
    
    ; Dispatch to registered port handlers
    cmp ax, 68                      ; DHCP Client Port
    je .handle_dhcp
    jmp .done

.handle_dhcp:
    ; dhcp_handle_packet(payload, len)
    call dhcp_handle_packet

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; Construct and send a UDP packet
; RCX = Source Port
; RDX = Destination Port
; R8d = Destination IP Address
; R9  = Payload pointer
; [rbp + 48] = Payload length (5th arg, retrieved using RBP)
udp_send:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 2048                   ; Temp buffer

    mov r12d, ecx                   ; Src Port
    mov r13d, edx                   ; Dst Port
    mov r14d, r8d                   ; Dst IP
    mov r15, r9                     ; Payload pointer

    ; Get payload length from stack (5th argument)
    ; Shadow space is 32 bytes, rbx..r15 push is 56 bytes.
    ; Offset from RBP = +48
    mov r10, [rbp + 48]             ; r10 = payload length

    ; Build UDP Header (8 bytes)
    lea rdi, [rsp + 0]
    
    ; Source Port
    mov ax, r12w
    xchg al, ah
    mov [rdi + UDP_SRC_PORT], ax

    ; Destination Port
    mov ax, r13w
    xchg al, ah
    mov [rdi + UDP_DST_PORT], ax

    ; Length = Payload length + 8
    mov rax, r10
    add rax, 8
    xchg al, ah
    mov [rdi + UDP_LEN], ax

    ; Checksum = 0 (optional in IPv4, disabled)
    mov word [rdi + UDP_CHKSUM], 0

    ; Copy Payload immediately after header
    add rdi, 8
    mov rsi, r15
    mov rcx, r10
    rep movsb

    ; Send via IP layer
    mov ecx, r14d                   ; Dest IP
    mov edx, 17                     ; Protocol = 17 (UDP)
    lea r8, [rsp + 0]               ; Payload
    mov r9, r10
    add r9, 8                       ; Size = Header + Payload
    call ip_send

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
