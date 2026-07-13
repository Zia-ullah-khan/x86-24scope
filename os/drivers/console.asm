; ==============================================================================
; x86-24scope OS - Framebuffer TUI Console Driver
; ==============================================================================
bits 64
default rel

section .text

global console_init
global con_putchar
global con_puts
global con_put_hex
global con_put_dec
global con_clear
global con_newline
global con_heartbeat

extern font8x16

; Colors (0x00RRGGBB; white is safe for both RGBX and BGRX).
BG_COLOR equ 0x0008111F            ; Deep dark blue
FG_COLOR equ 0x00FFFFFF            ; White text

CHAR_WIDTH  equ 8
CHAR_HEIGHT equ 16

console_init:
    push rbx
    push rdi

    ; RCX -> BootInfo:
    ; 0 width, 4 height, 8 pitch, 16 fb base, 24 fb size
    mov eax, [rcx + 0]
    test eax, eax
    jz .no_fb

    mov [fb_width], eax
    mov eax, [rcx + 4]
    mov [fb_height], eax

    ; Pitch must be >= width (some firmwares report 0 / stale PPSL)
    mov eax, [rcx + 8]
    mov ebx, [fb_width]
    cmp eax, ebx
    jae .pitch_ok
    mov eax, ebx
.pitch_ok:
    test eax, eax
    jnz .pitch_nonzero
    mov eax, ebx
.pitch_nonzero:
    mov [fb_pitch], eax

    mov rax, [rcx + 16]
    mov [fb_base], rax
    mov rax, [rcx + 24]
    mov [fb_size], rax

    ; Derive size if firmware reported 0 / too small
    mov eax, [fb_pitch]
    mov ebx, [fb_height]
    imul rax, rbx
    shl rax, 2
    mov rbx, [fb_size]
    test rbx, rbx
    jz .use_derived_size
    cmp rbx, rax
    jae .size_ok
.use_derived_size:
    mov [fb_size], rax
.size_ok:

    xor rdx, rdx
    mov eax, [fb_width]
    mov ebx, CHAR_WIDTH
    div ebx
    test eax, eax
    jnz .cols_ok
    mov eax, 1
.cols_ok:
    mov [max_cols], eax

    xor rdx, rdx
    mov eax, [fb_height]
    mov ebx, CHAR_HEIGHT
    div ebx
    test eax, eax
    jnz .rows_ok
    mov eax, 1
.rows_ok:
    mov [max_rows], eax

    mov dword [cursor_x], 0
    mov dword [cursor_y], 0

    pop rdi
    pop rbx
    ret

.no_fb:
    mov dword [fb_width], 0
    mov dword [fb_height], 0
    mov dword [fb_pitch], 0
    mov qword [fb_base], 0
    mov qword [fb_size], 0
    mov dword [max_cols], 0
    mov dword [max_rows], 0
    mov dword [cursor_x], 0
    mov dword [cursor_y], 0

    pop rdi
    pop rbx
    ret

con_clear:
    push rdi
    push rcx
    push rax
    push rbx

    mov rdi, [fb_base]
    test rdi, rdi
    jz .done

    cld
    mov rcx, [fb_size]
    shr rcx, 2
    test rcx, rcx
    jz .done
    mov rax, BG_COLOR
    rep stosd

    ; White bar at top — proves framebuffer writes regardless of font/text
    mov rdi, [fb_base]
    mov eax, [fb_pitch]
    mov ebx, 8
    imul rax, rbx
    mov rcx, rax
    mov eax, 0x00FFFFFF
    rep stosd

.done:
    mov dword [cursor_x], 0
    mov dword [cursor_y], 1

    pop rbx
    pop rax
    pop rcx
    pop rdi
    ret

; Paint an alternating green/yellow block in the top-right corner.
; Called from the network poll loops as a liveness heartbeat: if the block
; blinks, the kernel is alive even when no text is visible.
con_heartbeat:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi

    mov rdi, [fb_base]
    test rdi, rdi
    jz .done

    inc dword [heartbeat_counter]
    mov eax, [heartbeat_counter]
    and eax, 0x200                  ; Toggle every 512 calls
    mov ebx, 0x0000FF00             ; Green
    jz .color_set
    mov ebx, 0x00FFFF00             ; Yellow
.color_set:

    ; Block: 32px wide, 8px tall at top-right
    mov eax, [fb_width]
    sub eax, 32
    shl rax, 2
    add rdi, rax                    ; rdi = top row, 32px from right edge

    cld
    mov edx, 8                      ; 8 rows
.row:
    mov rcx, 32
    mov eax, ebx
    push rdi
    rep stosd
    pop rdi
    mov eax, [fb_pitch]
    shl rax, 2
    add rdi, rax
    dec edx
    jnz .row

.done:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

con_newline:
    mov dword [cursor_x], 0
    inc dword [cursor_y]
    
    ; Check if we need to scroll
    mov eax, [cursor_y]
    cmp eax, [max_rows]
    jl .done
    call con_scroll
.done:
    ret

; Scroll console up by one line
con_scroll:
    push rsi
    push rdi
    push rbx
    push rcx

    mov rbx, [fb_base]
    test rbx, rbx
    jz .done
    mov eax, [fb_pitch]
    shl rax, 2                      ; Bytes per scanline (pitch * 4)
    mov rdx, rax                    ; rdx = bytes per scanline

    ; Offset for one char line (16 scanlines)
    shl rax, 4                      ; rax = bytes per character row (bytes_per_scanline * 16)
    
    ; Copy from (fb_base + char_row_bytes) to (fb_base)
    mov rdi, rbx                    ; Destination = top
    mov rsi, rbx
    add rsi, rax                    ; Source = second line
    
    ; Calculate size to copy: (height - 16) * pitch * 4
    mov rbx, rdx                    ; bytes per scanline
    mov ecx, [fb_height]
    sub ecx, CHAR_HEIGHT            ; Number of scanlines to copy
    imul rcx, rbx                   ; Total bytes to copy
    shr rcx, 3                      ; Copy in QWORDs (8 bytes)
    cld
    rep movsq

    ; Clear the bottom line (fill with BG_COLOR)
    mov rdi, [fb_base]
    
    ; Bottom line offset: (height - 16) * pitch * 4
    mov ecx, [fb_height]
    sub ecx, CHAR_HEIGHT
    mov eax, [fb_pitch]
    imul rcx, rax
    shl rcx, 2                      ; convert to bytes
    add rdi, rcx                    ; rdi = destination (start of last line)

    ; Size to clear: 16 scanlines * pitch * 4
    mov eax, [fb_pitch]
    shl rax, 4                      ; 16 * pitch (pixels)
    mov rcx, rax
    mov rax, BG_COLOR
    rep stosd

    ; Set cursor to last row
    mov eax, [max_rows]
    dec eax
    mov [cursor_y], eax
    mov dword [cursor_x], 0

.done:
    pop rcx
    pop rbx
    pop rdi
    pop rsi
    ret

con_putchar:
    ; RCX = ASCII character code
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    mov rax, [fb_base]
    test rax, rax
    jz .done

    and rcx, 0xFF                   ; Mask to byte
    
    ; Handle control characters
    cmp cl, 10                      ; '\n'
    je .handle_nl
    cmp cl, 13                      ; '\r'
    je .handle_cr
    cmp cl, 9                       ; '\t'
    je .handle_tab
    jmp .draw_char

.handle_nl:
    call con_newline
    jmp .done

.handle_cr:
    mov dword [cursor_x], 0
    jmp .done

.handle_tab:
    ; Add 4 spaces
    mov ecx, 4
.tab_loop:
    push rcx
    mov rcx, ' '
    call con_putchar
    pop rcx
    loop .tab_loop
    jmp .done

.draw_char:
    ; Get pointer to character bitmap
    lea rbx, [font8x16]
    shl rcx, 4                      ; char * 16 (16 bytes per character)
    add rbx, rcx                    ; rbx = pointer to glyph bytes

    ; Calculate screen position (fb_base + Y * pitch * 4 * 16 + X * 8 * 4)
    mov rdi, [fb_base]
    
    mov eax, [cursor_y]
    imul eax, CHAR_HEIGHT           ; Pixel Y
    mov edx, [fb_pitch]
    imul eax, edx                   ; Pixel Y * pitch
    shl rax, 2                      ; convert to byte offset (4 bytes per pixel)
    add rdi, rax

    mov eax, [cursor_x]
    shl eax, 3                      ; Pixel X = char X * 8
    shl rax, 2                      ; convert to byte offset
    add rdi, rax                    ; rdi = top-left pixel address of character

    ; Draw glyph (16 rows)
    xor r10, r10                    ; r10 = row index (0..15)

.row_loop:
    movzx r11d, byte [rbx + r10]    ; Get glyph byte for this row
    
    ; Draw 8 pixels for this row
    xor r12, r12                    ; r12 = pixel index (0..7)
.pixel_loop:
    ; Font bit is MSB to LSB (left to right)
    ; Check if bit is set: r11d & (0x80 >> r12)
    mov r13d, 0x80
    mov ecx, r12d
    shr r13d, cl
    test r11d, r13d
    jz .bg_pixel

    mov dword [rdi + r12 * 4], FG_COLOR
    jmp .next_pixel

.bg_pixel:
    mov dword [rdi + r12 * 4], BG_COLOR

.next_pixel:
    inc r12d
    cmp r12d, CHAR_WIDTH
    jl .pixel_loop

    ; Next scanline (add pitch * 4 bytes to rdi)
    mov eax, [fb_pitch]
    shl rax, 2
    add rdi, rax

    inc r10
    cmp r10, CHAR_HEIGHT
    jl .row_loop

    ; Advance cursor
    inc dword [cursor_x]
    mov eax, [cursor_x]
    cmp eax, [max_cols]
    jl .done
    call con_newline

.done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

con_puts:
    ; RCX = Null-terminated string pointer
    push rsi
    cld
    mov rsi, rcx
.loop:
    lodsb
    test al, al
    jz .done
    movzx ecx, al
    call con_putchar
    jmp .loop
.done:
    pop rsi
    ret

con_put_hex:
    ; RCX = 64-bit value to print in hex
    push rbx
    push rdi
    push rsi
    sub rsp, 32

    mov rsi, rcx
    lea rdi, [rsp + 16]
    mov byte [rdi], 0               ; Null terminator
    dec rdi

    mov rcx, 16                     ; 16 hex digits
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
    call con_puts

    add rsp, 32
    pop rsi
    pop rdi
    pop rbx
    ret

con_put_dec:
    ; RCX = Value to print in decimal
    push rbx
    push rdi
    push rsi
    sub rsp, 40

    mov rax, rcx
    lea rdi, [rsp + 32]
    mov byte [rdi], 0
    
    mov rbx, 10
.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    test rax, rax
    jnz .loop

    mov rcx, rdi
    call con_puts

    add rsp, 40
    pop rsi
    pop rdi
    pop rbx
    ret

section .data
align 4
fb_width dd 0
fb_height dd 0
fb_pitch dd 0
fb_base dq 0
fb_size dq 0

max_cols dd 0
max_rows dd 0

cursor_x dd 0
cursor_y dd 0

heartbeat_counter dd 0
