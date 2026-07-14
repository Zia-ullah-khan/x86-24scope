; ==============================================================================
; x86-24scope OS - Intel iwlwifi connect (WPA2-PSK + MVM station bind)
; RCX = SSID, RDX = PSK ??? RAX = 1 on success
; ==============================================================================
bits 64
default rel

section .text

global iwl_wifi_connect

extern wifi_send_cmd
extern iwl_wifi_scan
extern iwl_assoc_flag
extern pbkdf2_sha1
extern prf_384
extern con_puts
extern serial_puts
extern sleep_ms

; MVM / legacy command IDs (subset)
REPLY_ERROR             equ 0x02
TX_CMD                  equ 0x1c
PHY_CONTEXT_CMD         equ 0x8
BINDING_CONTEXT_CMD     equ 0x2b
MAC_CONTEXT_CMD         equ 0x28
STA_CONTEXT_CMD         equ 0x18
ADD_STA_KEY             equ 0x17
LQ_CMD                  equ 0x4e
SCAN_OFFLOAD_REQUEST    equ 0x51

iwl_wifi_connect:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov rbx, rcx                    ; SSID
    mov r12, rdx                    ; PSK
    test rbx, rbx
    jz .fail

    lea rcx, [msg_conn]
    call con_puts
    lea rcx, [msg_conn]
    call serial_puts
    mov rcx, rbx
    call con_puts
    lea rcx, [msg_nl]
    call con_puts

    ; Copy SSID / measure length
    lea rdi, [ssid_buf]
    mov rsi, rbx
    xor r13d, r13d
.copy_ssid:
    lodsb
    stosb
    test al, al
    jz .ssid_done
    inc r13d
    cmp r13d, 32
    jb .copy_ssid
    mov byte [rdi - 1], 0
.ssid_done:

    ; Copy PSK
    lea rdi, [psk_buf]
    xor eax, eax
    mov ecx, 64
    rep stosb
    test r12, r12
    jz .open_net
    lea rdi, [psk_buf]
    mov rsi, r12
    mov ecx, 63
.copy_psk:
    lodsb
    stosb
    test al, al
    jz .psk_done
    loop .copy_psk
.psk_done:

    ; PBKDF2-SHA1 ??? PMK (32 bytes)
    lea rcx, [msg_pmk]
    call con_puts
    lea rcx, [msg_pmk]
    call serial_puts

    lea rcx, [psk_buf]
    lea rdx, [ssid_buf]
    mov r8, r13
    mov r9, 4096
    lea rax, [pmk]
    push rax
    sub rsp, 32
    call pbkdf2_sha1
    add rsp, 40

    ; Build PTK material placeholder (ANonce/SNonce zeros until 4-way)
    lea rdi, [ptk_data]
    xor eax, eax
    mov rcx, 76 / 4
    rep stosd
    lea rcx, [pmk]
    lea rdx, [label_ptk]
    lea r8, [ptk_data]
    lea r9, [ptk]
    call prf_384

.open_net:
    ; Scan first
    call iwl_wifi_scan

    ; MAC context add (station)
    lea rdi, [iwl_conn_cmd]
    mov rcx, 256 / 8
    xor eax, eax
    rep stosq
    mov byte [iwl_conn_cmd], 1           ; action = add
    mov byte [iwl_conn_cmd + 1], 0       ; id
    mov byte [iwl_conn_cmd + 2], 0       ; mac_type = BSS STA
    ; Copy SSID into mac ctxt
    lea rsi, [ssid_buf]
    lea rdi, [iwl_conn_cmd + 16]
    mov ecx, 32
    rep movsb

    mov ecx, MAC_CONTEXT_CMD
    lea rdx, [iwl_conn_cmd]
    mov r8, 128
    mov r9, 1
    call wifi_send_cmd

    ; PHY context
    lea rdi, [iwl_conn_cmd]
    mov rcx, 64 / 8
    xor eax, eax
    rep stosq
    mov byte [iwl_conn_cmd], 1
    mov ecx, PHY_CONTEXT_CMD
    lea rdx, [iwl_conn_cmd]
    mov r8, 64
    mov r9, 1
    call wifi_send_cmd

    ; Binding
    lea rdi, [iwl_conn_cmd]
    mov rcx, 64 / 8
    xor eax, eax
    rep stosq
    mov byte [iwl_conn_cmd], 1
    mov ecx, BINDING_CONTEXT_CMD
    lea rdx, [iwl_conn_cmd]
    mov r8, 32
    mov r9, 1
    call wifi_send_cmd

    ; Station context
    lea rdi, [iwl_conn_cmd]
    mov rcx, 128 / 8
    xor eax, eax
    rep stosq
    mov byte [iwl_conn_cmd], 1           ; add
    mov ecx, STA_CONTEXT_CMD
    lea rdx, [iwl_conn_cmd]
    mov r8, 96
    mov r9, 1
    call wifi_send_cmd

    ; Install PTK/GTK keys when PSK present (ADD_STA_KEY)
    cmp byte [psk_buf], 0
    jz .no_key
    lea rdi, [iwl_conn_cmd]
    mov rcx, 128 / 8
    xor eax, eax
    rep stosq
    mov byte [iwl_conn_cmd], 1           ; add key
    ; Copy TK (16 bytes from PTK offset 32)
    lea rsi, [ptk + 32]
    lea rdi, [iwl_conn_cmd + 16]
    mov rcx, 16
    rep movsb
    mov ecx, ADD_STA_KEY
    lea rdx, [iwl_conn_cmd]
    mov r8, 64
    mov r9, 1
    call wifi_send_cmd
.no_key:

    mov rcx, 100
    call sleep_ms

    mov byte [iwl_assoc_flag], 1
    lea rcx, [msg_up]
    call con_puts
    lea rcx, [msg_up]
    call serial_puts
    mov rax, 1
    jmp .done

.fail:
    mov byte [iwl_assoc_flag], 0
    xor rax, rax
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

section .data
label_ptk db "Pairwise key expansion", 0
msg_conn db "WiFi: Connecting to ", 0
msg_nl db 13, 10, 0
msg_pmk db "WiFi: Deriving WPA2 PMK (PBKDF2)...", 13, 10, 0
msg_up db "WiFi: Station bind commands sent; link marked UP.", 13, 10, 0

section .bss
align 16
ssid_buf resb 33
psk_buf resb 64
pmk resb 32
ptk resb 48
ptk_data resb 80
iwl_conn_cmd resb 256

