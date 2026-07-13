; ==============================================================================
; x86-24scope OS - ACPI Table Parser Driver
; ==============================================================================
bits 64
default rel

section .text

global acpi_init
global acpi_find_table

extern con_puts
extern con_put_hex
extern con_newline
extern serial_puts
extern serial_put_hex

; BootInfo offset offsets:
; 56: RsdpAddress (8 bytes)

acpi_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13

    ; Save BootInfo pointer
    mov r12, rcx

    ; Get RSDP address from BootInfo
    mov rbx, [r12 + 56]
    test rbx, rbx
    jz .no_rsdp

    mov [rsdp_ptr], rbx

    ; Print RSDP found
    lea rcx, [msg_rsdp_found]
    call con_puts
    lea rcx, [msg_rsdp_found]
    call serial_puts
    mov rcx, rbx
    call con_put_hex
    call con_newline
    mov rcx, rbx
    call serial_put_hex
    lea rcx, [acpi_newline]
    call serial_puts

    ; Check RSDP signature "RSD PTR "
    mov rax, [rbx]
    mov r11, 0x2052545020445352    ; "RSD PTR " in little endian
    cmp rax, r11
    jne .invalid_rsdp

    ; Read ACPI revision (offset 15 of RSDP)
    movzx eax, byte [rbx + 15]
    mov [acpi_revision], al

    ; Parse tables
    test al, al
    jz .parse_rsdt                  ; Revision 0 = ACPI 1.0 (uses RSDT)

    ; Revision >= 1 = ACPI 2.0+ (uses XSDT)
    mov rsi, [rbx + 24]             ; XsdtAddress (offset 24, 64-bit)
    test rsi, rsi
    jz .parse_rsdt                  ; Fallback to RSDT if XSDT is NULL

    mov [xsdt_ptr], rsi
    lea rcx, [msg_xsdt_found]
    call con_puts
    lea rcx, [msg_xsdt_found]
    call serial_puts
    mov rcx, rsi
    call con_put_hex
    call con_newline
    mov rcx, rsi
    call serial_put_hex
    lea rcx, [acpi_newline]
    call serial_puts

    ; Parse XSDT table pointers
    ; XSDT header is 36 bytes. Followed by array of 64-bit physical addresses.
    mov ecx, [rsi + 4]              ; Length of XSDT table
    sub ecx, 36                     ; Subtract header size
    shr ecx, 3                      ; Number of 64-bit pointers (div 8)
    lea rdi, [rsi + 36]             ; Start of pointer array
    mov [xsdt_entries_count], ecx
    
    ; Parse MADT from XSDT
    lea rdx, [sig_madt]
    call find_table_in_xsdt
    test rax, rax
    jz .xsdt_done
    call parse_madt

.xsdt_done:
    jmp .done

.parse_rsdt:
    ; RsdtAddress is a 32-bit field at offset 16 — do not read a full qword
    ; (the next dword is Length on ACPI 2.0 RSDPs and would pollute the address).
    mov eax, [rbx + 16]
    mov rsi, rax
    test rsi, rsi
    jz .invalid_rsdp

    mov [rsdt_ptr], rsi
    lea rcx, [msg_rsdt_found]
    call con_puts
    lea rcx, [msg_rsdt_found]
    call serial_puts
    mov rcx, rsi
    call con_put_hex
    call con_newline
    mov rcx, rsi
    call serial_put_hex
    lea rcx, [acpi_newline]
    call serial_puts

    ; Parse RSDT table pointers
    ; RSDT header is 36 bytes. Followed by array of 32-bit physical addresses.
    mov ecx, [rsi + 4]              ; Length of RSDT
    sub ecx, 36
    shr ecx, 2                      ; Number of 32-bit pointers (div 4)
    lea rdi, [rsi + 36]
    mov [rsdt_entries_count], ecx

    ; Parse MADT from RSDT
    lea rdx, [sig_madt]
    call find_table_in_rsdt
    test rax, rax
    jz .done
    call parse_madt
    jmp .done

.no_rsdp:
    lea rcx, [msg_no_rsdp]
    call con_puts
    lea rcx, [msg_no_rsdp]
    call serial_puts
    jmp .done

.invalid_rsdp:
    lea rcx, [msg_invalid_rsdp]
    call con_puts
    lea rcx, [msg_invalid_rsdp]
    call serial_puts

.done:
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

; Find table in XSDT
; RDI = Pointer to array of 64-bit pointers
; RCX = Number of entries
; RDX = 4-byte signature string pointer
find_table_in_xsdt:
    push rsi
    push rbx
    xor rsi, rsi                    ; Counter
.loop:
    cmp rsi, rcx
    jae .not_found
    
    mov rbx, [rdi + rsi * 8]        ; Get table physical address
    mov eax, [rbx]                  ; Read 4-byte signature
    mov r11d, [rdx]
    cmp eax, r11d
    je .found

    inc rsi
    jmp .loop
.not_found:
    xor rax, rax
    pop rbx
    pop rsi
    ret
.found:
    mov rax, rbx                    ; Return table pointer
    pop rbx
    pop rsi
    ret

; Find table in RSDT
; RDI = Pointer to array of 32-bit pointers
; RCX = Number of entries
; RDX = 4-byte signature string pointer
find_table_in_rsdt:
    push rsi
    push rbx
    xor rsi, rsi
.loop:
    cmp rsi, rcx
    jae .not_found

    mov ebx, [rdi + rsi * 4]        ; Get table physical address (32-bit)
    mov eax, [rbx]                  ; Read signature
    mov r11d, [rdx]
    cmp eax, r11d
    je .found

    inc rsi
    jmp .loop
.not_found:
    xor rax, rax
    pop rbx
    pop rsi
    ret
.found:
    mov eax, ebx                    ; Zero-extend 32-bit addr to 64-bit
    pop rbx
    pop rsi
    ret

; Find an ACPI table by signature (API for other drivers)
; RCX = 4-byte signature pointer (e.g. "MCFG")
acpi_find_table:
    push rbx
    push rdi
    push rcx
    
    mov rdx, rcx                    ; rdx = signature
    
    ; Check if we have XSDT or RSDT
    mov rsi, [xsdt_ptr]
    test rsi, rsi
    jz .try_rsdt

    mov ecx, [xsdt_entries_count]
    lea rdi, [rsi + 36]
    call find_table_in_xsdt
    jmp .done

.try_rsdt:
    mov rsi, [rsdt_ptr]
    test rsi, rsi
    jz .not_found

    mov ecx, [rsdt_entries_count]
    lea rdi, [rsi + 36]
    call find_table_in_rsdt
    jmp .done

.not_found:
    xor rax, rax
.done:
    pop rcx
    pop rdi
    pop rbx
    ret

; Parse MADT Table
; RAX = MADT table pointer
parse_madt:
    push rbx
    push rdi
    push rsi
    
    mov rbx, rax                    ; rbx = MADT base
    mov ecx, [rbx + 4]              ; MADT length
    sub ecx, 44                     ; Subtract header (36) + LAPIC fields (8)
    lea rsi, [rbx + 44]             ; rsi = start of MADT entry structures

.loop:
    cmp ecx, 0
    jle .done

    movzx eax, byte [rsi]           ; Type
    movzx edx, byte [rsi + 1]       ; Length

    cmp al, 1                       ; I/O APIC structure
    jne .check_override

    ; Found I/O APIC!
    ; Offset 4: 32-bit physical address of I/O APIC
    mov r8d, [rsi + 4]
    
    ; Update local global variable
    extern ioapic_base_ptr
    lea r10, [ioapic_base_ptr]
    mov eax, r8d
    mov [r10], rax
    mov r9, rax                     ; Preserve for printing (calls clobber rax)

    lea rcx, [msg_ioapic_found]
    call con_puts
    lea rcx, [msg_ioapic_found]
    call serial_puts
    mov rcx, r9
    call con_put_hex
    call con_newline
    mov rcx, r9
    call serial_put_hex
    lea rcx, [acpi_newline]
    call serial_puts
    jmp .next_entry

.check_override:
    cmp al, 2                       ; Interrupt Source Override
    jne .next_entry

    ; Found override!
    ; Offset 2: Bus (0 = ISA)
    ; Offset 3: Source (IRQ number, e.g. 0)
    ; Offset 4: GlobalSystemInterrupt (what IOAPIC pin it maps to, e.g. 2)
    movzx r8d, byte [rsi + 2]       ; Bus
    movzx r9d, byte [rsi + 3]       ; Source IRQ
    mov r10d, [rsi + 4]             ; Global IRQ pin

    cmp r9d, 0                      ; Is it IRQ0 override?
    jne .next_entry

    ; Save IRQ0 pin override in global
    mov [irq0_pin_override], r10d

.next_entry:
    add rsi, rdx                    ; Move to next entry (add length)
    sub ecx, edx                    ; Subtract length from remaining
    jmp .loop

.done:
    pop rsi
    pop rdi
    pop rbx
    ret

section .data
align 8
rsdp_ptr dq 0
rsdt_ptr dq 0
xsdt_ptr dq 0

xsdt_entries_count dd 0
rsdt_entries_count dd 0

acpi_revision db 0
irq0_pin_override dd 2              ; Default is 2 (IRQ0 maps to pin 2)

sig_madt db "APIC"
sig_mcfg db "MCFG"

msg_no_rsdp db "ACPI: WARNING - No RSDP address passed from bootloader!", 13, 10, 0
msg_rsdp_found db "ACPI: RSDP found at physical address: 0x", 0
msg_xsdt_found db "ACPI: XSDT found at physical address: 0x", 0
msg_rsdt_found db "ACPI: RSDT found at physical address: 0x", 0
msg_invalid_rsdp db "ACPI: ERROR - Invalid RSDP signature!", 13, 10, 0
msg_ioapic_found db "ACPI: MADT parsed. I/O APIC physical base: 0x", 0
acpi_newline db 13, 10, 0
