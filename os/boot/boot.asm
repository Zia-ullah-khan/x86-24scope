; ==============================================================================
; x86-24scope OS - UEFI Bootloader (Linked version)
; ==============================================================================
bits 64
default rel

section .text

global uefi_main
extern kernel_main

; Structures and offsets
%define SYSTEM_TABLE_CON_OUT        64
%define SYSTEM_TABLE_BOOT_SERVICES  96

%define SIMPLE_TEXT_OUTPUT_RESET    0
%define SIMPLE_TEXT_OUTPUT_STRING   8
%define SIMPLE_TEXT_OUTPUT_CLEAR    48

%define BOOT_SERVICES_GET_MEM_MAP   56
%define BOOT_SERVICES_EXIT_BS       232
%define BOOT_SERVICES_LOCATE_PROTO  320

; EFI_GRAPHICS_OUTPUT_PROTOCOL: QueryMode@0, SetMode@8, Blt@16, Mode*@24
%define GOP_MODE_OFFSET             24

; Main entry point called by UEFI firmware
uefi_main:
    ; Save UEFI arguments
    ; RCX = ImageHandle
    ; RDX = SystemTable
    push rbp
    mov rbp, rsp
    sub rsp, 64                     ; Shadow space + local variables

    mov [image_handle], rcx
    mov [system_table], rdx

    ; Print boot message
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]   ; ConOut pointer
    lea rdx, [boot_msg]
    call uefi_print

    ; Locate Graphics Output Protocol (GOP)
    mov rax, [system_table]
    mov rax, [rax + SYSTEM_TABLE_BOOT_SERVICES]
    lea rcx, [gop_guid]
    xor rdx, rdx                    ; Registration = NULL
    lea r8, [gop_interface]         ; Output pointer
    call [rax + BOOT_SERVICES_LOCATE_PROTO]
    test rax, rax
    jnz .gop_failed

    ; Print GOP success
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [dbg_gop_ok]
    call uefi_print

    ; Extract framebuffer information from GOP
    mov rsi, [gop_interface]
    mov rsi, [rsi + GOP_MODE_OFFSET]        ; GOP->Mode
    
    ; Mode structure offsets:
    ; 8: Info pointer (8 bytes)
    ; 24: FrameBufferBase (8 bytes)
    ; 32: FrameBufferSize (8 bytes)
    ;
    ; Info (EFI_GRAPHICS_OUTPUT_MODE_INFORMATION) offsets:
    ; 4: HorizontalResolution
    ; 8: VerticalResolution
    ; 32: PixelsPerScanLine (after PixelFormat + 16-byte PixelInformation)
    mov rdi, [rsi + 8]                      ; Info pointer
    
    mov eax, [rdi + 4]                      ; Info->HorizontalResolution
    mov [boot_info + 0], eax
    mov eax, [rdi + 8]                      ; Info->VerticalResolution
    mov [boot_info + 4], eax
    mov eax, [rdi + 32]                     ; Info->PixelsPerScanLine
    mov edx, [boot_info + 0]
    cmp eax, edx
    jae .ppsl_ok
    mov eax, edx                            ; pitch must be >= width
.ppsl_ok:
    test eax, eax
    jnz .ppsl_nonzero
    mov eax, edx
.ppsl_nonzero:
    mov [boot_info + 8], eax
    
    mov rax, [rsi + 24]                     ; Mode->FrameBufferBase
    mov [boot_info + 16], rax
    mov rax, [rsi + 32]                     ; Mode->FrameBufferSize
    mov [boot_info + 24], rax

    jmp .gop_done

.gop_failed:
    ; GOP not found - print warning but continue with dummy framebuffer
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [err_gop]
    call uefi_print

    ; Set dummy framebuffer info so kernel doesn't crash on null pointer
    mov dword [boot_info + 0], 0            ; Width = 0 (signals no framebuffer)
    mov dword [boot_info + 4], 0            ; Height = 0
    mov dword [boot_info + 8], 0            ; PixelsPerScanLine = 0
    mov qword [boot_info + 16], 0           ; FrameBufferBase = NULL
    mov qword [boot_info + 24], 0           ; FrameBufferSize = 0

.gop_done:
    ; --- Read Boot Disk into RAM ---
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [dbg_disk]
    call uefi_print

    mov rax, [system_table]
    mov rax, [rax + SYSTEM_TABLE_BOOT_SERVICES]
    mov [boot_services], rax

    ; Get LoadedImage
    mov rcx, [image_handle]
    lea rdx, [loaded_image_guid]
    lea r8, [loaded_image]
    mov rax, [boot_services]
    call [rax + 152]                        ; HandleProtocol (offset 152)
    test rax, rax
    jnz .disk_read_done                     ; Skip if we can't read LoadedImage

    ; Get DeviceHandle
    mov rsi, [loaded_image]
    mov rcx, [rsi + 24]                     ; DeviceHandle
    mov [device_handle], rcx

    ; Get BlockIo
    mov rcx, [device_handle]
    lea rdx, [block_io_guid]
    lea r8, [block_io]
    mov rax, [boot_services]
    call [rax + 152]                        ; HandleProtocol
    test rax, rax
    jnz .disk_read_done

    ; Get Media stats
    mov rsi, [block_io]
    mov rdi, [rsi + 8]                      ; Media
    mov eax, [rdi + 12]                     ; BlockSize
    mov [block_size], eax
    mov rax, [rdi + 24]                     ; LastBlock
    inc rax                                 ; TotalBlocks
    mov [total_blocks], rax

    ; Calculate partition size
    movzx rdx, dword [block_size]
    imul rax, rdx                           ; Size in bytes
    mov [disk_size_bytes], rax

    ; Cap RAM disk copy. Need enough of efi_part.img that static assets
    ; (Plane Icons, maps) are reachable ??? those currently sit ~160MB+ in.
    ; Also enforce a minimum so tiny El Torito windows still get a FAT BPB.
    mov r8, 2 * 1024 * 1024                 ; 2MB minimum
    cmp rax, r8
    jae .size_min_ok
    mov rax, r8
    mov [disk_size_bytes], rax
.size_min_ok:
    mov r8, 192 * 1024 * 1024               ; 192MB max (fits in 512MB VM)
    cmp rax, r8
    jbe .size_ok
    mov rax, r8
    mov [disk_size_bytes], rax
.size_ok:

    ; Allocate memory (pages)
    mov rax, [disk_size_bytes]
    add rax, 4095
    shr rax, 12                             ; Pages count
    mov [allocated_pages_count], rax

    xor rcx, rcx                            ; AllocateAnyPages
    mov rdx, 2                              ; EfiLoaderData
    mov r8, [allocated_pages_count]
    lea r9, [disk_buffer_ptr]
    mov rax, [boot_services]
    call [rax + 40]                         ; AllocatePages (offset 40)
    test rax, rax
    jnz .disk_read_done

    ; ReadBlocks (EFI_BLOCK_IO_PROTOCOL.ReadBlocks @ offset 24).
    ; Try LBA 0 first (El Torito boot-image window starts at FAT BPB).
    ; If that has no FAT signature, retry ISO LBA 21 (whole-CD BlockIo).
    mov rsi, [block_io]
    mov rax, [rsi + 24]                     ; ReadBlocks
    mov r11, [block_io]
    mov rdi, [r11 + 8]                      ; Media
    mov edx, [rdi]                          ; MediaId

    sub rsp, 64
    mov rcx, r11
    xor r8, r8                              ; LBA 0
    mov r9, [disk_size_bytes]
    mov r10, [disk_buffer_ptr]
    mov [rsp + 32], r10
    call rax
    add rsp, 64
    test rax, rax
    jnz .try_iso_lba21

    mov rsi, [disk_buffer_ptr]
    cmp word [rsi + 510], 0xAA55
    jne .try_iso_lba21
    cmp word [rsi + 11], 512
    je .read_ok

.try_iso_lba21:
    ; Whole ISO9660 device: FAT lives at 2048-byte LBA 21
    cmp dword [block_size], 2048
    jne .disk_read_done
    mov rsi, [block_io]
    mov rax, [rsi + 24]
    mov r11, [block_io]
    mov rdi, [r11 + 8]
    mov edx, [rdi]
    sub rsp, 64
    mov rcx, r11
    mov r8, 21
    mov r9, [disk_size_bytes]
    mov r10, [disk_buffer_ptr]
    mov [rsp + 32], r10
    call rax
    add rsp, 64
    test rax, rax
    jnz .disk_read_done

.read_ok:
    ; Save to BootInfo
    mov rax, [disk_buffer_ptr]
    mov [boot_info + 64], rax
    mov rax, [disk_size_bytes]
    mov [boot_info + 72], rax

    ; Verify the RAM disk actually contains a FAT BPB (or ISO+FAT).
    mov rsi, [disk_buffer_ptr]
    cmp word [rsi + 510], 0xAA55
    je .disk_sig_ok
    cmp word [rsi + 43008 + 510], 0xAA55
    je .disk_sig_ok
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [dbg_disk_nosig]
    call uefi_print
    jmp .disk_read_done
.disk_sig_ok:
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [dbg_disk_sigok]
    call uefi_print

.disk_read_done:
    ; Debug: print disk done
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [dbg_disk_done]
    call uefi_print

    ; Scan UEFI Configuration Table for ACPI RSDP pointer
    mov rax, [system_table]
    mov rcx, [rax + 104]                    ; NumberOfTableEntries
    mov rsi, [rax + 112]                    ; ConfigurationTable pointer
    xor rdx, rdx                            ; Counter
.config_loop:
    cmp rdx, rcx
    jae .config_done
    mov r8, rdx
    imul r8, 24
    lea r8, [rsi + r8]                      ; r8 points to current entry
    
    mov rax, [r8]                           ; GUID first 8 bytes
    mov r9, [r8 + 8]                        ; GUID second 8 bytes

    ; Check ACPI 2.0
    mov r10, 0x11D3E4F18868E871
    cmp rax, r10
    jne .check_acpi1
    mov r10, 0x81883CC7800022BC
    cmp r9, r10
    je .found_acpi

.check_acpi1:
    ; Check ACPI 1.0
    mov r10, 0x11D32D88EB9D2D30
    cmp rax, r10
    jne .next_entry
    mov r10, 0x4DC13F279000169A
    cmp r9, r10
    je .found_acpi

.next_entry:
    inc rdx
    jmp .config_loop

.found_acpi:
    mov rax, [r8 + 16]                      ; Table pointer
    mov [boot_info + 56], rax

.config_done:
    ; Debug: print ACPI done
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [dbg_acpi_done]
    call uefi_print

    ; --- WiFi credentials via UEFI keyboard (works on USB laptop keyboards) ---
    call uefi_wifi_prompt

    ; Get System Memory Map
    mov rax, [system_table]
    mov rax, [rax + SYSTEM_TABLE_BOOT_SERVICES]
    mov [boot_services], rax

    ; Debug: print about to exit boot services.
    ; IMPORTANT: this must happen BEFORE the final GetMemoryMap. Console output
    ; can allocate memory, which changes the memory map and invalidates the
    ; map key that ExitBootServices requires.
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [dbg_exit_bs]
    call uefi_print

    mov r12, 8                              ; Retry attempts
.exit_bs_retry:
    ; GetMemoryMap must immediately precede ExitBootServices
    mov qword [memory_map_size], 32768      ; Reset to full buffer size
    mov rax, [boot_services]
    lea rcx, [memory_map_size]
    lea rdx, [memory_map]
    lea r8, [map_key]
    lea r9, [descriptor_size]
    lea r10, [descriptor_version]
    mov [rsp + 32], r10
    call [rax + BOOT_SERVICES_GET_MEM_MAP]
    test rax, rax
    jnz .mem_map_failed

    ; Save memory map parameters to boot_info
    lea rax, [memory_map]
    mov [boot_info + 32], rax
    mov rax, [memory_map_size]
    mov [boot_info + 40], rax
    mov rax, [descriptor_size]
    mov [boot_info + 48], rax

    ; Exit Boot Services
    mov rcx, [image_handle]
    mov rdx, [map_key]
    mov rax, [boot_services]
    call [rax + BOOT_SERVICES_EXIT_BS]
    test rax, rax
    jz .exit_bs_ok

    dec r12
    jnz .exit_bs_retry
    jmp .exit_bs_failed

.exit_bs_ok:

    ; ==========================================================================
    ; BARE METAL STARTS HERE
    ; ==========================================================================
    cli                             ; Disable interrupts
    cld                             ; UEFI may leave DF=1; string ops must go forward

    ; --- Framebuffer smoke test ---
    ; Write a bright red bar at the top of the framebuffer to prove we're alive
    mov rdi, [boot_info + 16]       ; FrameBufferBase
    test rdi, rdi
    jz .no_fb_test                  ; Skip if no framebuffer
    
    ; Fill first 2 scanlines with bright red (0x00FF0000 in BGRX)
    mov eax, [boot_info + 8]        ; PixelsPerScanLine
    test eax, eax
    jnz .fb_pitch_ok
    mov eax, [boot_info + 0]        ; Fall back to width
.fb_pitch_ok:
    shl eax, 1                      ; 2 scanlines worth of pixels
    mov ecx, eax
    mov eax, 0x00FF0000             ; Bright red
    rep stosd                       ; Write pixels

.no_fb_test:
    ; Save boot_info address in RCX for kernel entry
    lea rcx, [boot_info]
    
    ; Jump to Kernel Main Entry
    jmp kernel_main

.mem_map_failed:
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [err_mem]
    call uefi_print
    jmp .halt

.exit_bs_failed:
    ; If ExitBootServices failed, we are still in UEFI context.
    ; Print error and halt.
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [err_exit_bs]
    call uefi_print
    
.halt:
    cli
    hlt
    jmp .halt

; Helpers
%define SYSTEM_TABLE_CON_IN         48
%define SIMPLE_TEXT_INPUT_READ      8
%define BOOT_SERVICES_STALL         248
%define EFI_NOT_READY               0x8000000000000006

; Prompt for SSID/password using EFI ConIn before ExitBootServices.
; 8s timeout on first SSID key; empty/skip leaves creds_valid=0 (QEMU-safe).
uefi_wifi_prompt:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    sub rsp, 64

    mov byte [boot_info + 177], 0   ; creds_valid = 0
    lea rdi, [boot_info + 80]       ; ssid
    xor eax, eax
    mov ecx, 33
    rep stosb
    lea rdi, [boot_info + 113]      ; psk
    mov ecx, 64
    rep stosb

    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [msg_wifi_banner]
    call uefi_print
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [msg_wifi_ssid]
    call uefi_print

    ; Wait up to ~8s for first key
    mov ebx, 8000
.wait_first:
    call uefi_try_key
    test rax, rax
    jnz .got_first
    mov rax, [system_table]
    mov rax, [rax + SYSTEM_TABLE_BOOT_SERVICES]
    mov rcx, 1000                   ; 1ms
    call [rax + BOOT_SERVICES_STALL]
    dec ebx
    jnz .wait_first
    ; timeout ??? skip WiFi setup
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [msg_wifi_skip]
    call uefi_print
    jmp .done

.got_first:
    ; AL = unicode low byte already in [uefi_key_unicode]
    lea rdi, [boot_info + 80]
    xor ebx, ebx                    ; length
    movzx eax, word [uefi_key_unicode]
    cmp ax, 13
    je .ssid_done_empty
    cmp ax, 10
    je .ssid_done_empty
    cmp ax, 8
    je .ssid_read_loop
    cmp ax, 32
    jb .ssid_read_loop
    mov [rdi + rbx], al
    inc ebx
    call uefi_echo_char

.ssid_read_loop:
    call uefi_wait_key
    movzx eax, word [uefi_key_unicode]
    cmp ax, 13
    je .ssid_done
    cmp ax, 10
    je .ssid_done
    cmp ax, 8
    je .ssid_bs
    cmp ax, 32
    jb .ssid_read_loop
    cmp ebx, 32
    jae .ssid_read_loop
    mov [rdi + rbx], al
    inc ebx
    call uefi_echo_char
    jmp .ssid_read_loop

.ssid_bs:
    test ebx, ebx
    jz .ssid_read_loop
    dec ebx
    mov byte [rdi + rbx], 0
    call uefi_echo_bs
    jmp .ssid_read_loop

.ssid_done_empty:
    xor ebx, ebx
.ssid_done:
    mov byte [rdi + rbx], 0
    call uefi_echo_nl
    test ebx, ebx
    jz .done

    ; Password
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [msg_wifi_psk]
    call uefi_print

    lea rdi, [boot_info + 113]
    xor ebx, ebx
.psk_loop:
    call uefi_wait_key
    movzx eax, word [uefi_key_unicode]
    cmp ax, 13
    je .psk_done
    cmp ax, 10
    je .psk_done
    cmp ax, 8
    je .psk_bs
    cmp ax, 32
    jb .psk_loop
    cmp ebx, 63
    jae .psk_loop
    mov [rdi + rbx], al
    inc ebx
    ; echo '*'
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [msg_star]
    call uefi_print
    jmp .psk_loop

.psk_bs:
    test ebx, ebx
    jz .psk_loop
    dec ebx
    mov byte [rdi + rbx], 0
    call uefi_echo_bs
    jmp .psk_loop

.psk_done:
    mov byte [rdi + rbx], 0
    call uefi_echo_nl
    mov byte [boot_info + 177], 1   ; creds_valid

    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [msg_wifi_ok]
    call uefi_print

.done:
    add rsp, 64
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; Returns RAX=1 if key available, unicode in uefi_key_unicode
uefi_try_key:
    push rbx
    sub rsp, 32
    mov rax, [system_table]
    mov rcx, [rax + SYSTEM_TABLE_CON_IN]
    test rcx, rcx
    jz .none
    lea rdx, [uefi_input_key]
    mov rax, [rcx + SIMPLE_TEXT_INPUT_READ]
    call rax
    cmp rax, 0
    jne .none
    mov ax, [uefi_input_key + 2]    ; UnicodeChar
    mov [uefi_key_unicode], ax
    mov rax, 1
    jmp .out
.none:
    xor rax, rax
.out:
    add rsp, 32
    pop rbx
    ret

uefi_wait_key:
    push rbx
.wait:
    call uefi_try_key
    test rax, rax
    jnz .got
    mov rax, [system_table]
    mov rax, [rax + SYSTEM_TABLE_BOOT_SERVICES]
    mov rcx, 1000
    sub rsp, 32
    call [rax + BOOT_SERVICES_STALL]
    add rsp, 32
    jmp .wait
.got:
    pop rbx
    ret

uefi_echo_char:
    ; echo last unicode as one-char UTF-16 string
    mov ax, [uefi_key_unicode]
    mov [msg_onechar], ax
    mov word [msg_onechar + 2], 0
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [msg_onechar]
    jmp uefi_print

uefi_echo_bs:
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [msg_bs]
    jmp uefi_print

uefi_echo_nl:
    mov rdx, [system_table]
    mov rcx, [rdx + SYSTEM_TABLE_CON_OUT]
    lea rdx, [msg_crlf]
    jmp uefi_print

uefi_print:
    ; RCX = ConOut, RDX = UTF-16 String
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov rax, [rcx + SIMPLE_TEXT_OUTPUT_STRING]
    call rax
    add rsp, 32
    pop rbp
    ret

; ==============================================================================
; DATA SECTION (.data)
; ==============================================================================
section .data

align 8
image_handle dq 0
system_table dq 0
boot_services dq 0

gop_guid:
    ; EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID = {9042A9DE-23DC-4A38-96FB-7ADED080516A}
    dd 0x9042A9DE
    dw 0x23DC
    dw 0x4A38
    db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A

gop_interface dq 0

; Boot Messages (UTF-16 L"string")
boot_msg:
    dw '2', '4', 'S', 'c', 'o', 'p', 'e', ' ', 'O', 'S', ' ', 'U', 'E', 'F', 'I', ' ', 'B', 'o', 'o', 't', 'l', 'o', 'a', 'd', 'e', 'r', ' ', 'L', 'o', 'a', 'd', 'e', 'd', '.', '.', '.', 13, 10, 0
exiting_msg:
    dw 'E', 'x', 'i', 't', 'i', 'n', 'g', ' ', 'U', 'E', 'F', 'I', ' ', 'B', 'o', 'o', 't', ' ', 'S', 'e', 'r', 'v', 'i', 'c', 'e', 's', ' ', 'a', 'n', 'd', ' ', 'l', 'a', 'u', 'n', 'c', 'h', 'i', 'n', 'g', ' ', 'k', 'e', 'r', 'n', 'e', 'l', '.', '.', '.', 13, 10, 0
err_gop:
    dw 'E', 'R', 'R', 'O', 'R', ':', ' ', 'F', 'a', 'i', 'l', 'e', 'd', ' ', 't', 'o', ' ', 'l', 'o', 'c', 'a', 't', 'e', ' ', 'G', 'O', 'P', '!', 13, 10, 0
err_mem:
    dw 'E', 'R', 'R', 'O', 'R', ':', ' ', 'F', 'a', 'i', 'l', 'e', 'd', ' ', 't', 'o', ' ', 'g', 'e', 't', ' ', 'm', 'e', 'm', 'o', 'r', 'y', ' ', 'm', 'a', 'p', '!', 13, 10, 0
err_exit_bs:
    dw 'E', 'R', 'R', 'O', 'R', ':', ' ', 'E', 'x', 'i', 't', 'B', 'o', 'o', 't', 'S', 'e', 'r', 'v', 'i', 'c', 'e', 's', ' ', 'f', 'a', 'i', 'l', 'e', 'd', '!', 13, 10, 0

dbg_gop_ok:
    dw '[', '1', ']', ' ', 'G', 'O', 'P', ' ', 'O', 'K', 13, 10, 0
dbg_disk:
    dw '[', '2', ']', ' ', 'D', 'i', 's', 'k', ' ', 'r', 'e', 'a', 'd', '.', '.', '.', 13, 10, 0
dbg_disk_done:
    dw '[', '3', ']', ' ', 'D', 'i', 's', 'k', ' ', 'd', 'o', 'n', 'e', 13, 10, 0
dbg_disk_sigok:
    dw '[', '3', 'a', ']', ' ', 'D', 'i', 's', 'k', ' ', 'F', 'A', 'T', ' ', 's', 'i', 'g', ' ', 'O', 'K', 13, 10, 0
dbg_disk_nosig:
    dw '[', '3', 'a', ']', ' ', 'D', 'i', 's', 'k', ' ', 'F', 'A', 'T', ' ', 's', 'i', 'g', ' ', 'M', 'I', 'S', 'S', 13, 10, 0
dbg_acpi_done:
    dw '[', '4', ']', ' ', 'A', 'C', 'P', 'I', ' ', 'd', 'o', 'n', 'e', 13, 10, 0
dbg_exit_bs:
    dw '[', '5', ']', ' ', 'E', 'x', 'i', 't', 'i', 'n', 'g', ' ', 'B', 'S', '.', '.', '.', 13, 10, 0

msg_wifi_banner:
    dw 13, 10, 'W', 'i', 'F', 'i', ' ', 's', 'e', 't', 'u', 'p', ' ', '(', 'U', 'E', 'F', 'I', ' ', 'k', 'e', 'y', 'b', 'o', 'a', 'r', 'd', ')', 13, 10, 0
msg_wifi_ssid:
    dw 'S', 'S', 'I', 'D', ' ', '(', 'E', 'n', 't', 'e', 'r', '=', 's', 'k', 'i', 'p', ',', ' ', '8', 's', ')', ':', ' ', 0
msg_wifi_psk:
    dw 'P', 'a', 's', 's', 'w', 'o', 'r', 'd', ':', ' ', 0
msg_wifi_skip:
    dw '(', 'n', 'o', ' ', 'S', 'S', 'I', 'D', ' ', '-', ' ', 's', 'k', 'i', 'p', 'p', 'i', 'n', 'g', ' ', 'W', 'i', 'F', 'i', ' ', 's', 'e', 't', 'u', 'p', ')', 13, 10, 0
msg_wifi_ok:
    dw 'W', 'i', 'F', 'i', ' ', 'c', 'r', 'e', 'd', 'e', 'n', 't', 'i', 'a', 'l', 's', ' ', 's', 'a', 'v', 'e', 'd', '.', 13, 10, 0
msg_star:
    dw '*', 0
msg_bs:
    dw 8, ' ', 8, 0
msg_crlf:
    dw 13, 10, 0
msg_onechar:
    dw 0, 0
align 8
uefi_input_key:
    dw 0, 0
uefi_key_unicode:
    dw 0

; BootInfo structure passed to kernel:
; Offset 0:  Width (4 bytes)
; Offset 4:  Height (4 bytes)
; Offset 8:  PixelsPerScanLine (4 bytes)
; Offset 12: Padding (4 bytes)
; Offset 16: FrameBufferBase (8 bytes)
; Offset 24: FrameBufferSize (8 bytes)
; Offset 32: MemoryMapBase (8 bytes)
; Offset 40: MemoryMapSize (8 bytes)
; Offset 48: DescriptorSize (8 bytes)
; Offset 56: RsdpAddress (8 bytes)
; Offset 64: DiskBufferBase (8 bytes)
; Offset 72: DiskBufferSize (8 bytes)
; Offset 80: WiFi SSID (33 bytes)
; Offset 113: WiFi PSK (64 bytes)
; Offset 177: WiFiCredsValid (1 byte)
align 16
boot_info:
    dd 0                            ; Width
    dd 0                            ; Height
    dd 0                            ; PixelsPerScanLine
    dd 0                            ; Padding
    dq 0                            ; FrameBufferBase
    dq 0                            ; FrameBufferSize
    dq 0                            ; MemoryMapBase
    dq 0                            ; MemoryMapSize
    dq 0                            ; DescriptorSize
    dq 0                            ; RsdpAddress
    dq 0                            ; DiskBufferBase
    dq 0                            ; DiskBufferSize
    times 33 db 0                   ; WiFi SSID @80
    times 64 db 0                   ; WiFi PSK @113
    db 0                            ; WiFiCredsValid @177
    times 7 db 0                    ; pad to 16-byte align

; Loaded Image / Block IO variables
align 8
loaded_image_guid:
    dd 0x5B1B31A1
    dw 0x9562
    dw 0x11D2
    db 0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

block_io_guid:
    dd 0x964E5B21
    dw 0x6459
    dw 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

loaded_image dq 0
device_handle dq 0
block_io dq 0
block_size dd 0
total_blocks dq 0
disk_size_bytes dq 0
allocated_pages_count dq 0
disk_buffer_ptr dq 0

; Memory Map variables
memory_map_size dq 32768            ; Set size of pre-allocated buffer
map_key dq 0
descriptor_size dq 0
descriptor_version dd 0

section .bss
align 4096
; Pre-allocate 32KB buffer for UEFI memory map
memory_map:
    resb 32768
