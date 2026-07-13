; ==============================================================================
; x86-24scope OS - Disk / RAM Block Layer
; ==============================================================================
bits 64
default rel

section .text

global disk_init
global disk_read_sectors

disk_init:
    ; RCX points to BootInfo
    ; Offset 64: disk_ram_base (8 bytes)
    ; Offset 72: disk_ram_size (8 bytes)
    mov rax, [rcx + 64]
    mov [disk_base], rax
    mov rax, [rcx + 72]
    mov [disk_size], rax
    ret

disk_read_sectors:
    ; RCX = LBA (Logical Block Address, sector index)
    ; RDX = Sector Count
    ; R8  = Destination Buffer Address
    push rsi
    push rdi
    push rcx
    push rdx

    mov rsi, [disk_base]
    test rsi, rsi
    jz .error

    ; Calculate source offset: base + LBA * 512
    shl rcx, 9                      ; LBA * 512
    add rsi, rcx

    ; Calculate size: count * 512
    mov rcx, rdx
    shl rcx, 9                      ; count * 512

    mov rdi, r8                     ; destination
    
    ; Copy memory
    rep movsb

    mov rax, 1                      ; Success
    jmp .done

.error:
    xor rax, rax                    ; Failure

.done:
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    ret

section .data
align 8
disk_base dq 0
disk_size dq 0
