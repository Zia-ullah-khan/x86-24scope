; ==============================================================================
; x86-24scope OS - Intel e1000 (82540EM / 82545EM) Ethernet Driver
; Used in QEMU for host <-> guest TCP (HTTP on port 8091)
; ==============================================================================
bits 64
default rel

section .text

global e1000_driver_init
global e1000_driver_send
global e1000_driver_recv
global e1000_driver_get_mac

extern con_puts
extern serial_puts
extern con_put_hex
extern con_newline
extern serial_put_hex
extern sleep_ms
extern pmm_alloc_page

; MMIO register offsets
E1000_CTRL     equ 0x0000
E1000_STATUS   equ 0x0008
E1000_EECD     equ 0x0010
E1000_EERD     equ 0x0014
E1000_ICR      equ 0x00C0
E1000_IMS      equ 0x00D0
E1000_IMC      equ 0x00D8
E1000_RCTL     equ 0x0100
E1000_TCTL     equ 0x0400
E1000_TIPG     equ 0x0410
E1000_RDBAL    equ 0x2800
E1000_RDBAH    equ 0x2804
E1000_RDLEN    equ 0x2808
E1000_RDH      equ 0x2810
E1000_RDT      equ 0x2818
E1000_TDBAL    equ 0x3800
E1000_TDBAH    equ 0x3804
E1000_TDLEN    equ 0x3808
E1000_TDH      equ 0x3810
E1000_TDT      equ 0x3818
E1000_MTA      equ 0x5200
E1000_RAL0     equ 0x5400
E1000_RAH0     equ 0x5404

; CTRL bits
CTRL_SLU       equ 0x40
CTRL_RST       equ 0x04000000

; RCTL bits
RCTL_EN        equ 0x00000002
RCTL_SBP       equ 0x00000004
RCTL_UPE       equ 0x00000008
RCTL_MPE       equ 0x00000010
RCTL_LBM_NONE  equ 0x00000000
RCTL_RDMTS_HALF equ 0x00000000
RCTL_BAM       equ 0x00008000
RCTL_BSIZE_2048 equ 0x00000000
RCTL_SECRC     equ 0x04000000

; TCTL bits
TCTL_EN        equ 0x00000002
TCTL_PSP       equ 0x00000008
TCTL_CT_SHIFT  equ 4
TCTL_COLD_SHIFT equ 12

NUM_RX_DESC    equ 32
NUM_TX_DESC    equ 32
RX_BUF_SIZE    equ 2048

; RCX = BAR physical, EDX = BDF
; Returns RAX = 1 on success, 0 on failure
e1000_driver_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov [e1000_mmio], rcx
    mov [e1000_bdf], edx

    lea rcx, [msg_e1000_init]
    call con_puts
    lea rcx, [msg_e1000_init]
    call serial_puts

    mov rbx, [e1000_mmio]
    test rbx, rbx
    jz .fail

    ; Soft reset
    mov eax, [rbx + E1000_CTRL]
    or eax, CTRL_RST
    mov [rbx + E1000_CTRL], eax
    mov rcx, 20
    call sleep_ms

    ; Link up + auto-speed
    mov eax, [rbx + E1000_CTRL]
    or eax, CTRL_SLU
    mov [rbx + E1000_CTRL], eax

    ; Disable interrupts
    mov dword [rbx + E1000_IMC], 0xFFFFFFFF
    mov eax, [rbx + E1000_ICR]

    ; Clear multicast table
    xor eax, eax
    mov ecx, 128
.clear_mta:
    mov [rbx + E1000_MTA + rax * 4], eax
    inc eax
    cmp eax, ecx
    jb .clear_mta

    call e1000_read_mac
    call e1000_setup_rx
    test rax, rax
    jz .fail
    call e1000_setup_tx
    test rax, rax
    jz .fail

    ; Enable RX
    mov eax, RCTL_EN | RCTL_UPE | RCTL_MPE | RCTL_BAM | RCTL_BSIZE_2048 | RCTL_SECRC
    mov [rbx + E1000_RCTL], eax

    ; Enable TX
    mov eax, TCTL_EN | TCTL_PSP
    or eax, (15 << TCTL_CT_SHIFT)
    or eax, (64 << TCTL_COLD_SHIFT)
    mov [rbx + E1000_TCTL], eax

    mov dword [rbx + E1000_TIPG], 0x0060200A

    lea rcx, [msg_e1000_ok]
    call con_puts
    lea rcx, [msg_e1000_ok]
    call serial_puts

    mov rax, 1
    jmp .done

.fail:
    lea rcx, [msg_e1000_fail]
    call con_puts
    lea rcx, [msg_e1000_fail]
    call serial_puts
    xor rax, rax

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

e1000_read_mac:
    push rbx
    push rsi
    mov rbx, [e1000_mmio]

    ; Try EEPROM word 0..2
    xor esi, esi
.eeprom_loop:
    mov eax, esi
    shl eax, 8
    or eax, 0x00000001              ; Start read
    mov [rbx + E1000_EERD], eax
    mov ecx, 1000
.wait_eerd:
    mov eax, [rbx + E1000_EERD]
    test eax, 0x10                  ; DONE
    jnz .eerd_done
    loop .wait_eerd
    jmp .use_ral
.eerd_done:
    shr eax, 16
    mov [e1000_mac + rsi * 2], ax
    inc esi
    cmp esi, 3
    jb .eeprom_loop

    ; Validate MAC (not all zeros)
    mov eax, dword [e1000_mac]
    or eax, dword [e1000_mac + 2]
    test eax, eax
    jnz .mac_ok

.use_ral:
    mov eax, [rbx + E1000_RAL0]
    mov [e1000_mac], eax
    mov eax, [rbx + E1000_RAH0]
    mov [e1000_mac + 4], ax

.mac_ok:
    ; Program RAL/RAH with our MAC
    mov eax, dword [e1000_mac]
    mov [rbx + E1000_RAL0], eax
    movzx eax, word [e1000_mac + 4]
    or eax, 0x80000000              ; AV bit
    mov [rbx + E1000_RAH0], eax

    pop rsi
    pop rbx
    ret

e1000_setup_rx:
    push rbx
    push rsi
    push rdi

    ; Allocate RX descriptor ring page
    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [rx_ring_phys], rax
    mov rdi, rax
    mov rcx, 4096 / 8
    xor rax, rax
    rep stosq

    ; Allocate one page per RX buffer (32 * need space - pack 2 per page = 16 pages)
    ; Simpler: allocate NUM_RX_DESC pages
    xor ebx, ebx
.alloc_rx_bufs:
    call pmm_alloc_page
    test rax, rax
    jz .fail
    lea rdi, [rx_bufs]
    mov [rdi + rbx * 8], rax

    ; Fill descriptor (16 bytes each: index << 4)
    mov rsi, [rx_ring_phys]
    mov rax, [rdi + rbx * 8]
    mov rcx, rbx
    shl rcx, 4
    mov [rsi + rcx], rax
    mov qword [rsi + rcx + 8], 0
    inc ebx
    cmp ebx, NUM_RX_DESC
    jb .alloc_rx_bufs

    mov rbx, [e1000_mmio]
    mov rax, [rx_ring_phys]
    mov [rbx + E1000_RDBAL], eax
    shr rax, 32
    mov [rbx + E1000_RDBAH], eax
    mov dword [rbx + E1000_RDLEN], NUM_RX_DESC * 16
    mov dword [rbx + E1000_RDH], 0
    mov dword [rbx + E1000_RDT], NUM_RX_DESC - 1
    mov dword [rx_cur], 0

    mov rax, 1
    jmp .done
.fail:
    xor rax, rax
.done:
    pop rdi
    pop rsi
    pop rbx
    ret

e1000_setup_tx:
    push rbx
    push rdi

    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [tx_ring_phys], rax
    mov rdi, rax
    mov rcx, 4096 / 8
    xor rax, rax
    rep stosq

    ; One shared TX bounce buffer
    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [tx_buf_phys], rax

    mov rbx, [e1000_mmio]
    mov rax, [tx_ring_phys]
    mov [rbx + E1000_TDBAL], eax
    shr rax, 32
    mov [rbx + E1000_TDBAH], eax
    mov dword [rbx + E1000_TDLEN], NUM_TX_DESC * 16
    mov dword [rbx + E1000_TDH], 0
    mov dword [rbx + E1000_TDT], 0
    mov dword [tx_cur], 0

    mov rax, 1
    jmp .done
.fail:
    xor rax, rax
.done:
    pop rdi
    pop rbx
    ret

e1000_driver_get_mac:
    push rsi
    push rdi
    push rcx
    lea rsi, [e1000_mac]
    mov rdi, rcx
    mov rcx, 6
    rep movsb
    pop rcx
    pop rdi
    pop rsi
    ret

; RCX = packet, RDX = length
e1000_driver_send:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov rsi, rcx
    mov r12, rdx
    cmp r12, 1518
    jbe .len_ok
    mov r12, 1518
.len_ok:
    test r12, r12
    jz .done

    ; Copy into TX bounce buffer
    mov rdi, [tx_buf_phys]
    mov rcx, r12
    rep movsb

    mov ebx, [tx_cur]
    mov rsi, [tx_ring_phys]
    mov rcx, rbx
    shl rcx, 4
    lea rdi, [rsi + rcx]

    mov rax, [tx_buf_phys]
    mov [rdi], rax                  ; buffer address
    mov word [rdi + 8], r12w
    mov byte [rdi + 10], 0
    mov byte [rdi + 11], 0x0B       ; EOP|IFCS|RS
    mov dword [rdi + 12], 0

    ; Advance TDT
    inc ebx
    and ebx, NUM_TX_DESC - 1
    mov [tx_cur], ebx
    mov rax, [e1000_mmio]
    mov [rax + E1000_TDT], ebx
    push rcx
    lea rcx, [msg_tx]
    call serial_puts
    pop rcx

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; RCX = dest buffer -> RAX = length
e1000_driver_recv:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov r12, rcx                    ; dest
    mov ebx, [rx_cur]
    mov rsi, [rx_ring_phys]
    mov rcx, rbx
    shl rcx, 4
    lea rdi, [rsi + rcx]

    movzx eax, byte [rdi + 12]      ; status
    test al, 0x01                   ; DD
    jz .empty

    push rax
    push rcx
    lea rcx, [msg_rx]
    call serial_puts
    pop rcx
    pop rax

    movzx edx, word [rdi + 8]       ; length
    mov eax, edx

    ; Copy from RX buffer
    lea rsi, [rx_bufs]
    mov rsi, [rsi + rbx * 8]
    mov rdi, r12
    mov rcx, rdx
    cmp rcx, 2048
    jbe .copy
    mov rcx, 2048
.copy:
    push rax
    rep movsb
    pop rax

    ; Recycle descriptor
    mov rsi, [rx_ring_phys]
    mov rcx, rbx
    shl rcx, 4
    lea rdi, [rsi + rcx]
    mov qword [rdi + 8], 0

    ; Advance RDT / rx_cur
    mov ecx, ebx
    inc ebx
    and ebx, NUM_RX_DESC - 1
    mov [rx_cur], ebx
    mov rsi, [e1000_mmio]
    mov [rsi + E1000_RDT], ecx
    jmp .done

.empty:
    xor rax, rax

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

section .data
align 8
e1000_mmio dq 0
e1000_bdf dd 0
e1000_mac db 0x52, 0x54, 0x00, 0x12, 0x34, 0x56, 0, 0
rx_ring_phys dq 0
tx_ring_phys dq 0
tx_buf_phys dq 0
rx_cur dd 0
tx_cur dd 0

msg_e1000_init db "Net: Intel e1000 Ethernet initializing...", 13, 10, 0
msg_e1000_ok   db "Net: e1000 link ready.", 13, 10, 0
msg_e1000_fail db "Net: e1000 init FAILED.", 13, 10, 0
msg_rx db "RX", 13, 10, 0
msg_tx db "TX", 13, 10, 0

section .bss
align 8
rx_bufs resq NUM_RX_DESC
