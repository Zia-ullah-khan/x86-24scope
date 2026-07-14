; ==============================================================================
; x86-24scope OS - WiFi credentials (UEFI boot prompt + optional kbd fallback)
; ==============================================================================
bits 64
default rel

section .text

global wifi_cfg_init
global wifi_prompt_credentials
global wifi_cfg_load_from_bootinfo
global wifi_cfg_ssid
global wifi_cfg_psk
global wifi_cfg_ssid_len

extern con_puts
extern serial_puts
extern kbd_readline
extern kbd_init

MAX_SSID equ 32
MAX_PSK  equ 63

BI_WIFI_SSID  equ 80
BI_WIFI_PSK   equ 113
BI_WIFI_VALID equ 177

wifi_cfg_init:
    push rsi
    lea rsi, [wifi_cfg_ssid]
    xor eax, eax
.len:
    cmp byte [rsi + rax], 0
    je .done
    inc eax
    cmp eax, MAX_SSID
    jb .len
.done:
    mov [wifi_cfg_ssid_len], eax
    pop rsi
    ret

; RCX = BootInfo pointer
; RAX = 1 if SSID was copied from UEFI prompt
wifi_cfg_load_from_bootinfo:
    push rbx
    push rsi
    push rdi

    xor eax, eax
    test rcx, rcx
    jz .done
    mov rbx, rcx
    cmp byte [rbx + BI_WIFI_VALID], 0
    jz .done
    cmp byte [rbx + BI_WIFI_SSID], 0
    jz .done

    lea rsi, [rbx + BI_WIFI_SSID]
    lea rdi, [wifi_cfg_ssid]
    mov ecx, MAX_SSID + 1
    rep movsb

    lea rsi, [rbx + BI_WIFI_PSK]
    lea rdi, [wifi_cfg_psk]
    mov ecx, MAX_PSK + 1
    rep movsb

    call wifi_cfg_init
    mov eax, 1

.done:
    pop rdi
    pop rsi
    pop rbx
    ret

; Fallback prompt using PS/2/serial (may not work on USB-only laptop keyboards).
; Prefer UEFI prompt in boot.asm. RAX = 1 if SSID non-empty.
wifi_prompt_credentials:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi

    call kbd_init

    lea rdi, [wifi_cfg_ssid]
    xor eax, eax
    mov ecx, MAX_SSID + 1
    rep stosb
    lea rdi, [wifi_cfg_psk]
    mov ecx, MAX_PSK + 1
    rep stosb
    mov dword [wifi_cfg_ssid_len], 0

    lea rcx, [wcfg_msg_banner]
    call con_puts
    lea rcx, [wcfg_msg_banner]
    call serial_puts
    lea rcx, [wcfg_msg_hint]
    call con_puts
    lea rcx, [wcfg_msg_hint]
    call serial_puts

    lea rcx, [wcfg_msg_ssid]
    call con_puts
    lea rcx, [wcfg_msg_ssid]
    call serial_puts

    lea rcx, [wifi_cfg_ssid]
    mov rdx, MAX_SSID + 1
    xor r8, r8
    call kbd_readline
    mov [wifi_cfg_ssid_len], eax
    test eax, eax
    jz .empty

    lea rcx, [wcfg_msg_psk]
    call con_puts
    lea rcx, [wcfg_msg_psk]
    call serial_puts

    lea rcx, [wifi_cfg_psk]
    mov rdx, MAX_PSK + 1
    mov r8, 1
    call kbd_readline

    lea rcx, [wcfg_msg_creds_ok]
    call con_puts
    lea rcx, [wcfg_msg_creds_ok]
    call serial_puts
    mov rax, 1
    jmp .done

.empty:
    lea rcx, [wcfg_msg_empty]
    call con_puts
    lea rcx, [wcfg_msg_empty]
    call serial_puts
    xor rax, rax

.done:
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

section .data
align 4
wifi_cfg_ssid_len dd 0

wcfg_msg_banner db 13, 10, "======== WiFi setup (kernel kbd) ========", 13, 10, 0
wcfg_msg_hint   db "If this keyboard is dead, reboot and type at the UEFI prompt.", 13, 10, 0
wcfg_msg_ssid   db "SSID: ", 0
wcfg_msg_psk    db "Password: ", 0
wcfg_msg_creds_ok db "Credentials accepted.", 13, 10, 0
wcfg_msg_empty  db "No SSID entered; skipping WiFi connect.", 13, 10, 0

section .bss
alignb 16
wifi_cfg_ssid resb MAX_SSID + 1
wifi_cfg_psk  resb MAX_PSK + 1
