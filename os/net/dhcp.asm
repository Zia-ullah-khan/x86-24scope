; ==============================================================================
; x86-24scope OS - DHCP Client Driver
; ==============================================================================
bits 64
default rel

section .text

global dhcp_init
global dhcp_handle_packet
global dhcp_get_our_ip
global dhcp_get_gateway_ip
global dhcp_get_subnet_mask
global dhcp_is_bound

extern udp_send
extern wifi_get_mac
extern wifi_recv_packet
extern wifi_is_loopback
extern e1000_is_qemu
extern e1000_dump_stats
extern wifi_needs_association
extern wifi_is_associated
extern net_handle_packet
extern con_puts
extern con_put_dec
extern con_put_hex
extern con_newline
extern serial_puts
extern serial_put_hex
extern get_ticks
extern sleep_ms

; DHCP Client States
STATE_INIT          equ 0
STATE_DISCOVERING   equ 1
STATE_REQUESTING    equ 2
STATE_BOUND         equ 3

; DHCP Packet structure offsets
DHCP_OP             equ 0           ; 1 = Request, 2 = Reply
DHCP_HTYPE          equ 1           ; 1 = Ethernet
DHCP_HLEN           equ 2           ; 6
DHCP_HOPS           equ 3           ; 0
DHCP_XID            equ 4           ; Transaction ID (4 bytes)
DHCP_SECS           equ 8           ; 0 (2 bytes)
DHCP_FLAGS          equ 10          ; 0x8000 = Broadcast (2 bytes)
DHCP_CIADDR         equ 12          ; Client IP (4 bytes)
DHCP_YIADDR         equ 16          ; Your IP (4 bytes)
DHCP_SIADDR         equ 20          ; Next Server IP (4 bytes)
DHCP_GIADDR         equ 24          ; Relay Agent IP (4 bytes)
DHCP_CHADDR         equ 28          ; Client MAC (16 bytes)
DHCP_SNAME          equ 44          ; Server Name (64 bytes)
DHCP_FILE           equ 108         ; Boot File Name (128 bytes)
DHCP_COOKIE         equ 236         ; Magic Cookie (0x63, 0x82, 0x53, 0x63)

dhcp_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov byte [dhcp_state], STATE_INIT
    mov dword [our_ip], 0
    mov dword [gateway_ip], 0
    mov dword [subnet_mask], 0

    lea rcx, [msg_dhcp_start]
    call con_puts
    lea rcx, [msg_dhcp_start]
    call serial_puts

    ; No external NIC: skip discover wait and bind loopback address
    call wifi_is_loopback
    test rax, rax
    jnz .loopback_bind

    ; Wireless not associated yet: do not spam Discover
    call wifi_needs_association
    test rax, rax
    jz .start_discover
    call wifi_is_associated
    test rax, rax
    jnz .start_discover
    lea rcx, [msg_dhcp_no_assoc]
    call con_puts
    lea rcx, [msg_dhcp_no_assoc]
    call serial_puts
    jmp .fallback

.start_discover:
    call dhcp_send_discover
    call get_ticks
    mov rbx, rax
    add rbx, 10000                  ; 10 second timeout
    mov r12, rax
    add r12, 2000                   ; retransmit every 2s

.poll_loop:
    cmp byte [dhcp_state], STATE_BOUND
    je .done

    call get_ticks
    cmp rax, rbx
    jae .fallback

    ; Retransmit DISCOVER while still discovering
    cmp byte [dhcp_state], STATE_DISCOVERING
    jne .pump_rx
    cmp rax, r12
    jb .pump_rx
    push rax
    lea rcx, [msg_dhcp_retry]
    call con_puts
    lea rcx, [msg_dhcp_retry]
    call serial_puts
    call dhcp_send_discover
    pop rax
    add rax, 2000
    mov r12, rax

.pump_rx:
    ; Pump RX so OFFER/ACK can arrive under polling drivers (e1000/QEMU)
    lea rcx, [dhcp_rx_buf]
    call wifi_recv_packet
    test rax, rax
    jz .no_rx
    push rax
    lea rcx, [msg_dhcp_rx]
    call con_puts
    pop rax
    push rax
    mov rcx, rax
    call con_put_dec
    call con_newline
    pop rax
    lea rcx, [dhcp_rx_buf]
    mov rdx, rax
    call net_handle_packet
.no_rx:
    mov rcx, 10
    call sleep_ms
    jmp .poll_loop

.loopback_bind:
    mov dword [our_ip], 0x0100007F      ; 127.0.0.1
    mov dword [gateway_ip], 0x0100007F
    mov dword [subnet_mask], 0x000000FF ; 255.0.0.0
    mov byte [dhcp_state], STATE_BOUND
    lea rcx, [msg_dhcp_loopback]
    call con_puts
    lea rcx, [msg_dhcp_loopback]
    call serial_puts
    call dhcp_print_config
    jmp .done

.fallback:
    ; Only invent 10.0.2.15 for QEMU's 82540EM (device 0x100E)
    call e1000_is_qemu
    test rax, rax
    jz .no_lease
    mov dword [our_ip], 0x0F02000A   ; 10.0.2.15
    mov dword [gateway_ip], 0x0202000A ; 10.0.2.2
    mov dword [subnet_mask], 0x00FFFFFF ; 255.255.255.0
    mov byte [dhcp_state], STATE_BOUND

    lea rcx, [msg_dhcp_timeout]
    call con_puts
    lea rcx, [msg_dhcp_timeout]
    call serial_puts
    call dhcp_print_config
    jmp .done

.no_lease:
    mov dword [our_ip], 0
    mov dword [gateway_ip], 0
    mov dword [subnet_mask], 0
    mov byte [dhcp_state], STATE_INIT
    lea rcx, [msg_dhcp_nolease]
    call con_puts
    lea rcx, [msg_dhcp_nolease]
    call serial_puts
    call e1000_dump_stats
    jmp .done

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; Send DHCP DISCOVER
dhcp_send_discover:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    sub rsp, 512                    ; Allocate 512-byte stack buffer for DHCP packet

    mov rbx, rsp                    ; rbx = start of packet
    
    ; Clear buffer
    mov rdi, rbx
    mov rcx, 64
    xor rax, rax
    rep stosq

    ; Build header
    mov byte [rbx + DHCP_OP], 1     ; Boot Request
    mov byte [rbx + DHCP_HTYPE], 1  ; Ethernet
    mov byte [rbx + DHCP_HLEN], 6   ; MAC size = 6
    mov dword [rbx + DHCP_XID], 0x3903F399 ; Transaction ID (hardcoded)
    mov word [rbx + DHCP_FLAGS], 0x0080 ; Broadcast flag (0x8000 big endian)

    ; Client MAC (chaddr)
    lea rcx, [rbx + DHCP_CHADDR]
    call wifi_get_mac

    ; Magic Cookie: 0x63, 0x82, 0x53, 0x63 (big endian: 0x63538263)
    mov dword [rbx + DHCP_COOKIE], 0x63538263

    ; Options (starts at offset 240)
    lea rdi, [rbx + 240]

    ; Option 53: DHCP Message Type (Length 1, Value 1 = DISCOVER)
    mov byte [rdi + 0], 53
    mov byte [rdi + 1], 1
    mov byte [rdi + 2], 1
    add rdi, 3

    ; Option 55: Parameter Request List (Length 3, Subnet Mask, Router, DNS)
    mov byte [rdi + 0], 55
    mov byte [rdi + 1], 3
    mov byte [rdi + 2], 1           ; Subnet Mask
    mov byte [rdi + 3], 3           ; Router (Gateway)
    mov byte [rdi + 4], 6           ; DNS Server
    add rdi, 5

    ; Option 255: End
    mov byte [rdi + 0], 255
    inc rdi

    ; Calculate total size
    mov r10, rdi
    sub r10, rbx                    ; r10 = packet size

    ; Send UDP: src 68, dst 67, ip 255.255.255.255, payload rbx, size r10
    mov ecx, 68                     ; src port
    mov edx, 67                     ; dst port
    mov r8d, 0xFFFFFFFF             ; Broadcast IP
    mov r9, rbx                     ; Payload
    push r10                        ; 5th arg: payload size
    sub rsp, 32                     ; shadow
    call udp_send
    add rsp, 40

    mov byte [dhcp_state], STATE_DISCOVERING

    add rsp, 512
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

; Send DHCP REQUEST
; RCX = Offered IP
; RDX = DHCP Server IP
dhcp_send_request:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    sub rsp, 512

    mov r12d, ecx                   ; Offered IP
    mov r13d, edx                   ; Server IP
    mov rbx, rsp                    ; rbx = start of packet

    ; Clear buffer
    mov rdi, rbx
    mov rcx, 64
    xor rax, rax
    rep stosq

    ; Build header
    mov byte [rbx + DHCP_OP], 1
    mov byte [rbx + DHCP_HTYPE], 1
    mov byte [rbx + DHCP_HLEN], 6
    mov dword [rbx + DHCP_XID], 0x3903F399
    mov word [rbx + DHCP_FLAGS], 0x0080

    ; MAC
    lea rcx, [rbx + DHCP_CHADDR]
    call wifi_get_mac

    ; Magic Cookie
    mov dword [rbx + DHCP_COOKIE], 0x63538263

    ; Options
    lea rdi, [rbx + 240]

    ; Option 53: DHCP Message Type (Value 3 = REQUEST)
    mov byte [rdi + 0], 53
    mov byte [rdi + 1], 1
    mov byte [rdi + 2], 3
    add rdi, 3

    ; Option 50: Requested IP Address (Length 4)
    mov byte [rdi + 0], 50
    mov byte [rdi + 1], 4
    mov eax, r12d
    mov [rdi + 2], eax
    add rdi, 6

    ; Option 54: DHCP Server Identifier (Length 4)
    mov byte [rdi + 0], 54
    mov byte [rdi + 1], 4
    mov eax, r13d
    mov [rdi + 2], eax
    add rdi, 6

    ; Option 255: End
    mov byte [rdi + 0], 255
    inc rdi

    ; Calculate total size
    mov r10, rdi
    sub r10, rbx

    ; Send UDP
    mov ecx, 68
    mov edx, 67
    mov r8d, 0xFFFFFFFF
    mov r9, rbx
    push r10
    sub rsp, 32
    call udp_send
    add rsp, 40

    mov byte [dhcp_state], STATE_REQUESTING

    add rsp, 512
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

; Handle incoming DHCP packets
; RCX = Payload pointer
; RDX = Length
dhcp_handle_packet:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    mov rbx, rcx                    ; rbx = DHCP packet start
    mov r12, rdx                    ; r12 = length

    ; Verify boot reply (op = 2)
    mov al, [rbx + DHCP_OP]
    cmp al, 2
    jne .done

    ; Verify transaction ID
    mov eax, [rbx + DHCP_XID]
    cmp eax, 0x3903F399
    jne .done

    ; Extract Offered IP (yiaddr)
    mov r13d, [rbx + DHCP_YIADDR]   ; r13d = Offered IP (our future IP)

    ; Parse Options (starts at offset 240)
    lea rsi, [rbx + 240]
    xor r14d, r14d                  ; r14d = server IP
    xor r10d, r10d                  ; r10d = subnet mask
    xor r11d, r11d                  ; r11d = gateway IP
    xor r8d, r8d                    ; r8d = message type (Option 53)

.parse_loop:
    movzx eax, byte [rsi]           ; Option code
    cmp al, 255                     ; End option
    je .parse_done

    movzx edx, byte [rsi + 1]       ; Option length

    cmp al, 53                      ; Message Type
    jne .check_subnet
    movzx r8d, byte [rsi + 2]       ; Save message type
    jmp .next_option

.check_subnet:
    cmp al, 1                       ; Subnet Mask
    jne .check_router
    mov r10d, [rsi + 2]             ; Save subnet mask
    jmp .next_option

.check_router:
    cmp al, 3                       ; Router (Gateway)
    jne .check_server
    mov r11d, [rsi + 2]             ; Save gateway
    jmp .next_option

.check_server:
    cmp al, 54                      ; Server ID
    jne .next_option
    mov r14d, [rsi + 2]             ; Save server IP

.next_option:
    lea rsi, [rsi + rdx + 2]        ; Move to next option
    jmp .parse_loop

.parse_done:
    ; Process based on current state and message type in r8d
    cmp byte [dhcp_state], STATE_DISCOVERING
    jne .check_requesting

    ; DISCOVERING state: we expect OFFER (r8d = 2)
    cmp r8d, 2
    jne .done

    ; Send REQUEST
    mov ecx, r13d                   ; Offered IP
    mov edx, r14d                   ; Server IP
    call dhcp_send_request
    jmp .done

.check_requesting:
    cmp byte [dhcp_state], STATE_REQUESTING
    jne .done

    ; REQUESTING state: we expect ACK (r8d = 5)
    cmp r8d, 5
    jne .done

    ; Bound! Save configuration
    mov [our_ip], r13d
    mov [subnet_mask], r10d
    mov [gateway_ip], r11d
    mov byte [dhcp_state], STATE_BOUND

    lea rcx, [msg_dhcp_bound]
    call con_puts
    lea rcx, [msg_dhcp_bound]
    call serial_puts

    call dhcp_print_config

.done:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; Print current network config
dhcp_print_config:
    push rbx
    
    lea rcx, [msg_ip]
    call con_puts
    lea rcx, [msg_ip]
    call serial_puts
    mov ecx, [our_ip]
    call print_ip
    call con_newline
    lea rcx, [dhcp_newline]
    call serial_puts

    lea rcx, [msg_mask]
    call con_puts
    lea rcx, [msg_mask]
    call serial_puts
    mov ecx, [subnet_mask]
    call print_ip
    call con_newline
    lea rcx, [dhcp_newline]
    call serial_puts

    lea rcx, [msg_gw]
    call con_puts
    lea rcx, [msg_gw]
    call serial_puts
    mov ecx, [gateway_ip]
    call print_ip
    call con_newline
    lea rcx, [dhcp_newline]
    call serial_puts

    pop rbx
    ret

; Print IP Address in dotted format
; RCX = IP address (4 bytes)
print_ip:
    push rbx
    mov ebx, ecx
    ; Also dump raw LE dword to serial for debugging
    push rcx
    call serial_put_hex
    pop rcx

    ; Byte 1
    movzx ecx, bl
    call con_put_dec
    call print_dot

    ; Byte 2
    mov ecx, ebx
    shr ecx, 8
    movzx ecx, cl
    call con_put_dec
    call print_dot

    ; Byte 3
    mov ecx, ebx
    shr ecx, 16
    movzx ecx, cl
    call con_put_dec
    call print_dot

    ; Byte 4
    mov ecx, ebx
    shr ecx, 24
    movzx ecx, cl
    call con_put_dec

    pop rbx
    ret

print_dot:
    push rcx
    mov rcx, '.'
    extern con_putchar
    call con_putchar
    pop rcx
    ret

dhcp_get_our_ip:
    mov eax, [our_ip]
    ret

dhcp_get_gateway_ip:
    mov eax, [gateway_ip]
    ret

dhcp_get_subnet_mask:
    mov eax, [subnet_mask]
    ret

dhcp_is_bound:
    xor rax, rax
    cmp byte [dhcp_state], STATE_BOUND
    sete al
    ret

section .data
align 8
our_ip dd 0
gateway_ip dd 0
subnet_mask dd 0
dhcp_state db STATE_INIT

msg_dhcp_start db "DHCP: Requesting IP address (discovering)...", 13, 10, 0
msg_dhcp_bound db "DHCP: Lease bound successfully!", 13, 10, 0
msg_dhcp_timeout db "DHCP: Request timeout. Using fallback static IP.", 13, 10, 0
msg_dhcp_nolease db "DHCP: No lease (real NIC needs working link/WiFi ALIVE).", 13, 10, 0
msg_dhcp_retry db "DHCP: Retransmitting DISCOVER...", 13, 10, 0
msg_dhcp_rx db "DHCP: RX frame bytes=", 0
msg_dhcp_loopback db "DHCP: Loopback only — bound 127.0.0.1 (no external NIC).", 13, 10, 0
msg_dhcp_no_assoc db "DHCP: WiFi not associated; using fallback IP.", 13, 10, 0
msg_ip db "  IP Address:  ", 0
msg_mask db "  Subnet Mask: ", 0
msg_gw db "  Gateway IP:  ", 0
dhcp_newline db 13, 10, 0

section .bss
align 16
dhcp_rx_buf resb 2048
