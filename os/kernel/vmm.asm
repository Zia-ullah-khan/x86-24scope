; ==============================================================================
; x86-24scope OS - Virtual Memory Manager (Paging)
; ==============================================================================
bits 64
default rel

section .text

global vmm_init
global vmm_map_page
extern pmm_alloc_page

; BootInfo structure offset:
; 16: FrameBufferBase (8 bytes)
; 24: FrameBufferSize (8 bytes)

; Page tables must be 4KiB-aligned physical addresses for MOV CR3.
; GoLink does not preserve NASM BSS align 4096 across objects, so allocate
; them from the PMM at runtime instead of using static .bss storage.

vmm_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13

    mov r12, rcx                    ; Save BootInfo pointer

    ; 1. Allocate PML4 (4KiB-aligned via PMM)
    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [kernel_pml4_ptr], rax
    mov rdi, rax
    mov rcx, 512
    xor rax, rax
    rep stosq

    ; 2. Allocate PDPT
    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [kernel_pdpt_ptr], rax
    mov rdi, rax
    mov rcx, 512
    xor rax, rax
    rep stosq

    ; Link PML4[0] -> PDPT
    mov rax, [kernel_pdpt_ptr]
    or rax, 0x03                    ; Present + Read/Write
    mov rdi, [kernel_pml4_ptr]
    mov [rdi], rax

    ; 3. Allocate 4 Page Directories and link PDPT[0..3]
    xor rbx, rbx                    ; PD index 0..3
.link_pdpt:
    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov rdi, rax
    mov rcx, 512
    push rax
    xor rax, rax
    rep stosq
    pop rax

    lea rdi, [kernel_pd_ptrs]
    mov [rdi + rbx * 8], rax

    mov r10, rax
    or r10, 0x03
    mov rdi, [kernel_pdpt_ptr]
    mov [rdi + rbx * 8], r10

    inc rbx
    cmp rbx, 4
    jb .link_pdpt

    ; 4. Identity map first 4GB with 2MB large pages
    xor rdx, rdx                    ; Current physical address
    xor rbx, rbx                    ; Global PD entry index 0..2047

.map_4gb:
    mov rax, rbx
    shr rax, 9                      ; PD table index (0..3)
    lea rdi, [kernel_pd_ptrs]
    mov rdi, [rdi + rax * 8]

    mov rax, rbx
    and rax, 0x1FF                  ; Entry within that PD
    mov r8, rdx
    or r8, 0x83                     ; Present + RW + Page Size
    mov [rdi + rax * 8], r8

    add rdx, 0x200000               ; Next 2MB
    inc rbx
    cmp rbx, 2048
    jb .map_4gb

    ; 5. Map Framebuffer if it is above 4GB
    test r12, r12
    jz .load_cr3
    mov rbx, [r12 + 16]             ; FrameBufferBase
    mov rsi, [r12 + 24]             ; FrameBufferSize
    test rbx, rbx
    jz .load_cr3
    mov r11, 0x100000000
    cmp rbx, r11
    jb .load_cr3

    mov r13, rbx
    add r13, rsi
    and rbx, ~0x1FFFFF
    add r13, 0x1FFFFF
    and r13, ~0x1FFFFF

.map_fb_loop:
    cmp rbx, r13
    jae .load_cr3

    mov rcx, rbx
    mov rdx, rbx
    call vmm_map_large_page

    add rbx, 0x200000
    jmp .map_fb_loop

.load_cr3:
    ; 6. Load new page tables into CR3 (must be 4KiB-aligned)
    mov rax, [kernel_pml4_ptr]
    mov cr3, rax

.fail:
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

; Map a 2MB page (Internal helper)
; RCX = Virtual Address
; RDX = Physical Address
vmm_map_large_page:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi

    mov r8, rcx
    shr r8, 39
    and r8, 0x1FF                   ; PML4 Index

    mov r9, rcx
    shr r9, 30
    and r9, 0x1FF                   ; PDPT Index

    mov r10, rcx
    shr r10, 21
    and r10, 0x1FF                  ; PD Index

    mov rdi, [kernel_pml4_ptr]
    test rdi, rdi
    jz .fail
    mov rax, [rdi + r8 * 8]
    test rax, 0x01
    jnz .pml4_present

    call pmm_alloc_page
    test rax, rax
    jz .fail
    push rdi
    mov rdi, rax
    push rcx
    mov rcx, 512
    xor r11, r11
    rep stosq
    pop rcx
    pop rdi
    mov r11, rax
    or r11, 0x03
    mov [rdi + r8 * 8], r11
    mov rax, r11

.pml4_present:
    and rax, ~0xFFF
    mov rdi, rax

    mov rax, [rdi + r9 * 8]
    test rax, 0x01
    jnz .pdpt_present

    call pmm_alloc_page
    test rax, rax
    jz .fail
    push rdi
    mov rdi, rax
    push rcx
    mov rcx, 512
    xor r11, r11
    rep stosq
    pop rcx
    pop rdi
    mov r11, rax
    or r11, 0x03
    mov [rdi + r9 * 8], r11
    mov rax, r11

.pdpt_present:
    and rax, ~0xFFF
    mov rdi, rax

    mov rax, rdx
    or rax, 0x83
    mov [rdi + r10 * 8], rax

    invlpg [rcx]

.fail:
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

; Map a 4KB page (Dynamic API)
; RCX = Virtual Address
; RDX = Physical Address
vmm_map_page:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12

    mov r8, rcx
    shr r8, 39
    and r8, 0x1FF

    mov r9, rcx
    shr r9, 30
    and r9, 0x1FF

    mov r10, rcx
    shr r10, 21
    and r10, 0x1FF

    mov r11, rcx
    shr r11, 12
    and r11, 0x1FF

    mov rdi, [kernel_pml4_ptr]
    test rdi, rdi
    jz .fail
    mov rax, [rdi + r8 * 8]
    test rax, 0x01
    jnz .pml4_present

    call pmm_alloc_page
    test rax, rax
    jz .fail
    push rdi
    mov rdi, rax
    push rcx
    mov rcx, 512
    xor r12, r12
    rep stosq
    pop rcx
    pop rdi
    mov r12, rax
    or r12, 0x03
    mov [rdi + r8 * 8], r12
    mov rax, r12

.pml4_present:
    and rax, ~0xFFF
    mov rdi, rax

    mov rax, [rdi + r9 * 8]
    test rax, 0x01
    jnz .pdpt_present

    call pmm_alloc_page
    test rax, rax
    jz .fail
    push rdi
    mov rdi, rax
    push rcx
    mov rcx, 512
    xor r12, r12
    rep stosq
    pop rcx
    pop rdi
    mov r12, rax
    or r12, 0x03
    mov [rdi + r9 * 8], r12
    mov rax, r12

.pdpt_present:
    and rax, ~0xFFF
    mov rdi, rax

    mov rax, [rdi + r10 * 8]
    test rax, 0x01
    jnz .pd_present

    ; Existing large-page mappings must not be overwritten with a PT pointer
    test rax, 0x80
    jnz .fail

    call pmm_alloc_page
    test rax, rax
    jz .fail
    push rdi
    mov rdi, rax
    push rcx
    mov rcx, 512
    xor r12, r12
    rep stosq
    pop rcx
    pop rdi
    mov r12, rax
    or r12, 0x03
    mov [rdi + r10 * 8], r12
    mov rax, r12

.pd_present:
    and rax, ~0xFFF
    mov rdi, rax

    mov rax, rdx
    or rax, 0x03
    mov [rdi + r11 * 8], rax

    invlpg [rcx]

.fail:
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

section .data
align 8
kernel_pml4_ptr dq 0
kernel_pdpt_ptr dq 0
kernel_pd_ptrs  times 4 dq 0
