; ==============================================================================
; x86-24scope OS - Software Loopback Network Driver
; ==============================================================================
bits 64
default rel

section .text

global loopback_driver_init
global loopback_driver_send
global loopback_driver_recv
global loopback_driver_get_mac

extern con_puts
extern serial_puts

loopback_driver_init:
    push rcx
    lea rcx, [msg_loopback]
    call con_puts
    lea rcx, [msg_loopback]
    call serial_puts
    mov qword [loopback_len], 0
    pop rcx
    mov rax, 1
    ret

loopback_driver_get_mac:
    push rsi
    push rdi
    push rcx
    lea rsi, [loopback_mac]
    mov rdi, rcx
    mov rcx, 6
    rep movsb
    pop rcx
    pop rdi
    pop rsi
    ret

; RCX = packet, RDX = length
loopback_driver_send:
    push rsi
    push rdi
    push rcx
    mov rsi, rcx
    lea rdi, [loopback_buf]
    mov rcx, rdx
    cmp rcx, 2048
    jbe .copy
    mov rcx, 2048
.copy:
    mov [loopback_len], rcx
    rep movsb
    pop rcx
    pop rdi
    pop rsi
    ret

; RCX = dest -> RAX = len
loopback_driver_recv:
    push rsi
    push rdi
    mov rax, [loopback_len]
    test rax, rax
    jz .empty
    mov rsi, rcx
    lea rdi, [loopback_buf]
    mov rcx, rax
    xchg rsi, rdi
    rep movsb
    mov qword [loopback_len], 0
.empty:
    pop rdi
    pop rsi
    ret

section .data
align 8
loopback_mac db 0x52, 0x54, 0x00, 0x12, 0x34, 0x56
msg_loopback db "Net: Loopback interface active (no external NIC).", 13, 10, 0

section .bss
align 16
loopback_buf resb 2048
loopback_len resq 1
