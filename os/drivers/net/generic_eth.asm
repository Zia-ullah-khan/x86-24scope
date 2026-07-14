; ==============================================================================
; x86-24scope OS - Generic Ethernet Driver (Virtio-net)
; Portable NIC path for QEMU/KVM and other virtio hosts.
; Implements the standard netdev contract used by e1000/loopback.
; ==============================================================================
bits 64
default rel

section .text

global generic_eth_driver_init
global generic_eth_driver_send
global generic_eth_driver_recv
global generic_eth_driver_get_mac

extern con_puts
extern serial_puts
extern pci_read_config
extern pmm_alloc_page
extern sleep_ms

; Legacy virtio-pci register offsets (I/O BAR0)
VIRTIO_PCI_HOST_FEATURES equ 0
VIRTIO_PCI_GUEST_FEATURES equ 4
VIRTIO_PCI_QUEUE_PFN     equ 8
VIRTIO_PCI_QUEUE_NUM     equ 12
VIRTIO_PCI_QUEUE_SEL     equ 14
VIRTIO_PCI_QUEUE_NOTIFY  equ 16
VIRTIO_PCI_STATUS        equ 18
VIRTIO_PCI_ISR           equ 19
VIRTIO_PCI_CONFIG        equ 20

; Status bits
VIRTIO_ACKNOWLEDGE       equ 1
VIRTIO_DRIVER            equ 2
VIRTIO_DRIVER_OK         equ 4
VIRTIO_FAILED            equ 128

; Feature bits
VIRTIO_NET_F_MAC         equ (1 << 5)
VIRTIO_NET_F_STATUS      equ (1 << 16)
VIRTIO_NET_F_MRG_RXBUF   equ (1 << 15)

; Virtqueue indices
VQ_RX                    equ 0
VQ_TX                    equ 1

; Match common QEMU virtio-net queue size (legacy QUEUE_NUM is often read-only)
VQ_SIZE                  equ 256
VRING_DESC_SIZE          equ 16
VIRTIO_NET_HDR_SIZE      equ 10

; Descriptor flags
VRING_DESC_F_NEXT        equ 1
VRING_DESC_F_WRITE       equ 2

; RCX = BAR (may be unused for I/O), EDX = packed BDF
; RAX = 1 success, 0 fail
generic_eth_driver_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov [eth_bdf], edx

    lea rcx, [msg_eth_init]
    call con_puts
    lea rcx, [msg_eth_init]
    call serial_puts

    ; Unpack BDF: bus:23:16 dev:15:8 func:7:0
    mov eax, [eth_bdf]
    movzx r14d, al                  ; function
    mov ecx, eax
    shr ecx, 8
    movzx r13d, cl                  ; device
    shr eax, 16
    movzx r12d, al                  ; bus

    ; Re-read BAR0 to detect I/O vs MMIO
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0x10
    call pci_read_config
    mov ebx, eax
    test ebx, 1
    jz .try_mmio

    and eax, 0xFFFFFFFC
    mov [eth_io_base], rax
    mov byte [eth_use_io], 1
    jmp .have_bar

.try_mmio:
    ; Memory BAR — transitional devices sometimes expose legacy at BAR0 MMIO
    and eax, 0xFFFFFFF0
    test eax, eax
    jz .fail
    mov [eth_io_base], rax
    mov byte [eth_use_io], 0

.have_bar:
    ; Reset device
    xor eax, eax
    call virtio_write_status

    mov al, VIRTIO_ACKNOWLEDGE
    call virtio_write_status

    mov al, VIRTIO_ACKNOWLEDGE | VIRTIO_DRIVER
    call virtio_write_status

    ; Negotiate features: MAC + STATUS (legacy 32-bit features only)
    call virtio_read_host_features
    mov ebx, eax
    and ebx, VIRTIO_NET_F_MAC | VIRTIO_NET_F_STATUS
    mov eax, ebx
    call virtio_write_guest_features
    mov [eth_features], ebx

    call virtio_setup_rx_queue
    test rax, rax
    jz .fail
    call virtio_setup_tx_queue
    test rax, rax
    jz .fail

    ; Read MAC from config space if offered
    test dword [eth_features], VIRTIO_NET_F_MAC
    jz .default_mac
    call virtio_read_mac
    jmp .mac_done

.default_mac:
    lea rsi, [eth_default_mac]
    lea rdi, [eth_mac]
    mov rcx, 6
    rep movsb

.mac_done:
    mov al, VIRTIO_ACKNOWLEDGE | VIRTIO_DRIVER | VIRTIO_DRIVER_OK
    call virtio_write_status

    lea rcx, [msg_eth_ok]
    call con_puts
    lea rcx, [msg_eth_ok]
    call serial_puts

    mov byte [eth_ready], 1
    mov rax, 1
    jmp .done

.fail:
    lea rcx, [msg_eth_fail]
    call con_puts
    lea rcx, [msg_eth_fail]
    call serial_puts
    mov byte [eth_ready], 0
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

; AL = status byte
virtio_write_status:
    push rdx
    push rax
    cmp byte [eth_use_io], 0
    jz .mmio
    mov dx, word [eth_io_base]
    add dx, VIRTIO_PCI_STATUS
    pop rax
    out dx, al
    pop rdx
    ret
.mmio:
    mov rdx, [eth_io_base]
    pop rax
    mov [rdx + VIRTIO_PCI_STATUS], al
    pop rdx
    ret

virtio_read_host_features:
    cmp byte [eth_use_io], 0
    jz .mmio
    mov dx, word [eth_io_base]
    add dx, VIRTIO_PCI_HOST_FEATURES
    in eax, dx
    ret
.mmio:
    mov rdx, [eth_io_base]
    mov eax, [rdx + VIRTIO_PCI_HOST_FEATURES]
    ret

; EAX = guest features
virtio_write_guest_features:
    cmp byte [eth_use_io], 0
    jz .mmio
    mov dx, word [eth_io_base]
    add dx, VIRTIO_PCI_GUEST_FEATURES
    out dx, eax
    ret
.mmio:
    mov rdx, [eth_io_base]
    mov [rdx + VIRTIO_PCI_GUEST_FEATURES], eax
    ret

virtio_read_mac:
    push rbx
    push rsi
    cmp byte [eth_use_io], 0
    jz .mmio
    mov dx, word [eth_io_base]
    add dx, VIRTIO_PCI_CONFIG
    lea rsi, [eth_mac]
    mov ecx, 6
.mac_io:
    in al, dx
    mov [rsi], al
    inc rsi
    inc dx
    loop .mac_io
    pop rsi
    pop rbx
    ret
.mmio:
    mov rbx, [eth_io_base]
    lea rsi, [eth_mac]
    mov eax, [rbx + VIRTIO_PCI_CONFIG]
    mov [rsi], eax
    movzx eax, word [rbx + VIRTIO_PCI_CONFIG + 4]
    mov [rsi + 4], ax
    pop rsi
    pop rbx
    ret

; Select queue AX; clamp guest size to VQ_SIZE; return size in AX (0 = fail)
virtio_select_queue:
    push rbx
    mov bx, ax
    cmp byte [eth_use_io], 0
    jz .mmio

    mov dx, word [eth_io_base]
    add dx, VIRTIO_PCI_QUEUE_SEL
    mov ax, bx
    out dx, ax

    ; Try to request our ring size (ignored if read-only)
    mov dx, word [eth_io_base]
    add dx, VIRTIO_PCI_QUEUE_NUM
    mov ax, VQ_SIZE
    out dx, ax
    in ax, dx
    cmp ax, VQ_SIZE
    jne .fail
    pop rbx
    ret

.mmio:
    mov rdx, [eth_io_base]
    mov [rdx + VIRTIO_PCI_QUEUE_SEL], bx
    mov word [rdx + VIRTIO_PCI_QUEUE_NUM], VQ_SIZE
    movzx eax, word [rdx + VIRTIO_PCI_QUEUE_NUM]
    cmp ax, VQ_SIZE
    jne .fail
    pop rbx
    ret

.fail:
    xor eax, eax
    pop rbx
    ret

; ECX = queue pfn (phys >> 12)
virtio_set_queue_pfn:
    cmp byte [eth_use_io], 0
    jz .mmio
    mov dx, word [eth_io_base]
    add dx, VIRTIO_PCI_QUEUE_PFN
    mov eax, ecx
    out dx, eax
    ret
.mmio:
    mov rdx, [eth_io_base]
    mov [rdx + VIRTIO_PCI_QUEUE_PFN], ecx
    ret

; AX = queue index to notify
virtio_notify:
    cmp byte [eth_use_io], 0
    jz .mmio
    push rax
    mov dx, word [eth_io_base]
    add dx, VIRTIO_PCI_QUEUE_NOTIFY
    pop rax
    out dx, ax
    ret
.mmio:
    mov rdx, [eth_io_base]
    mov [rdx + VIRTIO_PCI_QUEUE_NOTIFY], ax
    ret

virtio_setup_rx_queue:
    push rbx
    push rsi
    push rdi

    mov ax, VQ_RX
    call virtio_select_queue
    test ax, ax
    jz .fail

    ; Zero RX vring (desc | avail | pad | used) — 3 pages for VQ_SIZE=256
    lea rdi, [rx_vring]
    mov rcx, (4096 * 3) / 8
    xor rax, rax
    rep stosq

    ; Fill RX descriptors: each points at a writeable packet buffer
    xor ebx, ebx
.fill_rx:
    lea rsi, [rx_vring]
    mov eax, ebx
    shl eax, 4                      ; desc index * 16
    lea rdi, [rsi + rax]

    lea rax, [rx_packets]
    mov ecx, ebx
    imul ecx, 2048
    add rax, rcx
    mov [rdi], rax                  ; addr
    mov dword [rdi + 8], 2048       ; len
    mov word [rdi + 12], VRING_DESC_F_WRITE
    mov word [rdi + 14], 0

    ; avail ring entry
    lea rsi, [rx_vring]
    add rsi, VQ_SIZE * VRING_DESC_SIZE
    mov [rsi + 4 + rbx * 2], bx

    inc ebx
    cmp ebx, VQ_SIZE
    jb .fill_rx

    ; avail.idx = VQ_SIZE (all buffers offered)
    lea rsi, [rx_vring]
    add rsi, VQ_SIZE * VRING_DESC_SIZE
    mov word [rsi], 0               ; flags
    mov word [rsi + 2], VQ_SIZE     ; idx
    mov dword [rx_avail_idx], VQ_SIZE
    mov dword [rx_used_idx], 0
    mov dword [rx_last_used], 0

    lea rcx, [rx_vring]
    shr rcx, 12
    call virtio_set_queue_pfn

    mov rax, 1
    jmp .done
.fail:
    xor rax, rax
.done:
    pop rdi
    pop rsi
    pop rbx
    ret

virtio_setup_tx_queue:
    push rdi

    mov ax, VQ_TX
    call virtio_select_queue
    test ax, ax
    jz .fail

    lea rdi, [tx_vring]
    mov rcx, (4096 * 3) / 8
    xor rax, rax
    rep stosq

    mov dword [tx_avail_idx], 0
    mov dword [tx_used_idx], 0
    mov dword [tx_free_head], 0

    lea rcx, [tx_vring]
    shr rcx, 12
    call virtio_set_queue_pfn

    mov rax, 1
    jmp .done
.fail:
    xor rax, rax
.done:
    pop rdi
    ret

generic_eth_driver_get_mac:
    push rsi
    push rdi
    push rcx
    lea rsi, [eth_mac]
    mov rdi, rcx
    mov rcx, 6
    rep movsb
    pop rcx
    pop rdi
    pop rsi
    ret

; RCX = packet, RDX = length
generic_eth_driver_send:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    cmp byte [eth_ready], 0
    jz .done

    mov rsi, rcx
    mov r12, rdx
    cmp r12, 1514
    jbe .len_ok
    mov r12, 1514
.len_ok:
    test r12, r12
    jz .done

    ; Free completed TX used ring entries
    call virtio_reclaim_tx

    ; Build: desc0 = net hdr (READ), desc1 = packet (READ) chained
    mov ebx, [tx_free_head]
    and ebx, VQ_SIZE - 1

    ; Clear net header
    lea rdi, [tx_net_hdr]
    mov rcx, VIRTIO_NET_HDR_SIZE
    xor eax, eax
    rep stosb

    ; Copy packet into bounce buffer (one slot)
    lea rdi, [tx_packet]
    mov rcx, r12
    push rsi
    rep movsb
    pop rsi

    lea rsi, [tx_vring]
    mov eax, ebx
    shl eax, 4
    lea rdi, [rsi + rax]

    lea rax, [tx_net_hdr]
    mov [rdi], rax
    mov dword [rdi + 8], VIRTIO_NET_HDR_SIZE
    mov word [rdi + 12], VRING_DESC_F_NEXT
    mov ecx, ebx
    inc ecx
    and ecx, VQ_SIZE - 1
    mov word [rdi + 14], cx         ; next desc

    ; Second descriptor = packet
    mov eax, ecx
    shl eax, 4
    lea rdi, [rsi + rax]
    lea rax, [tx_packet]
    mov [rdi], rax
    mov dword [rdi + 8], r12d
    mov word [rdi + 12], 0
    mov word [rdi + 14], 0

    ; Publish in avail ring
    lea rsi, [tx_vring]
    add rsi, VQ_SIZE * VRING_DESC_SIZE
    mov eax, [tx_avail_idx]
    mov edx, eax
    and edx, VQ_SIZE - 1
    mov [rsi + 4 + rdx * 2], bx
    inc eax
    mov [tx_avail_idx], eax
    mov [rsi + 2], ax               ; avail.idx

    mov eax, [tx_free_head]
    add eax, 2
    mov [tx_free_head], eax

    mov ax, VQ_TX
    call virtio_notify

.done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

virtio_reclaim_tx:
    push rbx
    push rsi
    ; used ring at second page boundary for VQ_SIZE=256 layout
    lea rsi, [tx_vring]
    add rsi, 8192
    movzx eax, word [rsi + 2]       ; used.idx
    mov ebx, [tx_used_idx]
.reclaim:
    cmp ebx, eax
    jae .done
    inc ebx
    jmp .reclaim
.done:
    mov [tx_used_idx], ebx
    pop rsi
    pop rbx
    ret

; RCX = dest buffer -> RAX = length
generic_eth_driver_recv:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    cmp byte [eth_ready], 0
    jz .empty

    mov r12, rcx                    ; dest

    lea rsi, [rx_vring]
    add rsi, 8192                   ; used ring (page-aligned after avail)
    movzx eax, word [rsi + 2]       ; used.idx
    mov ebx, [rx_last_used]
    cmp ebx, eax
    jae .empty

    mov edx, ebx
    and edx, VQ_SIZE - 1
    movzx r13d, word [rsi + 4 + rdx * 8]     ; desc id
    mov r14d, [rsi + 4 + rdx * 8 + 4]        ; total len (hdr + frame)

    inc ebx
    mov [rx_last_used], ebx

    xor eax, eax
    cmp r14d, VIRTIO_NET_HDR_SIZE
    jbe .recycle

    mov ecx, r14d
    sub ecx, VIRTIO_NET_HDR_SIZE
    cmp ecx, 1518
    jbe .len_ok
    mov ecx, 1518
.len_ok:
    mov r14d, ecx

    lea rsi, [rx_packets]
    mov eax, r13d
    imul eax, 2048
    add rsi, rax
    add rsi, VIRTIO_NET_HDR_SIZE
    mov rdi, r12
    mov rcx, r14
    rep movsb
    mov rax, r14                    ; return length

.recycle:
    push rax
    ; Re-post RX descriptor
    lea rsi, [rx_vring]
    mov eax, r13d
    shl eax, 4
    lea rdi, [rsi + rax]
    lea rax, [rx_packets]
    mov ecx, r13d
    imul ecx, 2048
    add rax, rcx
    mov [rdi], rax
    mov dword [rdi + 8], 2048
    mov word [rdi + 12], VRING_DESC_F_WRITE
    mov word [rdi + 14], 0

    lea rsi, [rx_vring]
    add rsi, VQ_SIZE * VRING_DESC_SIZE
    mov eax, [rx_avail_idx]
    mov edx, eax
    and edx, VQ_SIZE - 1
    mov [rsi + 4 + rdx * 2], r13w
    inc eax
    mov [rx_avail_idx], eax
    mov [rsi + 2], ax

    mov ax, VQ_RX
    call virtio_notify
    pop rax
    jmp .done

.empty:
    xor rax, rax
.done:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

section .data
align 8
eth_io_base dq 0
eth_bdf dd 0
eth_features dd 0
eth_ready db 0
eth_use_io db 1
align 8
eth_mac db 0x52, 0x54, 0x00, 0x12, 0x34, 0x56
eth_default_mac db 0x52, 0x54, 0x00, 0x12, 0x34, 0x56

rx_avail_idx dd 0
rx_used_idx dd 0
rx_last_used dd 0
tx_avail_idx dd 0
tx_used_idx dd 0
tx_free_head dd 0

msg_eth_init db "Net: Generic Ethernet (virtio-net) init...", 13, 10, 0
msg_eth_ok   db "Net: Generic Ethernet ready.", 13, 10, 0
msg_eth_fail db "Net: Generic Ethernet init failed.", 13, 10, 0

section .bss
alignb 4096
rx_vring resb 4096 * 3
alignb 4096
tx_vring resb 4096 * 3
alignb 16
rx_packets resb VQ_SIZE * 2048
alignb 16
tx_net_hdr resb 64
alignb 16
tx_packet resb 2048
