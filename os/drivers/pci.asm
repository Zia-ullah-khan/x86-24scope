; ==============================================================================
; x86-24scope OS - PCI Bus Enumeration + Multi-Device Net Probe
; ==============================================================================
bits 64
default rel

section .text

global pci_init
global pci_read_config
global pci_write_config
global pci_get_wifi_device
global pci_get_netdev

; Driver type IDs (must match netdev.asm)
NETDEV_NONE         equ 0
NETDEV_LOOPBACK     equ 1
NETDEV_IWLWIFI      equ 2
NETDEV_E1000        equ 3
NETDEV_VIRTIO       equ 4
NETDEV_GENERIC_WIFI equ 5

extern con_puts
extern con_put_hex
extern con_newline
extern serial_puts
extern serial_put_hex
extern serial_putchar

PCI_CONFIG_ADDRESS equ 0xCF8
PCI_CONFIG_DATA    equ 0xCFC

pci_read_config:
    push rdx
    push rcx
    push rbx

    mov eax, 0x80000000
    and rcx, 0xFF
    shl rcx, 16
    or rax, rcx
    and rdx, 0x1F
    shl rdx, 11
    or rax, rdx
    and r8, 0x07
    shl r8, 8
    or rax, r8
    and r9, 0xFC
    or rax, r9

    mov dx, PCI_CONFIG_ADDRESS
    out dx, eax
    mov dx, PCI_CONFIG_DATA
    in eax, dx

    pop rbx
    pop rcx
    pop rdx
    ret

pci_write_config:
    push rdx
    push rcx
    push rbx

    mov eax, 0x80000000
    and rcx, 0xFF
    shl rcx, 16
    or rax, rcx
    and rdx, 0x1F
    shl rdx, 11
    or rax, rdx
    and r8, 0x07
    shl r8, 8
    or rax, r8
    and r9, 0xFC
    or rax, r9

    mov dx, PCI_CONFIG_ADDRESS
    out dx, eax

    mov eax, [rsp + 56 + 8]
    mov dx, PCI_CONFIG_DATA
    out dx, eax

    pop rbx
    pop rcx
    pop rdx
    ret

; Lookup vendor:device in net_device_table
; Input: R15D = vendor | (device << 16)
; Output: EAX = driver type (0 if unknown)
pci_lookup_netdev:
    push rsi
    push rbx
    lea rsi, [net_device_table]
.loop:
    mov eax, [rsi]
    test eax, eax
    jz .miss
    cmp eax, r15d
    je .hit
    add rsi, 8
    jmp .loop
.hit:
    mov eax, [rsi + 4]
    jmp .done
.miss:
    xor eax, eax
.done:
    pop rbx
    pop rsi
    ret

; Enable memory + bus master on current BDF (r12/r13/r14)
pci_enable_bus_master:
    push rax
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0x04
    call pci_read_config
    or ax, 0x06
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0x04
    push rax
    sub rsp, 32
    call pci_write_config
    add rsp, 40
    pop rax
    ret

; Read 64-bit BAR0 into RAX for current BDF
pci_read_bar0:
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0x10
    call pci_read_config
    mov ebx, eax
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0x14
    call pci_read_config
    ; If 32-bit BAR (bit 2 of low == 0 for type), high may be unused
    mov edx, ebx
    and edx, 0xFFFFFFF0
    test ebx, 0x04                  ; 64-bit BAR?
    jz .bar32
    shl rax, 32
    or rax, rdx
    ret
.bar32:
    mov eax, edx
    ret

pci_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov dword [netdev_type], NETDEV_NONE
    mov qword [netdev_bar], 0
    mov dword [netdev_bdf], 0
    mov byte [wifi_found], 0

    lea rcx, [msg_pci_scan]
    call con_puts
    lea rcx, [msg_pci_scan]
    call serial_puts

    xor r12, r12
.bus_loop:
    xor r13, r13
.dev_loop:
    xor r14, r14
.func_loop:
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    xor r9, r9
    call pci_read_config
    cmp ax, 0xFFFF
    je .next_func

    mov r15d, eax

    cmp r14, 0
    jne .print_device
    mov rcx, r12
    mov rdx, r13
    xor r8, r8
    mov r9, 0x0C
    call pci_read_config
    shr eax, 16
    and al, 0x80
    mov [is_multi_func], al

.print_device:
    lea rcx, [msg_dev_prefix]
    call serial_puts
    mov rcx, r12
    call serial_put_hex
    mov rcx, ':'
    call serial_putchar
    mov rcx, r13
    call serial_put_hex
    mov rcx, '.'
    call serial_putchar
    mov rcx, r14
    call serial_put_hex
    lea rcx, [msg_dev_middle]
    call serial_puts
    movzx rcx, r15w
    call serial_put_hex
    mov rcx, ':'
    call serial_putchar
    mov eax, r15d
    shr eax, 16
    movzx rcx, ax
    call serial_put_hex
    lea rcx, [pci_newline]
    call serial_puts

    ; Match against network device table
    call pci_lookup_netdev
    test eax, eax
    jnz .have_type

    ; Unknown ID: class-code fallback (Network controller)
    ; Class/subclass at config +0x08 bits 31:16 → class:subclass
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0x08
    call pci_read_config
    shr eax, 16
    cmp ax, 0x0280                  ; Network / Other (common WiFi class)
    jne .next_func
    mov eax, NETDEV_GENERIC_WIFI

.have_type:
    ; Prefer Ethernet (e1000/virtio) over WiFi for first bind if none yet;
    ; if e1000 found later while only iwl claimed, upgrade.
    cmp dword [netdev_type], NETDEV_NONE
    je .claim
    cmp eax, NETDEV_E1000
    je .claim
    cmp eax, NETDEV_VIRTIO
    je .claim
    jmp .next_func

.claim:
    mov [netdev_type], eax
    call pci_enable_bus_master
    call pci_read_bar0
    mov [netdev_bar], rax

    mov eax, r12d
    shl eax, 8
    or eax, r13d
    shl eax, 8
    or eax, r14d
    mov [netdev_bdf], eax

    cmp dword [netdev_type], NETDEV_IWLWIFI
    je .mark_wifi
    cmp dword [netdev_type], NETDEV_GENERIC_WIFI
    jne .announce
.mark_wifi:
    mov byte [wifi_found], 1
    mov [wifi_reg_base], rax
    mov [wifi_bus], r12d
    mov [wifi_dev], r13d
    mov [wifi_func], r14d

.announce:
    lea rcx, [msg_net_found]
    call con_puts
    lea rcx, [msg_net_found]
    call serial_puts
    mov ecx, [netdev_type]
    call con_put_hex
    call con_newline
    mov ecx, [netdev_type]
    call serial_put_hex
    lea rcx, [pci_newline]
    call serial_puts

.next_func:
    cmp r14, 0
    jne .inc_func
    cmp byte [is_multi_func], 0
    jz .next_dev
.inc_func:
    inc r14
    cmp r14, 8
    jl .func_loop
.next_dev:
    inc r13
    cmp r13, 32
    jl .dev_loop
    inc r12
    cmp r12, 256
    jl .bus_loop

    lea rcx, [msg_pci_done]
    call con_puts
    lea rcx, [msg_pci_done]
    call serial_puts

    cmp dword [netdev_type], NETDEV_NONE
    jne .done
    lea rcx, [msg_net_missing]
    call con_puts
    lea rcx, [msg_net_missing]
    call serial_puts

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

pci_get_netdev:
    ; RAX = BAR, RCX = type, RDX = BDF
    mov rax, [netdev_bar]
    mov ecx, [netdev_type]
    mov edx, [netdev_bdf]
    ret

pci_get_wifi_device:
    xor rax, rax
    cmp byte [wifi_found], 0
    jz .not_found
    mov rax, [wifi_reg_base]
    mov ecx, [wifi_bus]
    shl ecx, 8
    or ecx, [wifi_dev]
    shl ecx, 8
    or ecx, [wifi_func]
.not_found:
    ret

section .data
align 8
netdev_bar dq 0
wifi_reg_base dq 0
netdev_type dd NETDEV_NONE
netdev_bdf dd 0
wifi_bus dd 0
wifi_dev dd 0
wifi_func dd 0
wifi_found db 0
is_multi_func db 0

; Network PCI ID table: dword vendor|device<<16, dword driver_type
; Terminated by vendor=0
align 8
net_device_table:
    ; --- Intel e1000 / e1000e (QEMU + common NICs) ---
    dd 0x100E8086, NETDEV_E1000     ; 82540EM (QEMU default e1000)
    dd 0x100F8086, NETDEV_E1000     ; 82545EM
    dd 0x10D38086, NETDEV_E1000     ; 82574L
    dd 0x10F58086, NETDEV_E1000     ; 82567LM
    dd 0x15038086, NETDEV_E1000     ; 82579LM
    dd 0x153A8086, NETDEV_E1000     ; I217-LM
    dd 0x15A18086, NETDEV_E1000     ; I218-V
    dd 0x15B78086, NETDEV_E1000     ; I219-V
    dd 0x15D88086, NETDEV_E1000     ; I219-LM9
    ; --- Virtio-net ---
    dd 0x10001AF4, NETDEV_VIRTIO    ; legacy virtio-net
    dd 0x10411AF4, NETDEV_VIRTIO    ; modern virtio-net
    ; --- Intel iwlwifi WiFi (AX / AC / AX211 family) ---
    dd 0x7E408086, NETDEV_IWLWIFI   ; AX211
    dd 0x7E208086, NETDEV_IWLWIFI   ; AX203
    dd 0x51F08086, NETDEV_IWLWIFI   ; AX211 (ADL)
    dd 0x51F18086, NETDEV_IWLWIFI   ; AX211 variant
    dd 0x54F08086, NETDEV_IWLWIFI   ; AX211 (MTL)
    dd 0x27258086, NETDEV_IWLWIFI   ; AX210
    dd 0x27238086, NETDEV_IWLWIFI   ; AX200
    dd 0x27208086, NETDEV_IWLWIFI   ; AX201
    dd 0xA0F08086, NETDEV_IWLWIFI   ; AX201 (CMP)
    dd 0x06F08086, NETDEV_IWLWIFI   ; AX201 (CML)
    dd 0x02F08086, NETDEV_IWLWIFI   ; AX201 (CML-H)
    dd 0x43F08086, NETDEV_IWLWIFI   ; AX201 (TGL)
    dd 0x4DF08086, NETDEV_IWLWIFI   ; AX201 (JSL)
    dd 0x24F38086, NETDEV_IWLWIFI   ; AX200 (CNP)
    dd 0x24F48086, NETDEV_IWLWIFI   ; AX201
    dd 0x24FD8086, NETDEV_IWLWIFI   ; 8265/8260
    dd 0x24FB8086, NETDEV_IWLWIFI   ; 8265
    dd 0x25268086, NETDEV_IWLWIFI   ; 9260
    dd 0x25268086, NETDEV_IWLWIFI   ; duplicate ok
    dd 0x9DF08086, NETDEV_IWLWIFI   ; 9560
    dd 0xA3708086, NETDEV_IWLWIFI   ; 9560 CNVi
    dd 0x31DC8086, NETDEV_IWLWIFI   ; 9462
    dd 0x30DC8086, NETDEV_IWLWIFI   ; 9461
    dd 0x271C8086, NETDEV_IWLWIFI   ; AX101
    dd 0x271B8086, NETDEV_IWLWIFI   ; AX101
    dd 0x00000000, 0                ; end

msg_pci_scan db "PCI: Scanning PCI Bus...", 13, 10, 0
msg_dev_prefix db "  PCI: ", 0
msg_dev_middle db " -> ", 0
msg_net_found db "PCI: Network device claimed, driver type 0x", 0
msg_net_missing db "PCI: No supported network device found (will use loopback).", 13, 10, 0
msg_pci_done db "PCI: Bus scan complete.", 13, 10, 0
pci_newline db 13, 10, 0
