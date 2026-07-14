; ==============================================================================
; x86-24scope OS - Interrupt Descriptor Table (IDT)
; ==============================================================================
bits 64
default rel

section .text

global idt_init
global idt_register_handler
extern con_puts
extern con_put_hex
extern con_newline
extern serial_puts
extern serial_put_hex

; The IDT must live in a writable section: idt_init fills it at runtime, and
; UEFI maps the image's .text read-only (writes there triple-fault the CPU).
section .bss
align 16
idt:
    resb 256 * 16                   ; 256 IDT descriptors (16 bytes each)

section .data
align 8
idt_ptr:
    dw (256 * 16) - 1               ; Limit
    dq idt                          ; Base

section .text

; Register list of ISR stubs
align 8
isr_stub_table:
%assign i 0
%rep 256
    dq isr_stub_%+i
%assign i i+1
%endrep

idt_init:
    push rdi
    push rsi
    push rbx

    lea rsi, [isr_stub_table]
    lea rdi, [idt]
    xor rbx, rbx                    ; Interrupt counter

.loop:
    mov rdx, [rsi + rbx * 8]        ; Get ISR stub address
    
    ; Populate IDT Descriptor
    mov [rdi], dx                   ; Offset 15..0
    mov word [rdi + 2], 0x08        ; Selector (Kernel Code)
    mov byte [rdi + 4], 0           ; IST
    mov byte [rdi + 5], 0x8E        ; Type/Attr (Present, 64-bit Interrupt Gate, DPL=0)
    shr rdx, 16
    mov [rdi + 6], dx               ; Offset 31..16
    shr rdx, 16
    mov [rdi + 8], edx              ; Offset 63..32
    mov dword [rdi + 12], 0         ; Reserved

    add rdi, 16
    inc rbx
    cmp rbx, 256
    jl .loop

    ; Load IDT
    lidt [idt_ptr]

    pop rbx
    pop rsi
    pop rdi
    ret

; Register a custom interrupt handler (e.g. for timer, keyboard, or WiFi)
; RCX = Vector (0..255)
; RDX = Handler function address
idt_register_handler:
    push rbx
    lea rbx, [custom_handlers]
    mov [rbx + rcx * 8], rdx
    pop rbx
    ret

; Common Interrupt Handler
align 8
isr_common:
    ; Stack layout at this point:
    ; [rsp + 0]  - R15
    ; [rsp + 8]  - R14
    ; [rsp + 16] - R13
    ; [rsp + 24] - R12
    ; [rsp + 32] - R11
    ; [rsp + 40] - R10
    ; [rsp + 48] - R9
    ; [rsp + 56] - R8
    ; [rsp + 64] - RBP
    ; [rsp + 72] - RDI
    ; [rsp + 80] - RSI
    ; [rsp + 88] - RDX
    ; [rsp + 96] - RCX
    ; [rsp + 104] - RBX
    ; [rsp + 112] - RAX
    ; [rsp + 120] - Interrupt Vector Number
    ; [rsp + 128] - Error Code
    ; [rsp + 136] - RIP (pushed by CPU)
    ; [rsp + 144] - CS (pushed by CPU)
    ; [rsp + 152] - RFLAGS (pushed by CPU)
    ; [rsp + 160] - RSP (pushed by CPU)
    ; [rsp + 168] - SS (pushed by CPU)

    push rbp
    mov rbp, rsp

    ; Check if there is a custom handler registered
    mov rcx, [rbp + 128]            ; Get vector number from stack
    lea rax, [custom_handlers]
    mov rax, [rax + rcx * 8]
    test rax, rax
    jz .no_custom_handler
    
    ; Call custom handler
    call rax
    jmp .done

.no_custom_handler:
    ; If it's an exception (vectors 0..31), print error details and halt
    cmp rcx, 32
    jae .unhandled_irq

    ; Print Exception Info
    lea rcx, [msg_exception]
    call con_puts
    lea rcx, [msg_exception]
    call serial_puts

    mov rcx, [rbp + 128]            ; Vector
    call con_put_hex
    call con_newline
    mov rcx, [rbp + 128]
    call serial_put_hex
    call serial_newline

    ; Print registers (console + serial)
    lea rcx, [msg_rip]
    call con_puts
    lea rcx, [msg_rip]
    call serial_puts
    mov rcx, [rbp + 144]            ; RIP
    call con_put_hex
    call con_newline
    mov rcx, [rbp + 144]
    call serial_put_hex
    call serial_newline

    lea rcx, [msg_rsp]
    call con_puts
    lea rcx, [msg_rsp]
    call serial_puts
    mov rcx, [rbp + 168]            ; RSP
    call con_put_hex
    call con_newline
    mov rcx, [rbp + 168]
    call serial_put_hex
    call serial_newline

    cli
.halt:
    hlt
    jmp .halt

.unhandled_irq:
    ; For unhandled hardware IRQs, just send EOI and return
    ; In Phase 2, we will call local APIC EOI
    extern apic_send_eoi
    call apic_send_eoi

.done:
    pop rbp
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    
    add rsp, 16                     ; Clean up vector number and error code
    iretq

serial_newline:
    push rbp
    mov rbp, rsp
    lea rcx, [newline]
    call serial_puts
    pop rbp
    ret

; Define custom handlers array (256 pointers)
section .data
align 8
custom_handlers:
    times 256 dq 0

msg_exception db "!!! CPU EXCEPTION OCCURRED: Vector 0x", 0
msg_rip       db "  RIP: 0x", 0
msg_rsp       db "  RSP: 0x", 0
newline       db 13, 10, 0

; Generate the 256 ISR stubs
section .text

; Helper macros to push dummy error code if CPU doesn't push one
%macro ISR_NOERR 1
align 8
isr_stub_%1:
    push qword 0                    ; Dummy error code
    push qword %1                   ; Interrupt vector number
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    jmp isr_common
%endmacro

%macro ISR_ERR 1
align 8
isr_stub_%1:
    ; Error code is already pushed by CPU
    push qword %1                   ; Interrupt vector number
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    jmp isr_common
%endmacro

; Generate exceptions 0..31
ISR_NOERR 0  ; Divide by Zero
ISR_NOERR 1  ; Debug
ISR_NOERR 2  ; NMI
ISR_NOERR 3  ; Breakpoint
ISR_NOERR 4  ; Overflow
ISR_NOERR 5  ; Bound Range Exceeded
ISR_NOERR 6  ; Invalid Opcode
ISR_NOERR 7  ; Device Not Available
ISR_ERR   8  ; Double Fault
ISR_NOERR 9  ; Coprocessor Segment Overrun
ISR_ERR   10 ; Invalid TSS
ISR_ERR   11 ; Segment Not Present
ISR_ERR   12 ; Stack Segment Fault
ISR_ERR   13 ; General Protection Fault
ISR_ERR   14 ; Page Fault
ISR_NOERR 15 ; Reserved
ISR_NOERR 16 ; x87 Floating-Point Exception
ISR_ERR   17 ; Alignment Check
ISR_NOERR 18 ; Machine Check
ISR_NOERR 19 ; SIMD Floating-Point Exception
ISR_NOERR 20 ; Virtualization Exception
ISR_ERR   21 ; Control Protection Exception
%assign i 22
%rep 10
    ISR_NOERR i
    %assign i i+1
%endrep

; Generate remaining vectors (32..255) for IRQs/APIC interrupts
%assign i 32
%rep 224
    ISR_NOERR i
    %assign i i+1
%endrep
