; ==============================================================================
; x86-24scope OS - Realtek RTL8168 / RTL8111 / RTL8169 Ethernet
; Common laptop/desktop PCIe Gigabit Ethernet (vendor 0x10EC).
; ==============================================================================
bits 64
default rel

section .text

global rtl8169_driver_init
global rtl8169_driver_send
global rtl8169_driver_recv
global rtl8169_driver_get_mac

extern con_puts
extern serial_puts
extern con_put_hex
extern con_newline
extern sleep_ms
extern pmm_alloc_page
extern vmm_map_mmio

RTL_MAC0            equ 0x00
RTL_TNPDS           equ 0x20
RTL_CMD             equ 0x37
RTL_TPPOLL          equ 0x38
RTL_IMR             equ 0x3C
RTL_ISR             equ 0x3E
RTL_TCR             equ 0x40
RTL_RCR             equ 0x44
RTL_CFG9346         equ 0x50
RTL_RMS             equ 0xDA
RTL_CPLUSCMD        equ 0xE0
RTL_RDSAR           equ 0xE4

CMD_RESET           equ 0x10
CMD_RX_EN           equ 0x08
CMD_TX_EN           equ 0x04

DESC_OWN            equ 0x80000000
DESC_EOR            equ 0x40000000
DESC_FS             equ 0x20000000
DESC_LS             equ 0x10000000

NUM_RX_DESC         equ 64
NUM_TX_DESC         equ 64
RX_BUF_SIZE         equ 2048

rtl8169_driver_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov [rtl_mmio], rcx
    mov [rtl_bdf], edx

    lea rcx, [msg_rtl_init]
    call con_puts
    lea rcx, [msg_rtl_init]
    call serial_puts

    mov rbx, [rtl_mmio]
    test rbx, rbx
    jz .fail

    mov rcx, rbx
    mov rdx, 0x200000
    call vmm_map_mmio
    test rax, rax
    jz .fail

    lea rcx, [msg_rtl_bar]
    call con_puts
    mov rcx, rbx
    call con_put_hex
    call con_newline

    mov byte [rbx + RTL_CMD], CMD_RESET
    mov ecx, 1000
.wait_rst:
    test byte [rbx + RTL_CMD], CMD_RESET
    jz .rst_ok
    push rcx
    mov rcx, 1
    call sleep_ms
    pop rcx
    loop .wait_rst
.rst_ok:

    mov byte [rbx + RTL_CFG9346], 0xC0

    lea rsi, [rtl_mac]
    mov eax, [rbx + RTL_MAC0]
    mov [rsi], eax
    mov ax, [rbx + RTL_MAC0 + 4]
    mov [rsi + 4], ax

    call rtl_setup_rx
    test rax, rax
    jz .fail
    call rtl_setup_tx
    test rax, rax
    jz .fail

    mov word [rbx + RTL_RMS], 0x1FFF
    mov ax, [rbx + RTL_CPLUSCMD]
    or ax, 1
    mov [rbx + RTL_CPLUSCMD], ax
    mov dword [rbx + RTL_RCR], 0x0000E70E
    mov dword [rbx + RTL_TCR], 0x03000700
    mov word [rbx + RTL_IMR], 0
    mov word [rbx + RTL_ISR], 0xFFFF
    mov byte [rbx + RTL_CFG9346], 0x00
    mov byte [rbx + RTL_CMD], CMD_TX_EN | CMD_RX_EN

    mov byte [rtl_ready], 1
    lea rcx, [msg_rtl_ok]
    call con_puts
    lea rcx, [msg_rtl_ok]
    call serial_puts
    mov rax, 1
    jmp .done

.fail:
    mov byte [rtl_ready], 0
    lea rcx, [msg_rtl_fail]
    call con_puts
    lea rcx, [msg_rtl_fail]
    call serial_puts
    xor rax, rax

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

rtl_setup_rx:
    push rbx
    push rsi
    push rdi

    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [rtl_rx_ring_phys], rax
    mov rdi, rax
    mov rcx, 4096 / 8
    xor eax, eax
    rep stosq

    xor ebx, ebx
.alloc_bufs:
    call pmm_alloc_page
    test rax, rax
    jz .fail
    lea rdi, [rtl_rx_bufs]
    mov [rdi + rbx * 8], rax

    mov rsi, [rtl_rx_ring_phys]
    mov rcx, rbx
    shl rcx, 4
    lea rdi, [rsi + rcx]
    lea rax, [rtl_rx_bufs]
    mov rax, [rax + rbx * 8]
    mov [rdi + 8], rax
    mov eax, RX_BUF_SIZE
    or eax, DESC_OWN
    cmp ebx, NUM_RX_DESC - 1
    jne .not_eor
    or eax, DESC_EOR
.not_eor:
    mov [rdi], eax
    mov dword [rdi + 4], 0
    inc ebx
    cmp ebx, NUM_RX_DESC
    jb .alloc_bufs

    mov rbx, [rtl_mmio]
    mov rax, [rtl_rx_ring_phys]
    mov [rbx + RTL_RDSAR], eax
    shr rax, 32
    mov [rbx + RTL_RDSAR + 4], eax
    mov dword [rtl_rx_cur], 0
    mov rax, 1
    jmp .done
.fail:
    xor rax, rax
.done:
    pop rdi
    pop rsi
    pop rbx
    ret

rtl_setup_tx:
    push rbx
    push rdi

    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [rtl_tx_ring_phys], rax
    mov rdi, rax
    mov rcx, 4096 / 8
    xor eax, eax
    rep stosq

    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [rtl_tx_buf_phys], rax

    mov rdi, [rtl_tx_ring_phys]
    mov dword [rdi + (NUM_TX_DESC - 1) * 16], DESC_EOR

    mov rbx, [rtl_mmio]
    mov rax, [rtl_tx_ring_phys]
    mov [rbx + RTL_TNPDS], eax
    shr rax, 32
    mov [rbx + RTL_TNPDS + 4], eax
    mov dword [rtl_tx_cur], 0
    mov rax, 1
    jmp .done
.fail:
    xor rax, rax
.done:
    pop rdi
    pop rbx
    ret

rtl8169_driver_get_mac:
    push rsi
    push rdi
    push rcx
    lea rsi, [rtl_mac]
    mov rdi, rcx
    mov rcx, 6
    rep movsb
    pop rcx
    pop rdi
    pop rsi
    ret

rtl8169_driver_send:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    cmp byte [rtl_ready], 0
    jz .out
    mov r13, rcx
    mov r12, rdx
    test r12, r12
    jz .out
    cmp r12, 1514
    jbe .len_ok
    mov r12, 1514
.len_ok:

    mov ebx, [rtl_tx_cur]
    mov rsi, [rtl_tx_ring_phys]
    mov rcx, rbx
    shl rcx, 4
    lea rdi, [rsi + rcx]

    mov ecx, 1000
.wait_own:
    test dword [rdi], DESC_OWN
    jz .free
    push rcx
    mov rcx, 1
    call sleep_ms
    pop rcx
    loop .wait_own
    jmp .out

.free:
    mov rsi, r13
    mov rdi, [rtl_tx_buf_phys]
    mov rcx, r12
    rep movsb

    mov rsi, [rtl_tx_ring_phys]
    mov rcx, rbx
    shl rcx, 4
    lea rdi, [rsi + rcx]
    mov rax, [rtl_tx_buf_phys]
    mov [rdi + 8], rax
    mov dword [rdi + 4], 0
    mov eax, r12d
    or eax, DESC_OWN | DESC_FS | DESC_LS
    cmp ebx, NUM_TX_DESC - 1
    jne .tx_opts
    or eax, DESC_EOR
.tx_opts:
    mov [rdi], eax

    mov rax, [rtl_mmio]
    mov byte [rax + RTL_TPPOLL], 0x40

    inc ebx
    and ebx, NUM_TX_DESC - 1
    mov [rtl_tx_cur], ebx

.out:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

rtl8169_driver_recv:
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    xor r12d, r12d
    cmp byte [rtl_ready], 0
    jz .empty

    mov r13, rcx
    mov ebx, [rtl_rx_cur]
    mov rdi, [rtl_rx_ring_phys]
    mov ecx, ebx
    shl ecx, 4
    add rdi, rcx

    test dword [rdi], DESC_OWN
    jnz .empty

    mov eax, [rdi]
    mov edx, eax
    and edx, 0x1FFF
    cmp edx, 4
    jbe .recycle
    sub edx, 4
    cmp edx, 1514
    jbe .len_ok
    mov edx, 1514
.len_ok:
    lea rax, [rtl_rx_bufs]
    mov rsi, [rax + rbx * 8]
    mov rdi, r13
    mov rcx, rdx
    mov r12d, edx
    rep movsb

.recycle:
    mov rdi, [rtl_rx_ring_phys]
    mov ecx, ebx
    shl ecx, 4
    add rdi, rcx
    mov edx, RX_BUF_SIZE
    or edx, DESC_OWN
    cmp ebx, NUM_RX_DESC - 1
    jne .rx_opts
    or edx, DESC_EOR
.rx_opts:
    mov [rdi], edx
    mov dword [rdi + 4], 0
    inc ebx
    and ebx, NUM_RX_DESC - 1
    mov [rtl_rx_cur], ebx

    mov rcx, [rtl_mmio]
    mov word [rcx + RTL_ISR], 0xFFFF

    mov eax, r12d
    jmp .done
.empty:
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

section .data
align 8
rtl_mmio dq 0
rtl_bdf dd 0
rtl_rx_cur dd 0
rtl_tx_cur dd 0
rtl_ready db 0
rtl_mac db 0, 0, 0, 0, 0, 0

msg_rtl_init db "Net: Realtek RTL8168/8111 Ethernet initializing...", 13, 10, 0
msg_rtl_bar  db "Net: RTL MMIO BAR=0x", 0
msg_rtl_ok   db "Net: RTL8169 link ready.", 13, 10, 0
msg_rtl_fail db "Net: RTL8169 init failed.", 13, 10, 0

section .bss
alignb 8
rtl_rx_ring_phys resq 1
rtl_tx_ring_phys resq 1
rtl_tx_buf_phys resq 1
rtl_rx_bufs resq NUM_RX_DESC
