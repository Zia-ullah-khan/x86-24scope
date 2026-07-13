; ==============================================================================
; x86-24scope OS - COM1 Serial Port Debug Driver
; ==============================================================================
bits 64
default rel

section .text

global serial_init
global serial_putchar
global serial_puts
global serial_put_hex

PORT equ 0x3F8                      ; COM1 base port

serial_init:
    push rdx
    push rax

    ; Initialize COM1 serial port
    mov dx, PORT + 1
    xor al, al
    out dx, al                      ; Disable interrupts

    mov dx, PORT + 3
    mov al, 0x80
    out dx, al                      ; Enable DLAB (set baud rate divisor)

    mov dx, PORT + 0
    mov al, 0x01
    out dx, al                      ; Set divisor to 1 (lo byte) -> 115200 baud
    
    mov dx, PORT + 1
    xor al, al
    out dx, al                      ; Set divisor to 0 (hi byte)

    mov dx, PORT + 3
    mov al, 0x03
    out dx, al                      ; 8 bits, no parity, one stop bit (8N1)

    mov dx, PORT + 2
    mov al, 0xC7
    out dx, al                      ; Enable FIFO, clear them, 14-byte threshold

    mov dx, PORT + 4
    mov al, 0x0F
    out dx, al                      ; Enable IRQs, RTS/DSR set

    pop rax
    pop rdx
    ret

; Read line status and wait until transmit register is empty
serial_wait:
    push rdx
    push rax
    mov dx, PORT + 5
.loop:
    in al, dx
    test al, 0x20                   ; Transmit Holding Register Empty bit
    jz .loop
    pop rax
    pop rdx
    ret

serial_putchar:
    ; RCX = character byte
    push rdx
    push rax

    mov al, cl
    call serial_wait
    
    mov dx, PORT
    out dx, al                      ; Send character

    pop rax
    pop rdx
    ret

serial_puts:
    ; RCX = Null-terminated string pointer
    push rsi
    mov rsi, rcx
.loop:
    lodsb
    test al, al
    jz .done
    movzx ecx, al
    call serial_putchar
    jmp .loop
.done:
    pop rsi
    ret

serial_put_hex:
    ; RCX = 64-bit value to print in hex
    push rbx
    push rdi
    push rsi
    sub rsp, 32

    mov rsi, rcx
    lea rdi, [rsp + 16]
    mov byte [rdi], 0
    dec rdi

    mov rcx, 16
.loop:
    mov rbx, rsi
    and rbx, 0xF
    cmp rbx, 10
    jae .letter
    add rbx, '0'
    jmp .store
.letter:
    add rbx, 'A' - 10
.store:
    mov [rdi], bl
    dec rdi
    shr rsi, 4
    loop .loop

    inc rdi
    mov rcx, rdi
    call serial_puts

    add rsp, 32
    pop rsi
    pop rdi
    pop rbx
    ret
