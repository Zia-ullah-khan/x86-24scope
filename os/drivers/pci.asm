; ==============================================================================
; x86-24scope OS - PCI Bus Enumeration Driver
; ==============================================================================
bits 64
default rel

section .text

global pci_init
global pci_read_config
global pci_write_config
global pci_get_wifi_device

extern con_puts
extern con_put_hex
extern con_newline
extern serial_puts
extern serial_put_hex
extern serial_putchar

; PCI Config Ports
PCI_CONFIG_ADDRESS equ 0xCF8
PCI_CONFIG_DATA    equ 0xCFC

pci_read_config:
    ; RCX = Bus (0..255)
    ; RDX = Dev (0..31)
    ; R8  = Func (0..7)
    ; R9  = Register Offset (0..255, must be dword aligned)
    push rdx
    push rcx
    push rbx

    ; Build address:
    ; Bit 31: Enable
    ; Bits 23..16: Bus
    ; Bits 15..11: Dev
    ; Bits 10..8: Func
    ; Bits 7..2: Reg (offset)
    mov eax, 0x80000000             ; Enable bit
    
    and rcx, 0xFF
    shl rcx, 16                     ; Bus
    or rax, rcx

    and rdx, 0x1F
    shl rdx, 11                     ; Dev
    or rax, rdx

    and r8, 0x07
    shl r8, 8                       ; Func
    or rax, r8

    and r9, 0xFC                    ; Force dword alignment
    or rax, r9

    ; Write address to config port
    mov dx, PCI_CONFIG_ADDRESS
    out dx, eax

    ; Read data from data port
    mov dx, PCI_CONFIG_DATA
    in eax, dx

    pop rbx
    pop rcx
    pop rdx
    ret

pci_write_config:
    ; RCX = Bus
    ; RDX = Dev
    ; R8  = Func
    ; R9  = Register Offset
    ; [rsp + 40] = Value (passed on stack in Win64 calling convention)
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

    ; Get value from stack
    ; Stack has: shadow space (32 bytes) + push rbx (8) + push rcx (8) + push rdx (8) = 56 bytes offset
    mov eax, [rsp + 56 + 8]         ; Value to write
    
    mov dx, PCI_CONFIG_DATA
    out dx, eax

    pop rbx
    pop rcx
    pop rdx
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

    lea rcx, [msg_pci_scan]
    call con_puts
    lea rcx, [msg_pci_scan]
    call serial_puts

    ; Loop through buses
    xor r12, r12                    ; r12 = Bus (0..255)

.bus_loop:
    xor r13, r13                    ; r13 = Dev (0..31)

.dev_loop:
    xor r14, r14                    ; r14 = Func (0..7)

.func_loop:
    ; Read vendor ID (register offset 0)
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    xor r9, r9                      ; Reg offset = 0
    call pci_read_config
    
    cmp ax, 0xFFFF                  ; Device exists?
    je .next_func

    ; Device exists! Extract Vendor ID and Device ID
    mov r15d, eax                   ; Save vendor/device word
    
    ; If func == 0, check if multi-function device. If not, only check func 0.
    cmp r14, 0
    jne .print_device
    
    ; Read header type (register offset 0x0C)
    mov rcx, r12
    mov rdx, r13
    xor r8, r8
    mov r9, 0x0C
    call pci_read_config
    shr eax, 16                     ; Header type is in third byte (bits 16..23)
    and al, 0x80                    ; Bit 7 indicates multi-function
    mov [is_multi_func], al

.print_device:
    ; Print Bus/Dev/Func and Vendor:Device
    lea rcx, [msg_dev_prefix]
    call serial_puts
    mov rcx, r12
    call serial_put_hex             ; Bus
    mov rcx, ':'
    call serial_putchar
    mov rcx, r13
    call serial_put_hex             ; Dev
    mov rcx, '.'
    call serial_putchar
    mov rcx, r14
    call serial_put_hex             ; Func
    lea rcx, [msg_dev_middle]
    call serial_puts

    movzx rcx, r15w                 ; Vendor
    call serial_put_hex
    mov rcx, ':'
    call serial_putchar
    mov eax, r15d
    shr eax, 16                     ; Device
    movzx rcx, ax
    call serial_put_hex
    lea rcx, [pci_newline]
    call serial_puts

    ; Check if this is the Intel AX211 WiFi device (VEN_8086, DEV_7E40)
    cmp r15w, 0x8086                ; Intel Vendor ID
    jne .next_func
    mov eax, r15d
    shr eax, 16
    cmp ax, 0x7E40                  ; AX211 Device ID
    jne .next_func

    ; Found the AX211!
    mov [wifi_bus], r12d
    mov [wifi_dev], r13d
    mov [wifi_func], r14d
    mov byte [wifi_found], 1

    ; Read BAR0 (offset 0x10) and BAR1 (offset 0x14) to get 64-bit base address
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0x10
    call pci_read_config
    mov [wifi_bar0_low], eax

    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0x14
    call pci_read_config
    mov [wifi_bar0_high], eax

    ; Combine to 64-bit physical BAR0 (mask lower 4 bits for flag memory space type)
    mov rax, [wifi_bar0_high]
    shl rax, 32
    mov edx, [wifi_bar0_low]
    and edx, 0xFFFFFFF0             ; Clear flags
    or rax, rdx
    mov [wifi_reg_base], rax

    ; Enable PCIe Bus Master + Memory Space Access (Command register, offset 0x04)
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0x04
    call pci_read_config
    
    or ax, 0x06                     ; Set bit 1 (Memory Space) and bit 2 (Bus Master)
    
    ; Write back to Command register
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0x04
    push rax                        ; Pass value on stack (for Win64)
    sub rsp, 32                     ; shadow space
    call pci_write_config
    add rsp, 40                     ; Clean stack + shadow space

    lea rcx, [msg_wifi_found]
    call con_puts
    lea rcx, [msg_wifi_found]
    call serial_puts

    mov rcx, [wifi_reg_base]
    call con_put_hex
    call con_newline
    mov rcx, [wifi_reg_base]
    call serial_put_hex
    lea rcx, [pci_newline]
    call serial_puts

.next_func:
    ; If not multi-function and func == 0, skip remaining functions of this device
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

    ; Print scan complete
    lea rcx, [msg_pci_done]
    call con_puts
    lea rcx, [msg_pci_done]
    call serial_puts

    cmp byte [wifi_found], 0
    jnz .done
    lea rcx, [msg_wifi_missing]
    call con_puts
    lea rcx, [msg_wifi_missing]
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

pci_get_wifi_device:
    ; Returns:
    ; RAX = physical register base address (or 0 if not found)
    ; RCX = bus (8 bits) | dev (8 bits) | func (8 bits)
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
wifi_reg_base dq 0
wifi_bus dd 0
wifi_dev dd 0
wifi_func dd 0
wifi_bar0_low dd 0
wifi_bar0_high dd 0
wifi_found db 0
is_multi_func db 0

msg_pci_scan db "PCI: Scanning PCI Bus...", 13, 10, 0
msg_dev_prefix db "  PCI: ", 0
msg_dev_middle db " -> ", 0
msg_wifi_found db "PCI: Intel AX211 WiFi Device Found! MMIO base: 0x", 0
msg_wifi_missing db "PCI: WARNING - Intel AX211 WiFi Device NOT found on PCI bus!", 13, 10, 0
msg_pci_done db "PCI: Bus scan complete.", 13, 10, 0
pci_newline db 13, 10, 0
