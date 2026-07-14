; ==============================================================================
; x86-24scope OS - Keyboard input (PS/2 poll + COM1 serial fallback)
; ==============================================================================
bits 64
default rel

section .text

global kbd_init
global kbd_getchar
global kbd_readline

extern con_putchar
extern serial_putchar
extern sleep_ms

KBD_DATA    equ 0x60
KBD_STATUS  equ 0x64
COM1        equ 0x3F8

; No-op for now (polling path needs no IRQ)
kbd_init:
    mov byte [shift_down], 0
    mov byte [caps_lock], 0
    ret

; Block until a key is available. RAX = ASCII (0 if extended ignored)
kbd_getchar:
    push rbx
    push rcx
    push rdx
.wait:
    ; Prefer serial if a byte is waiting (QEMU -serial stdio / metal UART)
    mov dx, COM1 + 5
    in al, dx
    test al, 0x01
    jz .try_ps2
    mov dx, COM1
    in al, dx
    and eax, 0xFF
    cmp al, 13                      ; CR -> LF
    jne .got
    mov al, 10
    jmp .got

.try_ps2:
    mov dx, KBD_STATUS
    in al, dx
    test al, 0x01                   ; output buffer full
    jz .idle
    mov dx, KBD_DATA
    in al, dx
    movzx ebx, al
    ; Ignore releases (bit 7) except shift
    test bl, 0x80
    jnz .release
    cmp bl, 0x2A                    ; LSHIFT
    je .shift_on
    cmp bl, 0x36                    ; RSHIFT
    je .shift_on
    cmp bl, 0x3A                    ; CAPS
    je .caps_tog
    cmp bl, 0x0E                    ; Backspace
    je .bksp
    cmp bl, 0x1C                    ; Enter
    je .enter
    ; Translate
    cmp bl, 0x58
    ja .idle
    lea rdx, [scancode_map]
    movzx eax, byte [rdx + rbx]
    test al, al
    jz .idle
    cmp byte [shift_down], 0
    jnz .apply_shift
    cmp byte [caps_lock], 0
    jz .got
    ; caps: toggle a-z
    cmp al, 'a'
    jb .got
    cmp al, 'z'
    ja .got
    sub al, 32
    jmp .got

.apply_shift:
    lea rdx, [scancode_shift]
    movzx eax, byte [rdx + rbx]
    test al, al
    jnz .got
    lea rdx, [scancode_map]
    movzx eax, byte [rdx + rbx]
    jmp .got

.shift_on:
    mov byte [shift_down], 1
    jmp .idle

.release:
    and bl, 0x7F
    cmp bl, 0x2A
    je .shift_off
    cmp bl, 0x36
    je .shift_off
    jmp .idle
.shift_off:
    mov byte [shift_down], 0
    jmp .idle

.caps_tog:
    xor byte [caps_lock], 1
    jmp .idle

.bksp:
    mov al, 8
    jmp .got
.enter:
    mov al, 10
    jmp .got

.idle:
    mov rcx, 1
    call sleep_ms
    jmp .wait

.got:
    and eax, 0xFF
    pop rdx
    pop rcx
    pop rbx
    ret

; RCX = dest buffer, RDX = max len (incl NUL), R8 = echo mode (0=echo, 1=mask *)
; Returns RAX = length excluding NUL
kbd_readline:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    mov rdi, rcx                    ; dest
    mov r12, rdx                    ; max
    mov r13, r8                     ; mask
    test r12, r12
    jz .empty
    dec r12                         ; leave room for NUL
    xor r14, r14                    ; length

.loop:
    call kbd_getchar
    mov ebx, eax
    cmp bl, 10
    je .finish
    cmp bl, 13
    je .finish
    cmp bl, 8
    je .backspace
    cmp bl, 127
    je .backspace
    cmp bl, 32
    jb .loop
    cmp r14, r12
    jae .loop
    mov [rdi + r14], bl
    inc r14
    ; echo
    cmp r13, 0
    jz .echo_char
    mov rcx, '*'
    jmp .do_echo
.echo_char:
    movzx ecx, bl
.do_echo:
    push rcx
    call con_putchar
    pop rcx
    call serial_putchar
    jmp .loop

.backspace:
    test r14, r14
    jz .loop
    dec r14
    mov rcx, 8
    call con_putchar
    mov rcx, 8
    call serial_putchar
    mov rcx, ' '
    call con_putchar
    mov rcx, ' '
    call serial_putchar
    mov rcx, 8
    call con_putchar
    mov rcx, 8
    call serial_putchar
    jmp .loop

.finish:
    mov byte [rdi + r14], 0
    mov rcx, 13
    call con_putchar
    mov rcx, 10
    call con_putchar
    mov rcx, 13
    call serial_putchar
    mov rcx, 10
    call serial_putchar
    mov rax, r14
    jmp .done

.empty:
    xor rax, rax
.done:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

section .data
shift_down db 0
caps_lock db 0

; Set 1 make codes 0x00-0x58 → ASCII (unshifted / shifted)
align 16
scancode_map:
    db 0,27,'1','2','3','4','5','6','7','8','9','0','-','=',8
    db 9,'q','w','e','r','t','y','u','i','o','p','[',']',10
    db 0,'a','s','d','f','g','h','j','k','l',';',39,'`'
    db 0,'\','z','x','c','v','b','n','m',',','.','/',0
    db '*',0,' '
    times (0x59 - 0x39) db 0

scancode_shift:
    db 0,27,'!','@','#','$','%','^','&','*','(',')','_','+',8
    db 9,'Q','W','E','R','T','Y','U','I','O','P','{','}',10
    db 0,'A','S','D','F','G','H','J','K','L',':','"','~'
    db 0,'|','Z','X','C','V','B','N','M','<','>','?',0
    db '*',0,' '
    times (0x59 - 0x39) db 0
