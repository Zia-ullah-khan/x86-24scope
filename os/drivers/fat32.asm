; ==============================================================================
; x86-24scope OS - FAT32 Filesystem Driver (Read-Only with LFN support)
; ==============================================================================
bits 64
default rel

section .text

global fat32_init
global fat32_open
global fat32_read

extern disk_read_sectors
extern con_puts
extern con_put_hex
extern con_newline
extern serial_puts
extern serial_put_hex

; FAT32 Directory Entry offsets
DIR_NAME            equ 0
DIR_ATTR            equ 11
DIR_FST_CLUS_HI     equ 20
DIR_FST_CLUS_LO     equ 26
DIR_FILE_SIZE       equ 28

; LFN Entry offsets
LFN_SEQ             equ 0
LFN_NAME1           equ 1           ; 5 characters (10 bytes)
LFN_ATTR            equ 11          ; Always 0x0F
LFN_NAME2           equ 14          ; 6 characters (12 bytes)
LFN_NAME3           equ 28          ; 2 characters (4 bytes)

fat32_init:
    push rbp
    mov rbp, rsp
    sub rsp, 512                    ; Allocate 512-byte sector buffer

    ; 1. Read Boot Sector (LBA 0)
    xor rcx, rcx                    ; LBA = 0
    mov rdx, 1                      ; Count = 1
    mov r8, rsp                     ; Destination = stack buffer
    call disk_read_sectors
    test rax, rax
    jz .error

    ; 2. Parse BPB (BIOS Parameter Block)
    movzx eax, word [rsp + 11]      ; Bytes Per Sector
    mov [bytes_per_sector], eax
    
    movzx eax, byte [rsp + 13]      ; Sectors Per Cluster
    mov [sectors_per_cluster], eax

    movzx eax, word [rsp + 14]      ; Reserved Sectors Count
    mov [reserved_sectors], eax

    movzx eax, byte [rsp + 16]      ; Number of FATs
    mov [num_fats], eax

    mov eax, [rsp + 36]             ; Sectors Per FAT (FAT32)
    mov [sectors_per_fat], eax

    mov eax, [rsp + 44]             ; Root Cluster
    mov [root_cluster], eax

    ; 3. Calculate Sector Locations
    ; fat_start_sector = reserved_sectors
    movzx eax, word [reserved_sectors]
    mov [fat_start_sector], eax

    ; data_start_sector = reserved_sectors + num_fats * sectors_per_fat
    movzx ecx, byte [num_fats]
    imul ecx, [sectors_per_fat]
    add eax, ecx
    mov [data_start_sector], eax

    ; Print success
    lea rcx, [msg_fat_init]
    call con_puts
    lea rcx, [msg_fat_init]
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
    pop rbp
    ret

; Walk FAT to get next cluster in chain
; RCX = Current Cluster
; Returns RAX = Next Cluster (or 0x0FFFFFFF for End of Chain)
fat32_get_next_cluster:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    sub rsp, 512                    ; 512-byte sector buffer

    ; Offset in FAT = cluster * 4
    mov rax, rcx
    shl rax, 2                      ; rax = cluster * 4
    
    ; Sector of FAT = fat_start_sector + (offset / bytes_per_sector)
    xor rdx, rdx
    mov ecx, [bytes_per_sector]
    div rcx                         ; rax = sector offset, rdx = byte offset
    
    add eax, [fat_start_sector]     ; Absolute LBA sector
    
    ; Read FAT sector
    mov ecx, eax                    ; LBA
    mov rdx, 1                      ; Count = 1
    mov r8, rsp                     ; Buffer
    push rdx
    push rbx
    call disk_read_sectors
    pop rbx
    pop rdx
    test rax, rax
    jz .err

    ; Extract 32-bit entry
    mov eax, [rsp + rdx]
    and eax, 0x0FFFFFFF             ; Mask top 4 bits

    jmp .done

.err:
    mov eax, 0x0FFFFFFF             ; Return End of Chain on error

.done:
    add rsp, 512
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; Convert cluster index to LBA sector
; RCX = Cluster
; Returns RAX = LBA Sector
fat32_cluster_to_lba:
    sub rcx, 2                      ; cluster - 2
    movzx eax, byte [sectors_per_cluster]
    imul rax, rcx                   ; (cluster - 2) * sectors_per_cluster
    add rax, [data_start_sector]    ; add data_start_sector
    ret

; Traverse directory structures to open a file by path
; RCX = Null-terminated ASCII path string (e.g. "/Plane Icons/737.png")
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
    sub rsp, 4096                   ; Allocate 4KB scratch sector buffer

    mov r12, rcx                    ; r12 = current path pointer
    
    ; Skip leading slash
    cmp byte [r12], '/'
    je .skip_slash
    cmp byte [r12], '\'
    jne .start_traverse
.skip_slash:
    inc r12

.start_traverse:
    mov r13d, [root_cluster]        ; r13d = current directory cluster

.next_component:
    ; Extract next path component (up to '/' or '\' or 0)
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
    mov byte [comp_name + rcx], 0   ; Null terminate
    test ecx, ecx
    jz .found_target                ; If component is empty, we reached target!

    ; Check if there is another slash following
    mov al, [r12]
    cmp al, '/'
    je .skip_slash2
    cmp al, '\'
    je .skip_slash2
    jmp .search_dir

.skip_slash2:
    inc r12                         ; Advance past slash

.search_dir:
    ; Search for comp_name in the directory starting at cluster r13d
    ; Clear LFN buffer
    lea rdi, [lfn_name]
    xor rax, rax
    mov rcx, 512
    rep stosb

.read_dir_cluster:
    ; Convert directory cluster to LBA
    mov ecx, r13d
    call fat32_cluster_to_lba
    mov r14, rax                    ; r14 = LBA start sector of cluster

    ; Read cluster sectors
    movzx r15d, byte [sectors_per_cluster]
    xor rbx, rbx                    ; rbx = sector index in cluster

.read_sector_loop:
    cmp ebx, r15d
    jae .next_cluster

    ; Read sector
    lea rcx, [r14 + rbx]            ; LBA
    mov rdx, 1                      ; Count
    mov r8, rsp                     ; Buffer (stack)
    call disk_read_sectors
    test rax, rax
    jz .not_found

    ; Parse entries in sector (512 / 32 = 16 entries)
    xor esi, esi                    ; esi = entry offset (0..511)

.entry_loop:
    cmp esi, 512
    jae .next_sector

    lea rbp, [rsp + rsi]            ; rbp = pointer to entry

    movzx eax, byte [rbp + DIR_NAME]
    test al, al
    jz .not_found                   ; 0x00 = end of directory
    cmp al, 0xE5
    je .next_entry                  ; 0xE5 = deleted entry

    ; Check if LFN entry (Attribute = 0x0F)
    mov al, [rbp + DIR_ATTR]
    cmp al, 0x0F
    je .handle_lfn

    ; It's a standard directory entry
    ; Compare with comp_name
    
    ; Check if we have an assembled LFN
    cmp byte [lfn_name], 0
    jz .check_short_name

    ; Compare LFN
    lea rcx, [lfn_name]
    lea rdx, [comp_name]
    call str_case_compare
    test rax, rax
    jnz .match_found
    jmp .clear_lfn

.check_short_name:
    ; Convert short name to clean string (e.g. "PLANE   DIR" -> "PLANE", or "737     PNG" -> "737.png")
    lea rcx, [rbp + DIR_NAME]
    lea rdx, [short_name_buf]
    call format_short_name

    lea rcx, [short_name_buf]
    lea rdx, [comp_name]
    call str_case_compare
    test rax, rax
    jnz .match_found

.clear_lfn:
    ; Clear LFN buffer
    push rdi
    lea rdi, [lfn_name]
    xor rax, rax
    mov rcx, 512
    rep stosb
    pop rdi
    jmp .next_entry

.handle_lfn:
    ; LFN entry
    movzx edx, byte [rbp + LFN_SEQ]
    and dl, 0x1F                    ; Mask sequence number (1..20)
    dec dl                          ; 0-based index
    imul edx, 13                    ; Offset in characters (13 chars per entry)

    ; Extract 13 characters from LFN entry (convert UTF-16 to ASCII)
    lea rdi, [lfn_name]
    add rdi, rdx                    ; Destination pointer

    ; Chars 1-5 (offset 1, 10 bytes)
    lea r8, [rbp + LFN_NAME1]
    mov ecx, 5
    call copy_utf16_to_ascii

    ; Chars 6-11 (offset 14, 12 bytes)
    lea r8, [rbp + LFN_NAME2]
    mov ecx, 6
    call copy_utf16_to_ascii

    ; Chars 12-13 (offset 28, 4 bytes)
    lea r8, [rbp + LFN_NAME3]
    mov ecx, 2
    call copy_utf16_to_ascii
    jmp .next_entry

.match_found:
    ; Get starting cluster of matched entry
    movzx eax, word [rbp + DIR_FST_CLUS_HI]
    shl eax, 16
    movzx dx, word [rbp + DIR_FST_CLUS_LO]
    or eax, edx                     ; eax = start cluster
    
    mov r13d, eax                   ; Save start cluster

    ; Check if it is a directory or file
    mov al, [rbp + DIR_ATTR]
    and al, 0x10                    ; Subdirectory flag
    jnz .is_dir

    ; It's a file!
    mov edx, [rbp + DIR_FILE_SIZE]  ; File size
    mov eax, r13d                   ; File start cluster
    jmp .found_target

.is_dir:
    ; It's a directory, continue to next path component
    jmp .next_component

.next_entry:
    add esi, 32
    jmp .entry_loop

.next_sector:
    inc ebx
    jmp .read_sector_loop

.next_cluster:
    ; Walk FAT to get next directory cluster
    mov ecx, r13d
    call fat32_get_next_cluster
    mov r13d, eax
    cmp r13d, 0x0FFFFFFF
    jae .not_found
    cmp r13d, 2
    jae .read_dir_cluster

.not_found:
    xor rax, rax                    ; File not found
    xor rdx, rdx
    jmp .done

.found_target:
    ; Returns cluster in RAX and size in RDX
    ; If file is 0 bytes, make sure size is correct
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

    mov r12d, ecx                   ; r12d = current cluster
    mov r13, rdx                    ; r13 = remaining size
    mov r14, r8                     ; r14 = current destination pointer
    
    ; Calculate cluster size in bytes
    movzx eax, byte [sectors_per_cluster]
    imul eax, [bytes_per_sector]
    mov r15, rax                    ; r15 = cluster size (bytes)

.cluster_loop:
    test r13, r13
    jz .success
    cmp r12d, 0x0FFFFFFF
    jae .success

    ; Convert cluster to LBA
    mov ecx, r12d
    call fat32_cluster_to_lba       ; RAX = LBA sector
    
    ; Determine how much to read
    mov rdx, r15                    ; Try to read full cluster
    cmp r13, r15
    jae .read_full

    ; Remaining size is less than a cluster. Read necessary sectors.
    mov rdx, r13
    add rdx, 511
    shr rdx, 9                      ; rdx = sectors count = (r13 + 511) / 512

.read_full:
    ; Read sectors
    mov rcx, rax                    ; LBA
    ; rdx is already sector count (for full cluster, rdx = sectors_per_cluster)
    cmp rdx, r15
    jne .read_partial_call
    
    movzx rdx, byte [sectors_per_cluster]

.read_partial_call:
    mov r8, r14                     ; destination
    push rdx
    call disk_read_sectors
    pop rdx
    test rax, rax
    jz .error

    ; Update pointers and counters
    cmp r13, r15
    jae .sub_full

    ; Subtracted partial
    add r14, r13
    xor r13, r13                    ; Finished!
    jmp .success

.sub_full:
    sub r13, r15
    add r14, r15
    
    ; Next cluster in chain
    mov ecx, r12d
    call fat32_get_next_cluster
    mov r12d, eax
    jmp .cluster_loop

.success:
    mov rax, [rsp + 8]              ; Original RDX (file size)
    sub rax, r13                    ; RAX = bytes read
    jmp .done

.error:
    xor rax, rax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; String case-insensitive comparison helper
; RCX = str1, RDX = str2
; Returns RAX = 1 if match, 0 if mismatch
str_case_compare:
    push rsi
    push rdi
    mov rsi, rcx
    mov rdi, rdx

.loop:
    lodsb
    mov bl, [rdi]
    inc rdi

    ; Convert AL to uppercase
    cmp al, 'a'
    jb .check_bl
    cmp al, 'z'
    ja .check_bl
    sub al, 32

.check_bl:
    ; Convert BL to uppercase
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
    
    mov rax, 1                      ; Match
    jmp .done

.mismatch:
    xor rax, rax                    ; Mismatch

.done:
    pop rdi
    pop rsi
    ret

; Copy UTF-16 characters to ASCII
; R8  = Source UTF-16 (2 bytes per char)
; RCX = Char count
; RDI = Destination ASCII
copy_utf16_to_ascii:
    xor rdx, rdx
.loop:
    cmp rdx, rcx
    jae .done
    
    movzx ax, word [r8 + rdx * 2]
    test ax, ax
    jz .done
    cmp ax, 0x7F
    ja .placeholder                 ; Replace non-ascii with placeholder
    
    mov [rdi + rdx], al
    jmp .next
.placeholder:
    mov byte [rdi + rdx], '?'
.next:
    inc rdx
    jmp .loop
.done:
    add rdi, rdx                    ; Advance RDI by characters written
    ret

; Format FAT short name to readable format (e.g. "PLANE   DIR" -> "PLANE", or "737     PNG" -> "737.png")
; RCX = Source 11-byte name
; RDX = Destination buffer
format_short_name:
    push rsi
    push rdi
    mov rsi, rcx
    mov rdi, rdx

    ; Copy name part (up to 8 bytes, skip trailing spaces)
    xor rcx, rcx                    ; char counter
.name_loop:
    cmp rcx, 8
    jae .check_ext
    mov al, [rsi + rcx]
    cmp al, ' '
    je .name_space
    mov [rdi], al
    inc rdi
.name_space:
    inc rcx
    jmp .name_loop

.check_ext:
    ; Check extension (last 3 bytes)
    mov al, [rsi + 8]
    cmp al, ' '
    je .done_ext
    
    ; Add dot
    mov byte [rdi], '.'
    inc rdi

    xor rcx, rcx
.ext_loop:
    cmp rcx, 3
    jae .done_ext
    mov al, [rsi + 8 + rcx]
    cmp al, ' '
    je .ext_space
    mov [rdi], al
    inc rdi
.ext_space:
    inc rcx
    jmp .ext_loop

.done_ext:
    mov byte [rdi], 0               ; Null terminate
    pop rdi
    pop rsi
    ret

section .data
bytes_per_sector dd 512
sectors_per_cluster db 8
reserved_sectors dw 32
num_fats db 2
sectors_per_fat dd 0
root_cluster dd 2

fat_start_sector dd 0
data_start_sector dd 0


msg_fat_init db "FAT32: Mounted boot partition successfully.", 13, 10, 0
msg_fat_err  db "FAT32: ERROR - Failed to mount boot partition!", 13, 10, 0

section .bss
comp_name resb 256
lfn_name resb 512
short_name_buf resb 16
