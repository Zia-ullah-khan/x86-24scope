; ==============================================================================
; x86-24scope OS - Network Device Abstraction
; Dispatches to iwlwifi / e1000 / virtio / generic wifi / loopback
; ==============================================================================
bits 64
default rel

section .text

; Public API kept stable for ARP/IP/HTTP
global wifi_init
global wifi_send_packet
global wifi_recv_packet
global wifi_get_mac
global wifi_is_loopback

; Driver type IDs (must match pci.asm)
NETDEV_NONE         equ 0
NETDEV_LOOPBACK     equ 1
NETDEV_IWLWIFI      equ 2
NETDEV_E1000        equ 3
NETDEV_VIRTIO       equ 4
NETDEV_GENERIC_WIFI equ 5

extern pci_get_netdev
extern iwl_driver_init
extern iwl_driver_send
extern iwl_driver_recv
extern iwl_driver_get_mac
extern e1000_driver_init
extern e1000_driver_send
extern e1000_driver_recv
extern e1000_driver_get_mac
extern generic_eth_driver_init
extern generic_eth_driver_send
extern generic_eth_driver_recv
extern generic_eth_driver_get_mac
extern generic_wifi_driver_init
extern generic_wifi_driver_send
extern generic_wifi_driver_recv
extern generic_wifi_driver_get_mac
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
    cmp ecx, NETDEV_GENERIC_WIFI
    je .init_generic_wifi

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
    mov dword [active_type], NETDEV_LOOPBACK
    call loopback_driver_init
    jmp .done

.init_iwl:
    mov rcx, [active_bar]
    mov edx, [active_bdf]
    call iwl_driver_init
    test rax, rax
    jnz .done
    ; No firmware / bring-up failed — fall back to generic soft-MAC WiFi
    lea rcx, [msg_iwl_fallback]
    call con_puts
    lea rcx, [msg_iwl_fallback]
    call serial_puts
    mov dword [active_type], NETDEV_GENERIC_WIFI
    mov rcx, [active_bar]
    mov edx, [active_bdf]
    call generic_wifi_driver_init
    test rax, rax
    jnz .done
    mov dword [active_type], NETDEV_LOOPBACK
    call loopback_driver_init
    jmp .done

.init_virtio:
    mov rcx, [active_bar]
    mov edx, [active_bdf]
    call generic_eth_driver_init
    test rax, rax
    jnz .done
    mov dword [active_type], NETDEV_LOOPBACK
    call loopback_driver_init
    jmp .done

.init_generic_wifi:
    mov rcx, [active_bar]
    mov edx, [active_bdf]
    call generic_wifi_driver_init
    test rax, rax
    jnz .done
    mov dword [active_type], NETDEV_LOOPBACK
    call loopback_driver_init

.done:
    pop rbx
    pop rbp
    ret

; RAX = 1 if software loopback is the active interface
wifi_is_loopback:
    cmp dword [active_type], NETDEV_LOOPBACK
    sete al
    movzx eax, al
    ret

; RCX = packet, RDX = length
wifi_send_packet:
    mov eax, [active_type]
    cmp eax, NETDEV_E1000
    je .e1000
    cmp eax, NETDEV_IWLWIFI
    je .iwl
    cmp eax, NETDEV_VIRTIO
    je .virtio
    cmp eax, NETDEV_GENERIC_WIFI
    je .gwifi
    jmp loopback_driver_send
.e1000:
    jmp e1000_driver_send
.iwl:
    jmp iwl_driver_send
.virtio:
    jmp generic_eth_driver_send
.gwifi:
    jmp generic_wifi_driver_send

; RCX = dest buffer -> RAX = length
wifi_recv_packet:
    mov eax, [active_type]
    cmp eax, NETDEV_E1000
    je .e1000
    cmp eax, NETDEV_IWLWIFI
    je .iwl
    cmp eax, NETDEV_VIRTIO
    je .virtio
    cmp eax, NETDEV_GENERIC_WIFI
    je .gwifi
    jmp loopback_driver_recv
.e1000:
    jmp e1000_driver_recv
.iwl:
    jmp iwl_driver_recv
.virtio:
    jmp generic_eth_driver_recv
.gwifi:
    jmp generic_wifi_driver_recv

; RCX = 6-byte MAC out
wifi_get_mac:
    mov eax, [active_type]
    cmp eax, NETDEV_E1000
    je .e1000
    cmp eax, NETDEV_IWLWIFI
    je .iwl
    cmp eax, NETDEV_VIRTIO
    je .virtio
    cmp eax, NETDEV_GENERIC_WIFI
    je .gwifi
    jmp loopback_driver_get_mac
.e1000:
    jmp e1000_driver_get_mac
.iwl:
    jmp iwl_driver_get_mac
.virtio:
    jmp generic_eth_driver_get_mac
.gwifi:
    jmp generic_wifi_driver_get_mac

section .data
align 8
active_bar dq 0
active_bdf dd 0
active_type dd NETDEV_NONE

msg_netdev_init db "Net: Probing network devices...", 13, 10, 0
msg_iwl_fallback db "Net: iwlwifi unavailable; using generic WiFi soft-MAC.", 13, 10, 0
