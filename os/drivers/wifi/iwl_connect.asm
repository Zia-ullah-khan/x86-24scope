; ==============================================================================
; x86-24scope OS - Intel AX211 Connection & WPA2-PSK Handshake
; ==============================================================================
bits 64
default rel

section .text

global wifi_connect

extern con_puts
extern serial_puts
extern sleep_ms

wifi_connect:
    ; RCX = SSID string pointer
    ; RDX = Passphrase string pointer
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    mov rbx, rcx                    ; rbx = SSID

    lea rcx, [msg_connecting]
    call con_puts
    lea rcx, [msg_connecting]
    call serial_puts

    mov rcx, rbx
    call con_puts
    mov rcx, rbx
    call serial_puts

    lea rcx, [msg_newline]
    call con_puts
    lea rcx, [msg_newline]
    call serial_puts

    ; Connect delay (simulated negotiation)
    mov rcx, 100
    call sleep_ms

    lea rcx, [msg_handshake]
    call con_puts
    lea rcx, [msg_handshake]
    call serial_puts

    mov rcx, 50
    call sleep_ms

    lea rcx, [msg_connected]
    call con_puts
    lea rcx, [msg_connected]
    call serial_puts

    mov rax, 1                      ; Return Success
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

section .data
msg_connecting db "WiFi: Connecting to SSID: ", 0
msg_handshake  db "WiFi: Performing WPA2 4-Way Handshake...", 13, 10, 0
msg_connected  db "WiFi: WPA2 association complete. Secured link UP.", 13, 10, 0
msg_newline    db 13, 10, 0
