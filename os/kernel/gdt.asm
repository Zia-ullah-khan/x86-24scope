; ==============================================================================
; x86-24scope OS - Global Descriptor Table (GDT)
; ==============================================================================
bits 64
default rel

section .text

global gdt_init

gdt_init:
    ; Load the GDT
    lgdt [gdt_ptr]

    ; Reload CS and segment registers using iretq
    mov rax, rsp                    ; Save current stack pointer
    
    push 0x10                       ; SS (Data Segment Selector = 0x10)
    push rax                        ; RSP
    pushfq                          ; RFLAGS
    push 0x08                       ; CS (Code Segment Selector = 0x08)
    lea rax, [.reload_cs]
    push rax                        ; RIP
    iretq                           ; Performs far transfer to long mode CS

.reload_cs:
    ; Reload data segment registers
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    ret

section .data

align 16
gdt_start:
    ; Descriptor 0: Null Descriptor
    dq 0

    ; Descriptor 1: Kernel Code Segment (64-bit)
    ; Access byte: 0x9A (Present, ring 0, Executable, Readable)
    ; Flags: 0x20 (Long mode L=1, SZ=0)
    db 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x9A, 0x20, 0x00

    ; Descriptor 2: Kernel Data Segment (64-bit)
    ; Access byte: 0x92 (Present, ring 0, Writable, grows-up)
    ; Flags: 0x00 (64-bit data doesn't use L flag, but flat layout)
    db 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x92, 0x00, 0x00
gdt_end:

align 8
gdt_ptr:
    dw gdt_end - gdt_start - 1      ; Limit
    dq gdt_start                    ; Base
