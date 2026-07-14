; ==============================================================================
; x86-24scope OS - Disk / RAM Block Layer
; ==============================================================================
bits 64
default rel

section .text

global disk_init
global disk_read_sectors
global disk_get_base
global disk_get_size

disk_init:
    ; RCX points to BootInfo
    ; Offset 64: disk_ram_base (8 bytes)
    ; Offset 72: disk_ram_size (8 bytes)
    mov rax, [rcx + 64]
    mov [disk_base], rax
    mov rax, [rcx + 72]
    mov [disk_size], rax
    ret

disk_get_base:
    mov rax, [disk_base]
    ret

disk_get_size:
    mov rax, [disk_size]
    ret

; Bounds-checked sector read from the RAM disk image
disk_read_sectors:
    ; RCX = LBA (Logical Block Address, sector index)
    ; RDX = Sector Count
    ; R8  = Destination Buffer Address
    push rsi
    push rdi
    push rbx
    push rcx
    push rdx

    mov rsi, [disk_base]
    test rsi, rsi
    jz .error

    mov rax, rcx
    shl rax, 9                      ; byte offset
    mov rbx, [disk_size]
    cmp rax, rbx
    jae .error

    ; Ensure offset + count*512 fits
    mov rdi, rdx
    shl rdi, 9
    add rdi, rax
    cmp rdi, rbx
    ja .error

    add rsi, rax
    mov rcx, rdx
    shl rcx, 9
    mov rdi, r8
    rep movsb

    mov rax, 1
    jmp .done

.error:
    xor rax, rax

.done:
    pop rdx
    pop rcx
    pop rbx
    pop rdi
    pop rsi
    ret

section .data
align 8
disk_base dq 0
disk_size dq 0
