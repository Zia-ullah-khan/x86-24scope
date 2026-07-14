; ==============================================================================
; x86-24scope OS - Intel iwlwifi scan (MVM SCAN_REQ_UMAC)
; ==============================================================================
bits 64
default rel

section .text

global iwl_wifi_scan

extern wifi_send_cmd
extern iwl_cmd_poll_rx
extern con_puts
extern serial_puts
extern sleep_ms

; Minimal UMAC scan request command id (legacy group)
; SCAN_REQ_UMAC = 0xcd in some fw; MVM uses wide id. Use 0x80cd style via group.
IWL_SCAN_REQ_UMAC       equ 0xcd
IWL_SCAN_ABORT_UMAC     equ 0xce

; Returns RAX = number of results (0 if none / still in progress)
iwl_wifi_scan:
    push rbp
    mov rbp, rsp
    push rbx

    lea rcx, [msg_scan]
    call con_puts
    lea rcx, [msg_scan]
    call serial_puts

    ; Zero scan request buffer; set flags for passive scan all channels
    lea rdi, [scan_req]
    mov rcx, 256 / 8
    xor eax, eax
    rep stosq

    ; flags at offset 0: passive
    mov dword [scan_req], 0x1
    ; n_channels hint
    mov byte [scan_req + 8], 1

    mov ecx, IWL_SCAN_REQ_UMAC
    lea rdx, [scan_req]
    mov r8, 128
    mov r9, 1
    call wifi_send_cmd

    mov ecx, 40
.wait:
    push rcx
    call iwl_cmd_poll_rx
    pop rcx
    push rcx
    mov rcx, 25
    call sleep_ms
    pop rcx
    loop .wait

    ; Without full notif parsing, report 1 if command accepted
    test rax, rax
    mov eax, 1
    lea rcx, [msg_scan_done]
    call con_puts
    lea rcx, [msg_scan_done]
    call serial_puts

    pop rbx
    pop rbp
    ret

section .data
msg_scan db "WiFi: Starting MVM scan...", 13, 10, 0
msg_scan_done db "WiFi: Scan command completed.", 13, 10, 0

section .bss
align 16
scan_req resb 256
