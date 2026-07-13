; ==============================================================================
; x86-24scope OS - PIT 1ms Timer Driver
; ==============================================================================
bits 64
default rel

section .text

global timer_init
global sleep_ms
global get_ticks

extern idt_register_handler
extern apic_send_eoi
extern con_puts
extern serial_puts

; PIT IO Ports
PIT_DATA_PORT    equ 0x40
PIT_COMMAND_PORT equ 0x43

; 1193182 Hz / 1000 Hz = 1193 divisor
PIT_DIVISOR      equ 1193

; Assumed TSC frequency for the fallback busy-wait (3 GHz).
; Only used when the PIT is absent (e.g. Hyper-V Gen 2 has no 8254).
TSC_CYCLES_PER_MS equ 3000000

timer_init:
    push rbp
    mov rbp, rsp
    push rcx
    push rdx

    ; 1. Register timer_handler for IRQ0 (vector 32)
    mov rcx, 32                     ; IRQ0 -> Vector 32
    lea rdx, [timer_handler]
    call idt_register_handler

    ; 2. Configure 8254 PIT Channel 0
    ; Command: 0x36 = Channel 0, LSB/MSB access, Mode 3 (Square Wave), Binary
    mov dx, PIT_COMMAND_PORT
    mov al, 0x36
    out dx, al

    ; 3. Send Divisor LSB then MSB
    mov dx, PIT_DATA_PORT
    mov ax, PIT_DIVISOR
    out dx, al                      ; LSB
    mov al, ah
    out dx, al                      ; MSB

    ; 4. Detect whether PIT ticks actually arrive.
    ; Hyper-V Gen 2 and other modern platforms have no 8254; without this
    ; check sleep_ms would spin forever waiting for a tick.
    mov r8, [tick_count]
    rdtsc
    shl rdx, 32
    or rax, rdx
    mov r9, rax
    add r9, TSC_CYCLES_PER_MS * 100 ; Wait up to ~100ms worth of cycles

.detect_loop:
    mov rax, [tick_count]
    cmp rax, r8
    jne .pit_ok
    pause
    rdtsc
    shl rdx, 32
    or rax, rdx
    cmp rax, r9
    jb .detect_loop

    ; No ticks observed: fall back to TSC-based delays
    mov byte [pit_present], 0
    lea rcx, [msg_timer_tsc]
    call con_puts
    lea rcx, [msg_timer_tsc]
    call serial_puts
    jmp .done

.pit_ok:
    mov byte [pit_present], 1
    lea rcx, [msg_timer_init]
    call con_puts
    lea rcx, [msg_timer_init]
    call serial_puts

.done:
    pop rdx
    pop rcx
    pop rbp
    ret

; Timer Interrupt Handler
align 8
timer_handler:
    push rax
    
    ; Increment global tick count
    lock inc qword [tick_count]

    ; Send EOI to APIC
    call apic_send_eoi

    pop rax
    ret

; Busy-wait for a given number of milliseconds
sleep_ms:
    ; RCX = Milliseconds to wait
    push rbx
    push rcx
    push rdx

    cmp byte [pit_present], 0
    je .tsc_wait

    mov rbx, [tick_count]
    add rbx, rcx                    ; Target tick = current + wait

.wait_loop:
    mov rax, [tick_count]
    cmp rax, rbx
    jb .wait_loop
    jmp .done

.tsc_wait:
    ; No PIT: burn cycles on the TSC and advance the tick counter in
    ; software so get_ticks-based timeouts keep working.
    mov rbx, rcx                    ; Milliseconds to wait
    rdtsc
    shl rdx, 32
    or rax, rdx
    mov rcx, rax
    imul r8, rbx, TSC_CYCLES_PER_MS
    add rcx, r8                     ; Target TSC value

.tsc_loop:
    pause
    rdtsc
    shl rdx, 32
    or rax, rdx
    cmp rax, rcx
    jb .tsc_loop

    lock add qword [tick_count], rbx

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

get_ticks:
    mov rax, [tick_count]
    ret

section .data
align 8
tick_count dq 0
pit_present db 0

msg_timer_init db "Timer: PIT initialized for 1ms resolution.", 13, 10, 0
msg_timer_tsc  db "Timer: No PIT detected. Using TSC fallback for delays.", 13, 10, 0
