; ==============================================================================
; x86-24scope OS - FAT16/FAT32 Filesystem Driver (Read-Only with LFN support)
; ==============================================================================
bits 64
default rel

section .text

global fat32_init
global fat32_open
global fat32_read

extern disk_read_sectors
extern disk_get_base
extern disk_get_size
extern con_puts
extern con_put_hex
extern con_newline
extern serial_puts
extern serial_put_hex

; FAT Directory Entry offsets
DIR_NAME            equ 0
DIR_ATTR            equ 11
DIR_FST_CLUS_HI     equ 20
DIR_FST_CLUS_LO     equ 26
DIR_FILE_SIZE       equ 28

; LFN Entry offsets
LFN_SEQ             equ 0
LFN_NAME1           equ 1
LFN_ATTR            equ 11
LFN_NAME2           equ 14
LFN_NAME3           equ 28

; Sentinel: FAT16 fixed root directory (not a cluster chain)
FAT16_ROOT_SENTINEL equ 0xFFFFFFFF

fat32_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 512

    call disk_get_base
    test rax, rax
    jz .error
    mov r12, rax                    ; r12 = RAM disk base

    call disk_get_size
    shr rax, 9                      ; sector count (512-byte)
    test rax, rax
    jz .error
    mov rbx, rax
    cmp rbx, 4096
    jbe .scan_cap
    mov rbx, 4096
.scan_cap:
    xor ecx, ecx                    ; candidate LBA in ecx

.scan_loop:
    cmp rcx, rbx
    jae .error

    mov rax, rcx
    shl rax, 9
    lea rdx, [r12 + rax]            ; sector pointer

    cmp word [rdx + 510], 0xAA55
    jne .scan_next
    cmp word [rdx + 11], 512
    jne .scan_next

    mov eax, [rdx + 54]
    cmp eax, 'FAT1'
    je .scan_hit
    cmp eax, 'FAT3'
    je .scan_hit

    cmp word [rdx + 14], 0
    je .scan_next
    cmp byte [rdx + 16], 0
    je .scan_next
    cmp byte [rdx + 13], 0
    je .scan_next
    jmp .scan_hit

.scan_next:
    inc ecx
    jmp .scan_loop

.scan_hit:
    mov [partition_lba], ecx

    ; Copy BPB sector onto stack for stable parsing
    mov rsi, rdx
    mov rdi, rsp
    push rcx
    mov rcx, 64                     ; 512 bytes = 64 qwords
    rep movsq
    pop rcx

    ; Bytes per sector (BPB offset 11)
    movzx eax, word [rsp + 11]
    test eax, eax
    jz .error
    mov [bytes_per_sector], eax

    ; Sectors per cluster (offset 13)
    movzx eax, byte [rsp + 13]
    test eax, eax
    jz .error
    mov [sectors_per_cluster], eax

    ; Reserved sectors (offset 14)
    movzx eax, word [rsp + 14]
    mov [reserved_sectors], eax

    ; Number of FATs (offset 16)
    movzx eax, byte [rsp + 16]
    mov [num_fats], eax

    ; Root entry count (offset 17) — non-zero means FAT12/FAT16
    movzx eax, word [rsp + 17]
    mov [root_dir_entries], eax

    ; Sectors per FAT: FAT16 uses 16-bit at offset 22; FAT32 uses 32-bit at 36
    movzx eax, word [rsp + 22]
    test eax, eax
    jnz .fat16

    mov eax, [rsp + 36]
    test eax, eax
    jz .error
    mov [sectors_per_fat], eax
    mov eax, [rsp + 44]
    mov [root_cluster], eax
    mov dword [is_fat16], 0
    jmp .calc_layout

.fat16:
    mov [sectors_per_fat], eax
    mov dword [is_fat16], 1
    mov dword [root_cluster], FAT16_ROOT_SENTINEL

.calc_layout:
    ; All LBAs below are relative to the FAT volume start, then biased by partition_lba
    mov eax, [reserved_sectors]
    add eax, [partition_lba]
    mov [fat_start_sector], eax

    mov eax, [reserved_sectors]
    mov ecx, [num_fats]
    imul ecx, [sectors_per_fat]
    add eax, ecx
    add eax, [partition_lba]
    mov [root_start_sector], eax

    ; root_dir_sectors = ceil(root_dir_entries * 32 / bytes_per_sector)
    mov eax, [root_dir_entries]
    shl eax, 5
    mov ecx, [bytes_per_sector]
    add eax, ecx
    dec eax
    xor edx, edx
    div ecx
    mov [root_dir_sectors], eax

    ; data_start = root_start + root_dir_sectors
    mov eax, [root_start_sector]
    add eax, [root_dir_sectors]
    mov [data_start_sector], eax

    cmp dword [is_fat16], 0
    jne .msg16
    lea rcx, [msg_fat32_init]
    jmp .print
.msg16:
    lea rcx, [msg_fat16_init]
.print:
    call con_puts
    cmp dword [is_fat16], 0
    jne .ser16
    lea rcx, [msg_fat32_init]
    jmp .ser
.ser16:
    lea rcx, [msg_fat16_init]
.ser:
    call serial_puts

    mov rax, 1
    jmp .done

.error:
    lea rcx, [msg_fat_err]
    call con_puts
    lea rcx, [msg_fat_err]
    call serial_puts
    xor rax, rax

.done:
    add rsp, 512
    pop r12
    pop rbx
    pop rbp
    ret

; Walk FAT to get next cluster in chain
; RCX = Current Cluster
; Returns RAX = Next Cluster (or 0x0FFFFFFF for End of Chain)
fat32_get_next_cluster:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 512

    mov r12, rcx                    ; cluster

    ; FAT16 fixed root has no chain
    cmp r12d, FAT16_ROOT_SENTINEL
    je .eoc

    mov eax, [bytes_per_sector]
    test eax, eax
    jz .eoc
    mov r13d, eax                   ; r13 = bytes per sector

    ; Byte offset in FAT: cluster * 2 (FAT16) or cluster * 4 (FAT32)
    mov rax, r12
    cmp dword [is_fat16], 0
    jne .off16
    shl rax, 2
    jmp .div_sec
.off16:
    shl rax, 1

.div_sec:
    xor rdx, rdx
    mov rcx, r13
    div rcx                         ; rax = sector offset, rdx = byte offset
    mov ebx, edx                    ; ebx = offset within sector

    add eax, [fat_start_sector]

    mov ecx, eax
    mov rdx, 1
    mov r8, rsp
    call disk_read_sectors
    test rax, rax
    jz .eoc

    cmp dword [is_fat16], 0
    jne .read16
    mov eax, [rsp + rbx]
    and eax, 0x0FFFFFFF
    cmp eax, 0x0FFFFFF8
    jae .eoc
    jmp .done

.read16:
    movzx eax, word [rsp + rbx]
    cmp eax, 0xFFF8
    jae .eoc
    jmp .done

.eoc:
    mov eax, 0x0FFFFFFF

.done:
    add rsp, 512
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; Convert cluster index to LBA sector
; RCX = Cluster (must be a real data cluster, not FAT16 root sentinel)
; Returns RAX = LBA Sector
fat32_cluster_to_lba:
    sub rcx, 2
    mov eax, [sectors_per_cluster]
    imul rax, rcx
    add rax, [data_start_sector]
    ret

; Traverse directory structures to open a file by path
; RCX = Null-terminated ASCII path string
; Returns RAX = Start Cluster, RDX = File Size (or 0 on not found)
fat32_open:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 4096

    mov r12, rcx

    cmp byte [r12], '/'
    je .skip_slash
    cmp byte [r12], '\'
    jne .start_traverse
.skip_slash:
    inc r12

.start_traverse:
    mov r13d, [root_cluster]        ; current dir cluster (or FAT16 root sentinel)

.next_component:
    lea rdi, [comp_name]
    xor ecx, ecx

.copy_comp:
    mov al, [r12]
    test al, al
    jz .comp_done
    cmp al, '/'
    je .comp_done
    cmp al, '\'
    je .comp_done
    cmp ecx, 255
    jae .comp_done
    mov [rdi + rcx], al
    inc rcx
    inc r12
    jmp .copy_comp

.comp_done:
    mov byte [comp_name + rcx], 0
    test ecx, ecx
    jz .found_target

    mov al, [r12]
    cmp al, '/'
    je .skip_slash2
    cmp al, '\'
    je .skip_slash2
    jmp .search_dir
.skip_slash2:
    inc r12

.search_dir:
    lea rdi, [lfn_name]
    xor eax, eax
    mov rcx, 512
    rep stosb

    ; FAT16 root: scan fixed root region
    cmp r13d, FAT16_ROOT_SENTINEL
    jne .read_dir_cluster

    mov r14d, [root_start_sector]
    mov r15d, [root_dir_sectors]
    xor ebx, ebx
    jmp .read_sector_loop

.read_dir_cluster:
    mov ecx, r13d
    call fat32_cluster_to_lba
    mov r14, rax
    mov r15d, [sectors_per_cluster]
    xor ebx, ebx

.read_sector_loop:
    cmp ebx, r15d
    jae .next_cluster

    lea rcx, [r14 + rbx]
    mov rdx, 1
    mov r8, rsp
    call disk_read_sectors
    test rax, rax
    jz .not_found

    xor esi, esi

.entry_loop:
    cmp esi, 512
    jae .next_sector

    ; Use r8 as entry pointer (do not clobber rbp)
    lea r8, [rsp + rsi]

    movzx eax, byte [r8 + DIR_NAME]
    test al, al
    jz .not_found
    cmp al, 0xE5
    je .next_entry

    mov al, [r8 + DIR_ATTR]
    cmp al, 0x0F
    je .handle_lfn

    cmp byte [lfn_name], 0
    jz .check_short_name

    push r8
    lea rcx, [lfn_name]
    lea rdx, [comp_name]
    call str_case_compare
    pop r8
    test rax, rax
    jnz .match_found
    ; LFN present but did not match — still try the 8.3 name
    jmp .check_short_name

.check_short_name:
    push r8
    lea rcx, [r8 + DIR_NAME]
    lea rdx, [short_name_buf]
    call format_short_name
    lea rcx, [short_name_buf]
    lea rdx, [comp_name]
    call str_case_compare
    pop r8
    test rax, rax
    jnz .match_found

.clear_lfn:
    push rdi
    lea rdi, [lfn_name]
    xor rax, rax
    mov rcx, 512
    rep stosb
    pop rdi
    jmp .next_entry

.handle_lfn:
    movzx edx, byte [r8 + LFN_SEQ]
    mov eax, edx
    and eax, 0x1F
    test eax, eax
    jz .next_entry                  ; invalid sequence 0
    dec eax
    imul eax, 13
    cmp eax, 512 - 13
    ja .next_entry

    lea rdi, [lfn_name]
    add rdi, rax

    push r8
    lea r8, [r8 + LFN_NAME1]
    mov ecx, 5
    call copy_utf16_to_ascii
    pop r8

    push r8
    lea r8, [r8 + LFN_NAME2]
    mov ecx, 6
    call copy_utf16_to_ascii
    pop r8

    push r8
    lea r8, [r8 + LFN_NAME3]
    mov ecx, 2
    call copy_utf16_to_ascii
    pop r8
    jmp .next_entry

.match_found:
    movzx eax, word [r8 + DIR_FST_CLUS_HI]
    shl eax, 16
    movzx edx, word [r8 + DIR_FST_CLUS_LO]
    or eax, edx
    mov r13d, eax

    mov al, [r8 + DIR_ATTR]
    and al, 0x10
    jnz .is_dir

    mov edx, [r8 + DIR_FILE_SIZE]
    mov eax, r13d
    jmp .found_target

.is_dir:
    ; Subdirectory is always a cluster chain (even on FAT16)
    test r13d, r13d
    jz .not_found
    jmp .next_component

.next_entry:
    add esi, 32
    jmp .entry_loop

.next_sector:
    inc ebx
    jmp .read_sector_loop

.next_cluster:
    cmp r13d, FAT16_ROOT_SENTINEL
    je .not_found                   ; fixed root exhausted

    mov ecx, r13d
    call fat32_get_next_cluster
    mov r13d, eax
    cmp r13d, 0x0FFFFFFF
    jae .not_found
    cmp r13d, 2
    jae .read_dir_cluster

.not_found:
    xor rax, rax
    xor rdx, rdx
    jmp .done

.found_target:
.done:
    add rsp, 4096
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; Read file data from a cluster chain
; RCX = Start Cluster
; RDX = Size in bytes
; R8  = Destination Buffer
; Returns RAX = Bytes read
fat32_read:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov [rsp], rdx                  ; original size

    mov r12d, ecx
    mov r13, rdx
    mov r14, r8

    mov eax, [sectors_per_cluster]
    imul eax, [bytes_per_sector]
    test eax, eax
    jz .error
    mov r15, rax                    ; cluster size in bytes

.cluster_loop:
    test r13, r13
    jz .success
    cmp r12d, 0x0FFFFFFF
    jae .success
    cmp r12d, 2
    jb .success

    mov ecx, r12d
    call fat32_cluster_to_lba

    mov rdx, r15
    cmp r13, r15
    jae .read_full
    mov rdx, r13
    add rdx, 511
    shr rdx, 9
.read_full:
    cmp rdx, r15
    jne .read_partial_call
    mov edx, [sectors_per_cluster]

.read_partial_call:
    mov rcx, rax
    mov r8, r14
    push rdx
    call disk_read_sectors
    pop rdx
    test rax, rax
    jz .error

    cmp r13, r15
    jae .sub_full
    add r14, r13
    xor r13, r13
    jmp .success

.sub_full:
    sub r13, r15
    add r14, r15
    mov ecx, r12d
    call fat32_get_next_cluster
    mov r12d, eax
    jmp .cluster_loop

.success:
    mov rax, [rsp]
    sub rax, r13
    jmp .done

.error:
    xor rax, rax

.done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; RCX = str1, RDX = str2 → RAX = 1 if equal (case-insensitive)
str_case_compare:
    push rbx
    push rsi
    push rdi
    mov rsi, rcx
    mov rdi, rdx

.loop:
    lodsb
    mov bl, [rdi]
    inc rdi

    cmp al, 'a'
    jb .check_bl
    cmp al, 'z'
    ja .check_bl
    sub al, 32
.check_bl:
    cmp bl, 'a'
    jb .compare
    cmp bl, 'z'
    ja .compare
    sub bl, 32
.compare:
    cmp al, bl
    jne .mismatch
    test al, al
    jnz .loop
    mov rax, 1
    jmp .done
.mismatch:
    xor rax, rax
.done:
    pop rdi
    pop rsi
    pop rbx
    ret

; R8 = UTF-16 src, RCX = count, RDI = dest ASCII (advanced on return)
copy_utf16_to_ascii:
    xor rdx, rdx
.loop:
    cmp rdx, rcx
    jae .done
    movzx eax, word [r8 + rdx * 2]
    test ax, ax
    jz .done
    cmp ax, 0xFFFF                  ; LFN padding — end of name
    je .done
    cmp ax, 0x7F
    ja .placeholder
    mov [rdi + rdx], al
    jmp .next
.placeholder:
    mov byte [rdi + rdx], '?'
.next:
    inc rdx
    jmp .loop
.done:
    add rdi, rdx
    ret

; RCX = 11-byte short name, RDX = destination buffer
format_short_name:
    push rsi
    push rdi
    push rbx
    mov rsi, rcx
    mov rdi, rdx
    xor ebx, ebx
.name_loop:
    cmp ebx, 8
    jae .check_ext
    mov al, [rsi + rbx]
    cmp al, ' '
    je .name_space
    mov [rdi], al
    inc rdi
.name_space:
    inc ebx
    jmp .name_loop
.check_ext:
    mov al, [rsi + 8]
    cmp al, ' '
    je .done_ext
    mov byte [rdi], '.'
    inc rdi
    xor ebx, ebx
.ext_loop:
    cmp ebx, 3
    jae .done_ext
    mov al, [rsi + 8 + rbx]
    cmp al, ' '
    je .ext_space
    mov [rdi], al
    inc rdi
.ext_space:
    inc ebx
    jmp .ext_loop
.done_ext:
    mov byte [rdi], 0
    pop rbx
    pop rdi
    pop rsi
    ret

section .data
align 4
bytes_per_sector    dd 512
sectors_per_cluster dd 8
reserved_sectors    dd 32
num_fats            dd 2
sectors_per_fat     dd 0
root_dir_entries    dd 0
root_dir_sectors    dd 0
root_cluster        dd 2
fat_start_sector    dd 0
root_start_sector   dd 0
data_start_sector   dd 0
partition_lba       dd 0
is_fat16            dd 0

msg_fat16_init db "FAT16: Mounted boot partition successfully.", 13, 10, 0
msg_fat32_init db "FAT32: Mounted boot partition successfully.", 13, 10, 0
msg_fat_err    db "FAT: ERROR - Failed to mount boot partition!", 13, 10, 0

section .bss
comp_name resb 256
lfn_name resb 512
short_name_buf resb 16
