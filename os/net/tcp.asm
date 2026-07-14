; ==============================================================================
; x86-24scope OS - Lightweight TCP Engine
; ==============================================================================
bits 64
default rel

section .text

global tcp_init
global tcp_listen
global tcp_accept
global tcp_send
global tcp_recv
global tcp_close
global tcp_handle_packet

extern ip_send
extern ip_get_checksum
extern dhcp_get_our_ip
extern con_puts
extern con_put_hex
extern con_newline
extern serial_puts
extern serial_put_hex

; TCP Socket States
TCP_STATE_CLOSED        equ 0
TCP_STATE_LISTEN        equ 1
TCP_STATE_SYN_RECEIVED  equ 2
TCP_STATE_ESTABLISHED   equ 3
TCP_STATE_CLOSE_WAIT    equ 4
TCP_STATE_LAST_ACK      equ 5

; TCP flags
TCP_FLAG_FIN            equ 0x01
TCP_FLAG_SYN            equ 0x02
TCP_FLAG_RST            equ 0x04
TCP_FLAG_PSH            equ 0x08
TCP_FLAG_ACK            equ 0x10

; Socket structure definition (64 bytes per socket, 8 sockets total)
; Offset 0:   State (1 byte)
; Offset 2:   Local Port (2 bytes)
; Offset 4:   Remote Port (2 bytes)
; Offset 8:   Remote IP (4 bytes)
; Offset 12:  Local Seq (4 bytes)
; Offset 16:  Remote Seq (4 bytes)
; Offset 24:  Recv Page Base Address (8 bytes)
; Offset 32:  Recv Buf Write Pointer (4 bytes)
; Offset 36:  Recv Buf Read Pointer (4 bytes)

MAX_SOCKETS equ 8
SOCKET_SIZE equ 64
TCP_MSS     equ 1400                ; keep under Ethernet MTU / ip_send buffer

tcp_init:
    push rdi
    push rcx
    push rax

    ; Clear Socket Table
    lea rdi, [tcp_sockets]
    mov rcx, MAX_SOCKETS * SOCKET_SIZE
    xor rax, rax
    rep stosb

    pop rax
    pop rcx
    pop rdi
    ret

; Start listening on a local port
; RCX = Port
tcp_listen:
    push rbx
    push r12
    mov r12, rcx                    ; preserve port (rcx is reused below)

    ; Find free socket
    lea rbx, [tcp_sockets]
    xor rdx, rdx
.loop:
    cmp rdx, MAX_SOCKETS
    jae .fail

    mov rcx, rdx
    shl rcx, 6                      ; rcx = rdx * 64
    mov al, [rbx + rcx + 0]
    cmp al, TCP_STATE_CLOSED
    je .found

    inc rdx
    jmp .loop

.found:
    mov r8, rdx
    imul r8, SOCKET_SIZE
    add rbx, r8

    mov byte [rbx + 0], TCP_STATE_LISTEN
    mov [rbx + 2], r12w             ; Save port

    ; Allocate page for receive buffer
    extern pmm_alloc_page
    call pmm_alloc_page
    mov [rbx + 24], rax             ; Save page address
    mov dword [rbx + 32], 0         ; Write ptr
    mov dword [rbx + 36], 0         ; Read ptr

    mov rax, 1                      ; Success
    jmp .done

.fail:
    xor rax, rax                    ; Error

.done:
    pop r12
    pop rbx
    ret

; Accept a connection on a listening port
; RCX = Port
; RDX = Output Socket ID pointer
; Returns RAX = 1 if accepted, 0 if no connection
tcp_accept:
    push rbx
    lea rbx, [tcp_sockets]
    xor r8, r8

.loop:
    cmp r8, MAX_SOCKETS
    jae .not_found

    mov r9, r8
    imul r9, SOCKET_SIZE
    lea r9, [rbx + r9]

    ; Check if state is ESTABLISHED and local port matches
    mov al, [r9 + 0]
    cmp al, TCP_STATE_ESTABLISHED
    jne .next

    movzx eax, word [r9 + 2]
    cmp ax, cx
    jne .next

    ; Check if already accepted/processed (we can use a flag at offset 1 of socket)
    mov al, [r9 + 1]
    cmp al, 1                       ; 1 = already accepted
    je .next

    ; Mark as accepted
    mov byte [r9 + 1], 1
    
    ; Return socket ID
    mov [rdx], r8d
    mov rax, 1
    jmp .done

.next:
    inc r8
    jmp .loop

.not_found:
    xor rax, rax

.done:
    pop rbx
    ret

; Send data over an established socket
; RCX = Socket ID
; RDX = Buffer pointer
; R8  = Length
; Segments into TCP_MSS chunks so IP/Ethernet stay under MTU.
tcp_send:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 2048                   ; one TCP segment (header + MSS)

    mov r12d, ecx                   ; Socket ID
    mov r13, rdx                    ; Buffer
    mov r14, r8                     ; Remaining length
    xor r15, r15                    ; Total sent

    lea rbx, [tcp_sockets]
    mov r8, r12
    imul r8, SOCKET_SIZE
    add rbx, r8                     ; rbx = socket pointer

    mov al, [rbx + 0]
    cmp al, TCP_STATE_ESTABLISHED
    jne .error

    test r14, r14
    jz .success

.chunk_loop:
    mov rax, r14
    cmp rax, TCP_MSS
    jbe .chunk_size
    mov rax, TCP_MSS
.chunk_size:
    mov r12, rax                    ; r12 = this chunk length

    lea rdi, [rsp + 0]

    mov ax, [rbx + 2]
    xchg al, ah
    mov [rdi + 0], ax

    mov ax, [rbx + 4]
    xchg al, ah
    mov [rdi + 2], ax

    mov eax, [rbx + 12]
    bswap eax
    mov [rdi + 4], eax

    mov eax, [rbx + 16]
    bswap eax
    mov [rdi + 8], eax

    mov byte [rdi + 12], 0x50
    mov byte [rdi + 13], TCP_FLAG_ACK | TCP_FLAG_PSH
    mov word [rdi + 14], 0x0020
    mov word [rdi + 16], 0
    mov word [rdi + 18], 0

    lea rdi, [rsp + 20]
    mov rsi, r13
    mov rcx, r12
    rep movsb

    lea rcx, [rsp + 0]
    mov rdx, r12
    add rdx, 20
    mov r8d, [rbx + 8]
    call tcp_calculate_checksum
    mov [rsp + 16], ax

    mov ecx, [rbx + 8]
    mov edx, 6
    lea r8, [rsp + 0]
    mov r9, r12
    add r9, 20
    call ip_send

    mov eax, [rbx + 12]
    add eax, r12d
    mov [rbx + 12], eax

    add r13, r12
    add r15, r12
    sub r14, r12
    jnz .chunk_loop

.success:
    mov rax, r15
    jmp .done

.error:
    xor rax, rax

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

; Read from socket receive buffer
; RCX = Socket ID
; RDX = Destination buffer
; R8  = Max length
tcp_recv:
    push rbx
    push rsi
    push rdi
    push r12

    mov rdi, rdx                    ; preserve destination buffer
    mov r12, r8                     ; preserve max length

    lea rbx, [tcp_sockets]
    imul rcx, SOCKET_SIZE
    add rbx, rcx                    ; rbx = socket

    mov rsi, [rbx + 24]             ; Page base
    test rsi, rsi
    jz .empty

    mov eax, [rbx + 32]             ; Write pointer
    mov ecx, [rbx + 36]             ; Read pointer

    cmp ecx, eax
    je .empty

    ; Bytes available
    mov r8d, eax
    sub r8d, ecx
    cmp r8, r12
    jbe .copy_size
    mov r8, r12                     ; clamp to caller max

.copy_size:
    ; Copy to destination
    lea rsi, [rsi + rcx]            ; Source pointer
    mov rcx, r8                     ; Count
    rep movsb

    ; Advance read pointer by bytes copied
    mov ecx, [rbx + 36]
    add ecx, r8d
    mov [rbx + 36], ecx

    mov rax, r8                     ; Return size read
    jmp .done

.empty:
    xor rax, rax

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; Close connection
; RCX = Socket ID
tcp_close:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    sub rsp, 128

    lea rbx, [tcp_sockets]
    imul rcx, SOCKET_SIZE
    add rbx, rcx

    mov al, [rbx + 0]
    cmp al, TCP_STATE_CLOSED
    je .done

    ; If ESTABLISHED or CLOSE_WAIT, send FIN-ACK
    cmp al, TCP_STATE_LISTEN
    je .just_close

    ; Send FIN-ACK packet
    mov rdi, rsp
    
    mov ax, [rbx + 2]               ; Src Port
    xchg al, ah
    mov [rdi + 0], ax

    mov ax, [rbx + 4]               ; Dst Port
    xchg al, ah
    mov [rdi + 2], ax

    mov eax, [rbx + 12]             ; Seq
    bswap eax
    mov [rdi + 4], eax

    mov eax, [rbx + 16]             ; Ack
    bswap eax
    mov [rdi + 8], eax

    mov byte [rdi + 12], 0x50
    mov byte [rdi + 13], TCP_FLAG_FIN | TCP_FLAG_ACK
    mov word [rdi + 14], 0x0020
    mov word [rdi + 16], 0
    mov word [rdi + 18], 0

    ; Checksum
    mov rcx, rdi
    mov rdx, 20
    mov r8d, [rbx + 8]
    call tcp_calculate_checksum
    mov [rdi + 16], ax

    ; Send via IP
    mov ecx, [rbx + 8]
    mov edx, 6
    mov r8, rdi
    mov r9, 20
    call ip_send

    ; Connection socket — mark closed (listener stays in LISTEN separately)
    mov byte [rbx + 0], TCP_STATE_CLOSED
    mov byte [rbx + 1], 0
    mov word [rbx + 4], 0
    mov dword [rbx + 8], 0
    mov dword [rbx + 12], 0
    mov dword [rbx + 16], 0
    mov dword [rbx + 32], 0
    mov dword [rbx + 36], 0
    jmp .done

.just_close:
    mov byte [rbx + 0], TCP_STATE_CLOSED

.done:
    add rsp, 128
    pop rdi
    pop rbx
    pop rbp
    ret

; Parse incoming TCP Packets
; RCX = Start of TCP packet header
; RDX = Segment length (IP total length - IP header length)
; R8d = Source IP
; R9d = Destination IP
tcp_handle_packet:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov rsi, rcx                    ; rsi = TCP start
    push rcx
    lea rcx, [msg_tcp_pkt]
    call serial_puts
    pop rcx
    mov rsi, rcx
    mov r12, rdx                    ; r12 = length
    mov r13d, r8d                   ; r13d = Src IP
    mov r14d, r9d                   ; r14d = Dst IP

    ; Check minimum TCP header size
    cmp r12, 20
    jb .done

    ; Extract Ports
    movzx ebx, word [rsi + 0]       ; Src Port
    xchg bl, bh                     ; ebx = Src Port
    
    movzx ecx, word [rsi + 2]       ; Dst Port
    xchg cl, ch                     ; ecx = Dst Port

    ; Extract Seq/Ack
    mov eax, [rsi + 4]
    bswap eax                     ; eax = Seq (little endian)
    mov r15d, eax                   ; r15d = incoming Seq

    mov eax, [rsi + 8]
    bswap eax                     ; eax = Ack (little endian)
    mov r10d, eax                   ; r10d = incoming Ack

    ; Get header length (offset is at byte 12)
    movzx eax, byte [rsi + 12]
    shr al, 4                       ; Header length in dwords
    shl al, 2                       ; Header length in bytes
    movzx r8d, al                   ; r8d = TCP Header length
    
    ; Calculate payload length
    mov r9d, r12d
    sub r9d, r8d                    ; r9d = payload length

    ; Extract Flags
    movzx eax, byte [rsi + 13]      ; eax = Flags

    ; 1. Search Socket Table
    lea rdi, [tcp_sockets]
    xor rdx, rdx                    ; Socket index

.search_loop:
    cmp rdx, MAX_SOCKETS
    jae .handle_new_conn

    mov r11, rdx
    imul r11, SOCKET_SIZE
    lea r11, [rdi + r11]            ; r11 = current socket

    mov r10b, [r11 + 0]             ; State
    cmp r10b, TCP_STATE_CLOSED
    je .next

    movzx r10d, word [r11 + 2]      ; Local Port
    cmp r10d, ecx
    jne .next

    ; LISTEN sockets are handled in .handle_new_conn (SYN path).
    ; Matching them here would swallow SYNs without spawning.
    mov r10b, [r11 + 0]
    cmp r10b, TCP_STATE_LISTEN
    je .next

    cmp r10b, TCP_STATE_SYN_RECEIVED
    je .process_state

    cmp r10b, TCP_STATE_ESTABLISHED
    jne .next

    mov r10d, [r11 + 8]             ; Remote IP
    cmp r10d, r13d
    jne .next

    movzx r10d, word [r11 + 4]      ; Remote Port
    cmp r10d, ebx
    je .process_state

.next:
    inc rdx
    jmp .search_loop

.handle_new_conn:
    ; No active matching socket found. Is it SYN?
    test al, TCP_FLAG_SYN
    jz .done

    ; Search for a listening socket on local port ecx
    lea rdi, [tcp_sockets]
    xor rdx, rdx
.listen_search:
    cmp rdx, MAX_SOCKETS
    jae .done

    mov r11, rdx
    imul r11, SOCKET_SIZE
    lea r11, [rdi + r11]

    mov r10b, [r11 + 0]
    cmp r10b, TCP_STATE_LISTEN
    jne .next_listen

    movzx r10d, word [r11 + 2]
    cmp r10d, ecx
    je .spawn_socket                ; Found listener! Spawn connection.

.next_listen:
    inc rdx
    jmp .listen_search

.spawn_socket:
    ; Allocate a free socket for this connection; keep the listener in LISTEN
    ; so the browser can open multiple image requests in parallel.
    push r12
    push r14
    mov r14, r11                    ; r14 = listener socket

    lea rdi, [tcp_sockets]
    xor rdx, rdx
.find_free:
    cmp rdx, MAX_SOCKETS
    jae .spawn_busy

    mov r11, rdx
    imul r11, SOCKET_SIZE
    lea r11, [rdi + r11]
    cmp byte [r11 + 0], TCP_STATE_CLOSED
    je .spawn_found
    inc rdx
    jmp .find_free

.spawn_busy:
    pop r14
    pop r12
    jmp .done

.spawn_found:
    lea rcx, [msg_tcp_syn]
    call serial_puts

    movzx r12d, word [r14 + 2]      ; local port from listener

    mov byte [r11 + 0], TCP_STATE_SYN_RECEIVED
    mov byte [r11 + 1], 0           ; not yet accepted by http
    mov [r11 + 2], r12w             ; Local Port
    mov [r11 + 4], bx               ; Remote Port
    mov [r11 + 8], r13d             ; Remote IP
    mov dword [r11 + 12], 1000      ; Local Seq
    mov r10d, r15d
    inc r10d
    mov [r11 + 16], r10d            ; Remote Seq

    ; Recv buffer: reuse listener page if child has none — allocate fresh
    cmp qword [r11 + 24], 0
    jne .spawn_buf_ok
    extern pmm_alloc_page
    call pmm_alloc_page
    test rax, rax
    jz .spawn_busy_free
    mov [r11 + 24], rax
.spawn_buf_ok:
    mov dword [r11 + 32], 0
    mov dword [r11 + 36], 0

    lea rcx, [r11]
    mov edx, TCP_FLAG_SYN | TCP_FLAG_ACK
    call tcp_send_control
    pop r14
    pop r12
    jmp .done

.spawn_busy_free:
    mov byte [r11 + 0], TCP_STATE_CLOSED
    pop r14
    pop r12
    jmp .done

.process_state:
    ; Process socket in r11 based on flags in eax and state in [r11 + 0]
    mov r10b, [r11 + 0]             ; Socket State
    
    cmp r10b, TCP_STATE_SYN_RECEIVED
    jne .check_established

    ; Retransmitted SYN: resend SYN-ACK
    test al, TCP_FLAG_SYN
    jz .synrecv_ack
    lea rcx, [r11]
    mov edx, TCP_FLAG_SYN | TCP_FLAG_ACK
    call tcp_send_control
    jmp .done

.synrecv_ack:
    ; Expecting ACK (flags at eax)
    test al, TCP_FLAG_ACK
    jz .done

    ; Transition to ESTABLISHED!
    mov byte [r11 + 0], TCP_STATE_ESTABLISHED
    lea rcx, [msg_tcp_est]
    call serial_puts
    jmp .done

.check_established:
    cmp r10b, TCP_STATE_ESTABLISHED
    jne .check_last_ack

    ; Check for FIN (client closing)
    test al, TCP_FLAG_FIN
    jz .process_data

    ; Client wants to close. Send ACK of FIN and set state to CLOSE_WAIT
    mov r10d, r15d
    inc r10d                        ; Remote Seq = incoming Seq + 1
    mov [r11 + 16], r10d

    lea rcx, [r11]
    mov edx, TCP_FLAG_ACK
    call tcp_send_control
    
    mov byte [r11 + 0], TCP_STATE_CLOSE_WAIT
    jmp .done

.process_data:
    ; Check if payload length > 0
    test r9d, r9d
    jz .ack_only

    ; rsi still points at TCP header; payload is at rsi + header_len
    lea r10, [rsi + r8]             ; r10 = payload source

    mov rdi, [r11 + 24]             ; recv page
    test rdi, rdi
    jz .ack_only

    mov eax, [r11 + 32]             ; write pointer
    add rdi, rax                    ; destination

    mov rsi, r10
    mov rcx, r9
    rep movsb

    ; Update Write Pointer
    mov eax, [r11 + 32]
    add eax, r9d
    mov [r11 + 32], eax

    ; Update Remote Seq: Remote Seq = incoming Seq + payload_len
    mov eax, r15d
    add eax, r9d
    mov [r11 + 16], eax

.ack_only:
    ; Send ACK packet
    lea rcx, [r11]
    mov edx, TCP_FLAG_ACK
    call tcp_send_control
    jmp .done

.check_last_ack:
    cmp r10b, TCP_STATE_LAST_ACK
    jne .done

    ; Expecting ACK of our FIN
    test al, TCP_FLAG_ACK
    jz .done

    mov byte [r11 + 0], TCP_STATE_CLOSED

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; Send TCP Control Packet (SYN-ACK, ACK, FIN-ACK, etc.)
; RCX = Socket pointer
; RDX = Flags (SYN, ACK, FIN, etc.)
tcp_send_control:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push r12
    push r13
    sub rsp, 128                    ; Temp stack buffer

    mov rbx, rcx                    ; rbx = Socket pointer
    mov r12d, edx                   ; r12d = Flags
    mov rdi, rsp                    ; rdi = TCP packet

    ; Source Port
    mov ax, [rbx + 2]
    xchg al, ah
    mov [rdi + 0], ax

    ; Destination Port
    mov ax, [rbx + 4]
    xchg al, ah
    mov [rdi + 2], ax

    ; Seq
    mov eax, [rbx + 12]
    bswap eax
    mov [rdi + 4], eax

    ; Ack
    mov eax, [rbx + 16]
    bswap eax
    mov [rdi + 8], eax

    ; Header Len (20 bytes = 5 dwords -> 0x50)
    mov byte [rdi + 12], 0x50
    ; Flags
    mov al, r12b
    mov byte [rdi + 13], al
    ; Window Size = 8192
    mov word [rdi + 14], 0x0020
    ; Checksum = 0
    mov word [rdi + 16], 0
    ; Urgent = 0
    mov word [rdi + 18], 0

    ; Calculate checksum
    mov rcx, rdi
    mov rdx, 20                     ; Length = 20
    mov r8d, [rbx + 8]              ; Dest IP
    call tcp_calculate_checksum
    mov [rdi + 16], ax

    ; Send via IP
    mov ecx, [rbx + 8]              ; Dest IP
    mov edx, 6                      ; TCP
    mov r8, rdi                     ; Payload
    mov r9, 20                      ; Length
    call ip_send

    ; If we sent SYN or FIN, increment local seq by 1
    test r12d, TCP_FLAG_SYN | TCP_FLAG_FIN
    jz .no_inc
    inc dword [rbx + 12]

.no_inc:
    add rsp, 128
    pop r13
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret

; Calculate TCP Checksum (includes pseudo-header)
; RCX = TCP segment pointer
; RDX = TCP segment length (header + payload)
; R8d = Destination IP address
tcp_calculate_checksum:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 64

    mov rsi, rcx                    ; rsi = TCP Start
    mov r12, rdx                    ; r12 = TCP Length
    mov r13d, r8d                   ; r13d = Dest IP

    ; Build 12-byte pseudo-header on stack
    lea rdi, [rsp + 0]
    
    ; Source IP
    call dhcp_get_our_ip
    mov [rdi + 0], eax

    ; Destination IP
    mov [rdi + 4], r13d

    ; Reserved (0x00) + Protocol (0x06 = TCP)
    mov byte [rdi + 8], 0
    mov byte [rdi + 9], 6

    ; TCP Length (big endian)
    mov rax, r12
    xchg al, ah
    mov [rdi + 10], ax

    ; 1. Compute Checksum of Pseudo-Header (12 bytes)
    lea rcx, [rsp + 0]
    mov rdx, 12
    call ip_get_checksum
    not ax                          ; ip_get_checksum returns NOT of sum, so invert back!
    movzx r11d, ax                  ; r11d = pseudo checksum sum

    ; 2. Compute Checksum of TCP Header + Payload
    mov rcx, rsi
    mov rdx, r12
    call ip_get_checksum
    not ax
    movzx eax, ax

    ; Add them together
    add eax, r11d

    ; Fold 32-bit to 16-bit
.fold:
    mov ebx, eax
    shr ebx, 16
    and eax, 0xFFFF
    add eax, ebx
    cmp eax, 0xFFFF
    ja .fold

    not ax                          ; Final ones' complement
    
    add rsp, 64
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

section .data
msg_tcp_syn db "TCP: SYN received, sending SYN-ACK", 13, 10, 0
msg_tcp_pkt db "TCP-PKT", 13, 10, 0
msg_tcp_est db "TCP: ESTABLISHED", 13, 10, 0

section .bss
align 16
tcp_sockets resb MAX_SOCKETS * SOCKET_SIZE
