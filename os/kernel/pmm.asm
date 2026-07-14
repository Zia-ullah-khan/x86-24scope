; ==============================================================================
; x86-24scope OS - Physical Memory Manager (PMM)
; ==============================================================================
bits 64
default rel

section .text

global pmm_init
global pmm_alloc_page
global pmm_free_page
global pmm_get_free_pages

extern con_puts
extern con_put_hex
extern con_put_dec

; BootInfo offset offsets:
; 0:  Width (4 bytes)
; 4:  Height (4 bytes)
; 8:  PixelsPerScanLine (4 bytes)
; 16: FrameBufferBase (8 bytes)
; 24: FrameBufferSize (8 bytes)
; 32: MemoryMapBase (8 bytes)
; 40: MemoryMapSize (8 bytes)
; 48: DescriptorSize (8 bytes)

; UEFI Memory Type Constants:
; 7 = EfiConventionalMemory (usable RAM)

pmm_init:
    push rdi
    push rsi
    push rbx
    push r12
    push r13

    mov r12, rcx                    ; Save BootInfo pointer

    ; 1. Mark entire bitmap as used (all bits = 1)
    lea rdi, [pmm_bitmap]
    mov rcx, BITMAP_SIZE_WORDS
    mov rax, 0xFFFFFFFFFFFFFFFF
    rep stosq

    ; 2. Parse memory map to free conventional memory
    mov rsi, [r12 + 32]             ; rsi = MemoryMapBase
    mov rbx, [r12 + 40]             ; rbx = MemoryMapSize
    mov r13, [r12 + 48]             ; r13 = DescriptorSize
    
    xor r8, r8                      ; r8 = offset in memory map

.parse_loop:
    cmp r8, rbx
    jae .parse_done

    lea rax, [rsi + r8]             ; rax = pointer to descriptor
    
    ; Descriptor fields:
    ; offset 0:  Type (uint32)
    ; offset 8:  PhysicalStart (uint64)
    ; offset 16: VirtualStart (uint64)
    ; offset 24: NumberOfPages (uint64)
    ; offset 32: Attribute (uint64)

    mov ecx, [rax]                  ; Type
    cmp ecx, 7                      ; EfiConventionalMemory
    jne .next_descriptor

    ; Usable RAM region found
    mov rdx, [rax + 8]              ; PhysicalStart
    mov r9, [rax + 24]              ; NumberOfPages

    ; Free pages in this region
    call pmm_free_region

.next_descriptor:
    add r8, r13
    jmp .parse_loop

.parse_done:
    ; 3. Protect kernel memory region (0x0 to 0x2000000 - first 32MB)
    ; This covers UEFI structures, kernel code/data/bss/stack, and GDT/IDT.
    xor rcx, rcx                    ; Start address = 0
    mov rdx, 0x2000                 ; 0x2000 pages = 32MB
    call pmm_reserve_region

    ; 4. Protect the RAM disk buffer passed from the bootloader.
    ; ConventionalMemory descriptors still include those pages, so without
    ; this reserve VMM page-table allocations overwrite the disk image with zeros.
    mov rcx, [r12 + 64]             ; DiskBufferBase
    mov rax, [r12 + 72]             ; DiskBufferSize
    test rcx, rcx
    jz .stats
    test rax, rax
    jz .stats
    add rax, 4095
    shr rax, 12                     ; page count
    mov rdx, rax
    call pmm_reserve_region

.stats:
    ; Calculate and print statistics
    call pmm_recalculate_stats

    pop r13
    pop r12
    pop rbx
    pop rsi
    pop rdi
    ret

; Free a physical memory region
; RDX = Start physical address
; R9 = Number of pages
pmm_free_region:
    push rdi
    push rsi
    push rbx

    shr rdx, 12                     ; Page index = Address / 4096
    mov rcx, r9                     ; Page count

.loop:
    test rcx, rcx
    jz .done

    ; Clear bit in bitmap: index in rdx
    mov rax, rdx
    shr rax, 6                      ; Word index = page / 64
    mov rbx, rdx
    and rbx, 63                     ; Bit index = page % 64
    
    lea rsi, [pmm_bitmap]
    mov r10, [rsi + rax * 8]
    btr r10, rbx                    ; Bit Test and Reset (clears bit to 0)
    mov [rsi + rax * 8], r10

    inc rdx
    dec rcx
    jmp .loop

.done:
    pop rbx
    pop rsi
    pop rdi
    ret

; Reserve a physical memory region (mark as allocated)
; RCX = Start physical address
; RDX = Number of pages
pmm_reserve_region:
    push rdi
    push rsi
    push rbx

    shr rcx, 12                     ; Page index
    mov r8, rdx                     ; Page count

.loop:
    test r8, r8
    jz .done

    ; Set bit in bitmap: index in rcx
    mov rax, rcx
    shr rax, 6                      ; Word index
    mov rbx, rcx
    and rbx, 63                     ; Bit index
    
    lea rsi, [pmm_bitmap]
    mov r10, [rsi + rax * 8]
    bts r10, rbx                    ; Bit Test and Set (sets bit to 1)
    mov [rsi + rax * 8], r10

    inc rcx
    dec r8
    jmp .loop

.done:
    pop rbx
    pop rsi
    pop rdi
    ret

; Allocate 1 page of physical memory (4KB)
; Returns physical address in RAX, or 0 if out of memory
pmm_alloc_page:
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi

    lea rdi, [pmm_bitmap]
    xor rcx, rcx                    ; Word index

.find_word:
    cmp rcx, BITMAP_SIZE_WORDS
    jae .oom

    mov rax, [rdi + rcx * 8]
    cmp rax, 0xFFFFFFFFFFFFFFFF    ; All bits set? (All pages allocated)
    je .next_word

    ; Found a word with at least one free page (0 bit)
    xor rdx, rdx                    ; Bit index

.find_bit:
    bt rax, rdx
    jnc .found                      ; If bit is 0, it's free!
    inc rdx
    cmp rdx, 64
    jl .find_bit

.next_word:
    inc rcx
    jmp .find_word

.found:
    ; Set the bit to allocate it
    mov rax, [rdi + rcx * 8]
    bts rax, rdx
    mov [rdi + rcx * 8], rax

    ; Calculate physical address: (word_index * 64 + bit_index) * 4096
    mov rax, rcx
    shl rax, 6                      ; rax = word_index * 64
    add rax, rdx                    ; rax = page_index
    shl rax, 12                     ; rax = physical address (page_index * 4096)

    ; Update stats
    lock dec qword [free_pages_count]

    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

.oom:
    xor rax, rax                    ; Return NULL
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

; Free a previously allocated physical page
; RCX = Physical address of the page
pmm_free_page:
    push rbx
    push rsi

    shr rcx, 12                     ; Page index
    mov rax, rcx
    shr rax, 6                      ; Word index
    and rcx, 63                     ; Bit index

    lea rsi, [pmm_bitmap]
    mov r11, [rsi + rax * 8]
    btr r11, rcx
    mov [rsi + rax * 8], r11

    ; Update stats
    lock inc qword [free_pages_count]

    pop rsi
    pop rbx
    ret

; Recalculate statistics (used once during init)
pmm_recalculate_stats:
    push rdi
    push rsi
    push rbx

    xor rax, rax                    ; Free pages counter
    lea rdi, [pmm_bitmap]
    xor rcx, rcx                    ; Word index

.word_loop:
    cmp rcx, BITMAP_SIZE_WORDS
    jae .done

    mov rbx, [rdi + rcx * 8]
    not rbx                         ; Flip bits (free pages become 1)

    ; Count set bits manually (popcnt faults on CPUs without SSE4.2,
    ; e.g. QEMU's default qemu64 model)
.count_bits:
    test rbx, rbx
    jz .count_done
    lea rdx, [rbx - 1]
    and rbx, rdx                    ; Clear lowest set bit
    inc rax
    jmp .count_bits
.count_done:

    inc rcx
    jmp .word_loop

.done:
    mov [free_pages_count], rax
    
    ; Total conventional memory tracked
    mov rsi, BITMAP_SIZE_WORDS
    shl rsi, 6                      ; Total pages = words * 64
    mov [total_pages_count], rsi

    pop rbx
    pop rsi
    pop rdi
    ret

pmm_get_free_pages:
    mov rax, [free_pages_count]
    ret

; Bitmap can track up to 64GB of memory
; 64GB / 4KB = 16,777,216 pages
; 16,777,216 bits = 2,097,152 bytes = 2MB bitmap
; 2MB / 8 bytes = 262,144 quadwords
BITMAP_SIZE_BYTES equ 2097152
BITMAP_SIZE_WORDS equ 262144

section .data
align 8
free_pages_count dq 0
total_pages_count dq 0

section .bss
align 4096
pmm_bitmap:
    resb BITMAP_SIZE_BYTES
