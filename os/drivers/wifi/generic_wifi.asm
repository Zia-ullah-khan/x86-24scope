; ==============================================================================
; x86-24scope OS - WiFi ops dispatcher (swappable backends)
; Soft-MAC fallback + registration for real chip backends (iwl, ...).
; ==============================================================================
bits 64
default rel

section .text

global generic_wifi_driver_init
global generic_wifi_driver_send
global generic_wifi_driver_recv
global generic_wifi_driver_get_mac
global wifi_scan
global wifi_connect
global wifi_is_associated
global wifi_try_connect
global wifi_register_ops
global wifi_needs_association
global wifi_set_ready

extern con_puts
extern serial_puts
extern sleep_ms
extern wifi_cfg_ssid
extern wifi_cfg_psk
extern wifi_cfg_ssid_len
extern wifi_cfg_init
extern wifi_prompt_credentials
extern wifi_cfg_load_from_bootinfo

WIFI_STATE_DOWN        equ 0
WIFI_STATE_IDLE        equ 1
WIFI_STATE_SCANNING    equ 2
WIFI_STATE_ASSOCIATING equ 3
WIFI_STATE_ASSOCIATED  equ 4

MAX_SSID_LEN           equ 32
MAX_PSK_LEN            equ 63

; Ops table layout (function pointers):
; +0  scan() -> RAX=count
; +8  connect(RCX=ssid, RDX=psk) -> RAX=1/0
; +16 is_associated() -> RAX=1/0
OPS_SCAN    equ 0
OPS_CONNECT equ 8
OPS_ASSOC   equ 16

; RCX = pointer to 3 qword ops table (or 0 to restore soft)
wifi_register_ops:
    test rcx, rcx
    jz .soft
    mov rax, [rcx + OPS_SCAN]
    mov [ops_scan], rax
    mov rax, [rcx + OPS_CONNECT]
    mov [ops_connect], rax
    mov rax, [rcx + OPS_ASSOC]
    mov [ops_assoc], rax
    mov byte [ops_active], 1
    ret
.soft:
    lea rax, [soft_wifi_scan]
    mov [ops_scan], rax
    lea rax, [soft_wifi_connect]
    mov [ops_connect], rax
    lea rax, [soft_wifi_is_associated]
    mov [ops_assoc], rax
    mov byte [ops_active], 0
    ret

; AL = 1/0 — mark wireless path ready for wifi_try_connect
wifi_set_ready:
    mov [wifi_ready], al
    ret

; RAX = 1 if a wireless backend that must associate before DHCP
wifi_needs_association:
    cmp byte [wifi_ready], 0
    jz .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

wifi_scan:
    mov rax, [ops_scan]
    jmp rax

wifi_connect:
    mov rax, [ops_connect]
    jmp rax

wifi_is_associated:
    mov rax, [ops_assoc]
    jmp rax

; Boot helper: use UEFI BootInfo creds if present, else kernel kbd prompt.
; RAX = 1 if associated (or non-wifi).
wifi_try_connect:
    push rbp
    mov rbp, rsp
    push rbx

    cmp byte [wifi_ready], 0
    jz .not_wifi
    cmp byte [ops_active], 0
    jnz .have_wifi
    cmp byte [soft_ready], 0
    jz .not_wifi

.have_wifi:
    ; Prefer credentials collected in the UEFI bootloader (USB keyboards work there)
    extern boot_info_ptr
    mov rcx, [boot_info_ptr]
    call wifi_cfg_load_from_bootinfo
    test rax, rax
    jnz .connect_now

    ; Fallback: PS/2/serial (often dead on USB-only laptops after ExitBootServices)
    call wifi_prompt_credentials
    test rax, rax
    jz .no_ssid

.connect_now:
    call wifi_cfg_init

    lea rcx, [msg_try]
    call con_puts
    lea rcx, [msg_try]
    call serial_puts

    lea rcx, [wifi_cfg_ssid]
    lea rdx, [wifi_cfg_psk]
    call wifi_connect
    test rax, rax
    jz .fail

    lea rcx, [msg_ok]
    call con_puts
    lea rcx, [msg_ok]
    call serial_puts
    mov rax, 1
    jmp .done

.no_ssid:
    lea rcx, [msg_no_ssid]
    call con_puts
    lea rcx, [msg_no_ssid]
    call serial_puts
    xor rax, rax
    jmp .done

.fail:
    lea rcx, [msg_fail]
    call con_puts
    lea rcx, [msg_fail]
    call serial_puts
    xor rax, rax
    jmp .done

.not_wifi:
    mov rax, 1                      ; Ethernet / loopback: no assoc needed
.done:
    pop rbx
    pop rbp
    ret

; RCX=a, RDX=b -> RAX=1 if equal
str_eq:
    push rsi
    push rdi
    push rbx
    mov rsi, rcx
    mov rdi, rdx
.lp:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .no
    test al, al
    jz .yes
    inc rsi
    inc rdi
    jmp .lp
.yes:
    mov rax, 1
    jmp .out
.no:
    xor rax, rax
.out:
    pop rbx
    pop rdi
    pop rsi
    ret

; ---------- Soft-MAC backend (fallback) ----------

generic_wifi_driver_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi

    mov [wifi_bar], rcx
    mov [wifi_bdf], edx

    lea rcx, [msg_wifi_init]
    call con_puts
    lea rcx, [msg_wifi_init]
    call serial_puts

    mov dword [wifi_state], WIFI_STATE_IDLE
    mov qword [wifi_rx_len], 0
    mov byte [wifi_assoc], 0
    mov byte [soft_ready], 1
    mov byte [wifi_ready], 1

    lea rsi, [wifi_default_mac]
    lea rdi, [wifi_mac]
    mov rcx, 6
    rep movsb

    xor rcx, rcx
    call wifi_register_ops          ; soft defaults already set below
    lea rax, [soft_wifi_scan]
    mov [ops_scan], rax
    lea rax, [soft_wifi_connect]
    mov [ops_connect], rax
    lea rax, [soft_wifi_is_associated]
    mov [ops_assoc], rax

    lea rcx, [msg_wifi_ready]
    call con_puts
    lea rcx, [msg_wifi_ready]
    call serial_puts

    mov rax, 1
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

generic_wifi_driver_get_mac:
    push rsi
    push rdi
    push rcx
    lea rsi, [wifi_mac]
    mov rdi, rcx
    mov rcx, 6
    rep movsb
    pop rcx
    pop rdi
    pop rsi
    ret

soft_wifi_is_associated:
    movzx eax, byte [wifi_assoc]
    ret

soft_wifi_scan:
    push rsi
    push rdi
    cmp byte [soft_ready], 0
    jz .fail
    mov dword [wifi_state], WIFI_STATE_SCANNING
    lea rcx, [msg_wifi_scan]
    call con_puts
    lea rcx, [msg_wifi_scan]
    call serial_puts
    mov rcx, 50
    call sleep_ms
    mov dword [wifi_state], WIFI_STATE_IDLE
    mov eax, 1
    jmp .done
.fail:
    xor eax, eax
.done:
    pop rdi
    pop rsi
    ret

soft_wifi_connect:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov rbx, rcx
    mov r12, rdx
    cmp byte [soft_ready], 0
    jz .fail
    test rbx, rbx
    jz .fail

    mov dword [wifi_state], WIFI_STATE_ASSOCIATING
    lea rcx, [msg_wifi_connecting]
    call con_puts
    lea rcx, [msg_wifi_connecting]
    call serial_puts
    mov rcx, rbx
    call con_puts
    mov rcx, rbx
    call serial_puts
    lea rcx, [msg_wifi_nl]
    call con_puts

    lea rdi, [wifi_ssid]
    mov rsi, rbx
    mov ecx, MAX_SSID_LEN
.copy_ssid:
    lodsb
    stosb
    test al, al
    jz .ssid_done
    loop .copy_ssid
    mov byte [rdi - 1], 0
.ssid_done:

    lea rdi, [wifi_psk]
    xor eax, eax
    mov ecx, MAX_PSK_LEN + 1
    rep stosb
    test r12, r12
    jz .psk_done
    lea rdi, [wifi_psk]
    mov rsi, r12
    mov ecx, MAX_PSK_LEN
.copy_psk:
    lodsb
    stosb
    test al, al
    jz .psk_done
    loop .copy_psk
.psk_done:

    mov rcx, 80
    call sleep_ms
    mov byte [wifi_assoc], 1
    mov dword [wifi_state], WIFI_STATE_ASSOCIATED
    lea rcx, [msg_wifi_up]
    call con_puts
    lea rcx, [msg_wifi_up]
    call serial_puts
    mov rax, 1
    jmp .done
.fail:
    xor rax, rax
.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

generic_wifi_driver_send:
    push rsi
    push rdi
    push rcx
    cmp byte [soft_ready], 0
    jz .drop
    cmp byte [wifi_assoc], 0
    jz .drop
    mov rsi, rcx
    lea rdi, [wifi_rx_buf]
    mov rcx, rdx
    cmp rcx, 2048
    jbe .copy
    mov rcx, 2048
.copy:
    mov [wifi_rx_len], rcx
    rep movsb
.drop:
    pop rcx
    pop rdi
    pop rsi
    ret

generic_wifi_driver_recv:
    push rsi
    push rdi
    xor rax, rax
    cmp byte [soft_ready], 0
    jz .empty
    cmp byte [wifi_assoc], 0
    jz .empty
    mov rax, [wifi_rx_len]
    test rax, rax
    jz .empty
    mov rsi, rcx
    lea rdi, [wifi_rx_buf]
    mov rcx, rax
    xchg rsi, rdi
    rep movsb
    mov qword [wifi_rx_len], 0
.empty:
    pop rdi
    pop rsi
    ret

section .data
align 8
ops_scan    dq soft_wifi_scan
ops_connect dq soft_wifi_connect
ops_assoc   dq soft_wifi_is_associated
ops_active  db 0
wifi_ready  db 0
soft_ready  db 0
wifi_assoc  db 0
align 8
wifi_bar dq 0
wifi_bdf dd 0
wifi_state dd WIFI_STATE_DOWN
wifi_mac db 0x02, 0x00, 0x00, 0x24, 0x53, 0x01
wifi_default_mac db 0x02, 0x00, 0x00, 0x24, 0x53, 0x01

msg_placeholder db 0
msg_try db "WiFi: Associating...", 13, 10, 0
msg_ok db "WiFi: Association succeeded.", 13, 10, 0
msg_fail db "WiFi: Association failed.", 13, 10, 0
msg_no_ssid db "WiFi: No SSID entered; DHCP skipped for wireless.", 13, 10, 0
msg_wifi_init db "Net: Generic WiFi driver init...", 13, 10, 0
msg_wifi_ready db "Net: Generic WiFi soft-MAC ready.", 13, 10, 0
msg_wifi_scan db "WiFi: Soft scan...", 13, 10, 0
msg_wifi_connecting db "WiFi: Soft connecting to: ", 0
msg_wifi_up db "WiFi: Soft-MAC associated.", 13, 10, 0
msg_wifi_nl db 13, 10, 0

section .bss
align 16
wifi_ssid resb MAX_SSID_LEN + 1
wifi_psk resb MAX_PSK_LEN + 1
wifi_rx_buf resb 2048
wifi_rx_len resq 1
