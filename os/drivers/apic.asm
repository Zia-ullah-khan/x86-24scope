; ==============================================================================
; x86-24scope OS - APIC and I/O APIC Interrupt Controller Driver
; ==============================================================================
bits 64
default rel

section .text

global apic_init
global apic_send_eoi
global ioapic_map_irq
global ioapic_base_ptr

extern con_puts
extern serial_puts

; Legacy PIC Ports
PIC1_COMMAND equ 0x20
PIC1_DATA    equ 0x21
PIC2_COMMAND equ 0xA0
PIC2_DATA    equ 0xA1

; APIC Register Offsets
LAPIC_ID     equ 0x20
LAPIC_VER    equ 0x30
LAPIC_TPR    equ 0x80
LAPIC_EOI    equ 0xB0
LAPIC_SVR    equ 0xF0

; Default Physical Bases
DEFAULT_LAPIC_BASE  equ 0xFEE00000
DEFAULT_IOAPIC_BASE equ 0xFEC00000

; IOAPIC Register Indices
IOAPIC_ID    equ 0x00
IOAPIC_VER   equ 0x01
IOAPIC_ARB   equ 0x02
IOAPIC_REDTBL_BASE equ 0x10         ; Redirection table starts at index 0x10 (each entry is 2 dwords)

apic_init:
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdx

    ; 1. Disable legacy 8259 PIC
    mov al, 0xFF
    out PIC1_DATA, al
    out PIC2_DATA, al
    
    ; 2. Initialize Local APIC
    ; Read IA32_APIC_BASE MSR (0x1B)
    mov ecx, 0x1B
    rdmsr
    
    ; Base address is in EAX (bits 12..31) and EDX (bits 32..35)
    and eax, 0xFFFFF000             ; Mask off flags
    mov [lapic_base_ptr], rax       ; Save base address

    ; Enable APIC by setting bit 11 of MSR 0x1B
    rdmsr
    or eax, 0x800                   ; Set bit 11 (APIC Global Enable)
    wrmsr

    ; Set Spurious Interrupt Vector Register (SVR)
    ; Bit 8 must be set to 1 to enable the Local APIC software-wise.
    ; We map spurious interrupt to vector 0xFF.
    mov rbx, [lapic_base_ptr]
    mov eax, [rbx + LAPIC_SVR]
    or eax, 0x1FF                   ; Set bit 8 (APIC Software Enable) and Vector = 0xFF
    mov [rbx + LAPIC_SVR], eax

    ; Set Task Priority Register (TPR) to 0 (allow all interrupts)
    xor eax, eax
    mov [rbx + LAPIC_TPR], eax

    ; 3. Initialize I/O APIC base
    ; In standard systems, the I/O APIC is at 0xFEC00000
    mov rax, DEFAULT_IOAPIC_BASE
    mov [ioapic_base_ptr], rax

    ; 4. Route IRQ0 (PIT) through I/O APIC to Vector 32
    ; IRQ0 maps to Redirection Entry 2 in I/O APIC (due to ACPI ISO override on standard systems)
    ; Or Entry 2 on standard AT-compatible IO APICs.
    mov ecx, 2                      ; Redirection Entry index (2 = IRQ2/IRQ0 override)
    mov edx, 32                     ; Vector 32 (IRQ0)
    call ioapic_map_irq

    ; Print status
    lea rcx, [msg_apic_init]
    call con_puts
    lea rcx, [msg_apic_init]
    call serial_puts

    ; 5. Enable hardware interrupts!
    sti

    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

apic_send_eoi:
    push rax
    push rbx
    mov rbx, [lapic_base_ptr]
    test rbx, rbx
    jz .done
    xor eax, eax
    mov [rbx + LAPIC_EOI], eax      ; Write 0 to EOI register
.done:
    pop rbx
    pop rax
    ret

; Map a hardware IRQ line to an interrupt vector on CPU0
; RCX = I/O APIC Redirection Entry Index (0..23)
; RDX = Vector Number (32..255)
ioapic_map_irq:
    push rbx
    push rdi
    push rsi

    mov rdi, [ioapic_base_ptr]
    test rdi, rdi
    jz .done

    ; Calculate register indices for Redirection Entry
    ; Index = 0x10 + Entry * 2 (low dword)
    ; Index + 1 = 0x11 + Entry * 2 (high dword)
    mov r8, rcx
    shl r8, 1
    add r8, IOAPIC_REDTBL_BASE      ; r8 = register index for low dword

    ; 1. Write low dword: Vector (8 bits) + delivery mode (000 = physical) + trigger mode (0 = edge)
    ; We set flags: Delivery Mode = 0x000, Destination Mode = 0 (Physical), Active High, Edge Triggered
    mov eax, edx                    ; Vector number
    and eax, 0xFF                   ; Force byte limit
    
    ; Write to IOREGSEL
    mov [rdi + 0x00], r8d
    ; Write to IOWIN
    mov [rdi + 0x10], eax

    ; 2. Write high dword: Destination field (0 = CPU0 physical APIC ID)
    inc r8                          ; r8 = index + 1
    xor eax, eax                    ; Destination APIC ID = 0 (CPU0)
    
    ; Write to IOREGSEL
    mov [rdi + 0x00], r8d
    ; Write to IOWIN
    mov [rdi + 0x10], eax

.done:
    pop rsi
    pop rdi
    pop rbx
    ret

section .data
align 8
lapic_base_ptr  dq 0
ioapic_base_ptr dq 0

msg_apic_init db "APIC: Interrupt controllers configured. Hardware interrupts enabled.", 13, 10, 0
