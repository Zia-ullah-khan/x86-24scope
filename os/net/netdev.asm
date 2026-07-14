; ==============================================================================
; x86-24scope OS - Network Device Abstraction
; Dispatches to iwlwifi / e1000 / virtio / loopback based on PCI probe
; ==============================================================================
bits 64
default rel

section .text

; Public API kept stable for ARP/IP/HTTP
global wifi_init
global wifi_send_packet
global wifi_recv_packet
global wifi_get_mac

; Driver type IDs (must match pci.asm)
NETDEV_NONE     equ 0
NETDEV_LOOPBACK equ 1
NETDEV_IWLWIFI  equ 2
NETDEV_E1000    equ 3
NETDEV_VIRTIO   equ 4

extern pci_get_netdev
extern iwl_driver_init
extern iwl_driver_send
extern iwl_driver_recv
extern iwl_driver_get_mac
extern e1000_driver_init
extern e1000_driver_send
extern e1000_driver_recv
extern e1000_driver_get_mac
extern loopback_driver_init
extern loopback_driver_send
extern loopback_driver_recv
extern loopback_driver_get_mac
extern con_puts
extern serial_puts

wifi_init:
    push rbp
    mov rbp, rsp
    push rbx

    lea rcx, [msg_netdev_init]
    call con_puts
    lea rcx, [msg_netdev_init]
    call serial_puts

    call pci_get_netdev
    ; RAX = BAR / cookie, RCX = type, RDX = BDF packed
    mov [active_type], ecx
    mov [active_bar], rax
    mov [active_bdf], edx

    cmp ecx, NETDEV_E1000
    je .init_e1000
    cmp ecx, NETDEV_IWLWIFI
    je .init_iwl
    cmp ecx, NETDEV_VIRTIO
    je .init_virtio

    ; Default: software loopback (QEMU without NIC, or unknown)
    mov dword [active_type], NETDEV_LOOPBACK
    call loopback_driver_init
    jmp .done

.init_e1000:
    mov rcx, [active_bar]
    mov edx, [active_bdf]
    call e1000_driver_init
    test rax, rax
    jnz .done
    ; Fall back if init failed
    mov dword [active_type], NETDEV_LOOPBACK
    call loopback_driver_init
    jmp .done

.init_iwl:
    mov rcx, [active_bar]
    mov edx, [active_bdf]
    call iwl_driver_init
    test rax, rax
    jnz .done
    mov dword [active_type], NETDEV_LOOPBACK
    call loopback_driver_init
    jmp .done

.init_virtio:
    ; Virtio path reserved; fall through to loopback until fully wired
    lea rcx, [msg_virtio_todo]
    call con_puts
    lea rcx, [msg_virtio_todo]
    call serial_puts
    mov dword [active_type], NETDEV_LOOPBACK
    call loopback_driver_init

.done:
    pop rbx
    pop rbp
    ret

; RCX = packet, RDX = length
wifi_send_packet:
    mov eax, [active_type]
    cmp eax, NETDEV_E1000
    je .e1000
    cmp eax, NETDEV_IWLWIFI
    je .iwl
    jmp loopback_driver_send
.e1000:
    jmp e1000_driver_send
.iwl:
    jmp iwl_driver_send

; RCX = dest buffer -> RAX = length
wifi_recv_packet:
    mov eax, [active_type]
    cmp eax, NETDEV_E1000
    je .e1000
    cmp eax, NETDEV_IWLWIFI
    je .iwl
    jmp loopback_driver_recv
.e1000:
    jmp e1000_driver_recv
.iwl:
    jmp iwl_driver_recv

; RCX = 6-byte MAC out
wifi_get_mac:
    mov eax, [active_type]
    cmp eax, NETDEV_E1000
    je .e1000
    cmp eax, NETDEV_IWLWIFI
    je .iwl
    jmp loopback_driver_get_mac
.e1000:
    jmp e1000_driver_get_mac
.iwl:
    jmp iwl_driver_get_mac

section .data
align 8
active_bar dq 0
active_bdf dd 0
active_type dd NETDEV_NONE

msg_netdev_init db "Net: Probing network devices...", 13, 10, 0
msg_virtio_todo db "Net: Virtio-net detected but driver incomplete; using loopback.", 13, 10, 0
