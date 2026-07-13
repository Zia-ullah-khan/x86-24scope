; ==============================================================================
; x86-24scope OS - TUI Dashboard & Console Renderer
; ==============================================================================
bits 64
default rel

section .text

global tui_init
global tui_update
global tui_add_log

extern con_clear
extern con_puts
extern con_newline
extern con_putchar
extern con_put_hex
extern con_put_dec
extern dhcp_get_our_ip
extern dhcp_get_subnet_mask
extern dhcp_get_gateway_ip
extern get_ticks

; Colors
COLOR_BG            equ 0x08111F    ; Deep blue background
COLOR_TEXT          equ 0xE5EEFC    ; Off-white text
COLOR_ACCENT        equ 0x56D4FF    ; Bright cyan accent
COLOR_MUTED         equ 0x8EA2C8    ; Muted blue-grey

tui_init:
    ; Do not clear: keep the kernel init log visible for diagnostics
    push rbp
    mov rbp, rsp
    call tui_draw_static_layout
    call tui_update
    pop rbp
    ret

tui_draw_static_layout:
    push rbx
    push rdi

    ; 1. Draw Title Header
    ; Set cursor positions and print title
    ; Since we don't have direct coordinate setting APIs in console.asm,
    ; we can just print standard formatted string lines to form our boxes!
    lea rcx, [msg_header_border]
    call con_puts
    lea rcx, [msg_header_title]
    call con_puts
    lea rcx, [msg_header_border]
    call con_puts
    call con_newline

    ; 2. Draw Network Info Pane Header
    lea rcx, [msg_net_header]
    call con_puts
    call con_newline

    pop rdi
    pop rbx
    ret

tui_update:
    push rbp
    mov rbp, rsp
    push rbx

    ; To update dynamic values in a pure terminal console without cursor positioning,
    ; we can just rewrite the screen or print status updates sequentially.
    ; For a clean bare-metal console, printing status lines on state changes works great!
    ; Let's output network configuration status:
    lea rcx, [msg_net_status]
    call con_puts

    pop rbx
    pop rbp
    ret

; Add log entry to the TUI server log pane
; RCX = Null-terminated log message pointer
tui_add_log:
    push rbx
    push rcx

    mov rbx, rcx                    ; rbx = log msg

    ; Print timestamp
    lea rcx, [msg_bracket_open]
    call con_puts
    call get_ticks
    mov rcx, rax
    call con_put_dec
    lea rcx, [msg_bracket_close]
    call con_puts

    ; Print message
    mov rcx, rbx
    call con_puts
    call con_newline

    pop rcx
    pop rbx
    ret

section .data
msg_header_border db "================================================================================", 13, 10, 0
msg_header_title  db "               * * *   2 4 S C O P E   B A R E - M E T A L   O S   * * *        ", 13, 10, 0
msg_net_header    db "--- NETWORK SYSTEM DASHBOARD ---------------------------------------------------", 0
msg_net_status    db "  [System Status]: ACTIVE | [Web Server]: listening on port 8091", 13, 10, 0
msg_bracket_open  db " [", 0
msg_bracket_close db "ms] : ", 0
