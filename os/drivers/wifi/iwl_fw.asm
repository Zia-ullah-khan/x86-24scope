; ==============================================================================
; x86-24scope OS - Intel iwlwifi firmware loader (Linux TLV .ucode)
; Loads \EFI\FIRMWARE\IWLWIFI.UC (or named fallbacks) via FAT32 into DRAM.
; ==============================================================================
bits 64
default rel

section .text

global wifi_load_firmware
global iwl_fw_sec_info
global iwl_fw_sec_count
global iwl_fw_blob_ptr
global iwl_fw_blob_size

extern fat32_open
extern fat32_read
extern con_puts
extern serial_puts
extern con_put_hex
extern con_newline
extern serial_put_hex
extern pmm_alloc_page

; Linux iwl-fw-file.h TLV types (fw/file.h)
IWL_TLV_UCODE_MAGIC             equ 0x0a4c5749   ; "IWL\n"
IWL_TLV_HDR_SIZE                equ 88           ; sizeof(iwl_tlv_ucode_header)

IWL_UCODE_TLV_INST              equ 1
IWL_UCODE_TLV_DATA              equ 2
IWL_UCODE_TLV_INIT              equ 3
IWL_UCODE_TLV_INIT_DATA         equ 4
IWL_UCODE_TLV_BOOT              equ 5
IWL_UCODE_TLV_PROBE_MAX_LEN     equ 6
IWL_UCODE_TLV_SEC_RT            equ 19
IWL_UCODE_TLV_SEC_INIT          equ 20
IWL_UCODE_TLV_SEC_WOWLAN        equ 21
IWL_UCODE_TLV_SECURE_SEC_RT     equ 24
IWL_UCODE_TLV_SECURE_SEC_INIT   equ 25
IWL_UCODE_TLV_SECURE_SEC_WOWLAN equ 26
IWL_UCODE_TLV_PAGING            equ 32
IWL_UCODE_TLV_SEC_RT_USNIFFER   equ 34
IWL_UCODE_TLV_IML               equ 52

FW_MAX_SECS                     equ 128
FW_MAX_SIZE                     equ (2 * 1024 * 1024)

; Separator markers inside sec stream (after parse, stored as type)
SEC_TYPE_LMAC                   equ 1
SEC_TYPE_UMAC                   equ 2
SEC_TYPE_PAGING                 equ 3
SEC_TYPE_SEP                    equ 0xFF

; RAX = 1 success
wifi_load_firmware:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov dword [fw_sec_count], 0
    mov qword [fw_blob_size], 0

    lea rcx, [msg_fw_load]
    call con_puts
    lea rcx, [msg_fw_load]
    call serial_puts

    ; Try primary path then alternates
    lea rcx, [fw_path_primary]
    call fat32_open
    test rax, rax
    jnz .opened
    lea rcx, [fw_path_alt1]
    call fat32_open
    test rax, rax
    jnz .opened
    lea rcx, [fw_path_alt2]
    call fat32_open
    test rax, rax
    jnz .opened
    jmp .missing

.opened:
    mov r12, rax                    ; cluster
    mov r13, rdx                    ; size
    test r13, r13
    jz .missing
    cmp r13, FW_MAX_SIZE
    ja .too_big

    lea rcx, [msg_fw_size]
    call con_puts
    mov rcx, r13
    call con_put_hex
    call con_newline

    lea r8, [fw_blob]
    mov rcx, r12
    mov rdx, r13
    call fat32_read
    test rax, rax
    jz .fail
    mov [fw_blob_size], rax

    call iwl_parse_tlv
    test rax, rax
    jz .fail

    lea rcx, [msg_fw_ok]
    call con_puts
    lea rcx, [msg_fw_ok]
    call serial_puts
    mov eax, [fw_sec_count]
    mov rcx, rax
    call con_put_hex
    call con_newline

    mov rax, 1
    jmp .done

.too_big:
    lea rcx, [msg_fw_big]
    call con_puts
    lea rcx, [msg_fw_big]
    call serial_puts
    xor rax, rax
    jmp .done

.missing:
    lea rcx, [msg_fw_miss]
    call con_puts
    lea rcx, [msg_fw_miss]
    call serial_puts
    xor rax, rax
    jmp .done

.fail:
    lea rcx, [msg_fw_fail]
    call con_puts
    lea rcx, [msg_fw_fail]
    call serial_puts
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

; Parse TLV stream in fw_blob. RAX=1 ok
iwl_parse_tlv:
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    lea rsi, [fw_blob]
    mov r12, [fw_blob_size]
    test r12, r12
    jz .bad

    ; Modern files: iwl_tlv_ucode_header (zero + magic + human + ver + ...)
    cmp r12, IWL_TLV_HDR_SIZE
    jb .try_legacy
    cmp dword [rsi], 0
    jne .try_legacy
    cmp dword [rsi + 4], IWL_TLV_UCODE_MAGIC
    jne .try_legacy
    add rsi, IWL_TLV_HDR_SIZE
    sub r12, IWL_TLV_HDR_SIZE
    jmp .tlv_loop

.try_legacy:
    ; v1/v2 header not supported for section extract yet; require TLV magic form
    jmp .bad

.tlv_loop:
    cmp r12, 8
    jb .finish

    mov eax, [rsi]                  ; type (LE)
    mov edx, [rsi + 4]              ; length
    add rsi, 8
    sub r12, 8

    ; Align length to 4
    mov ecx, edx
    add ecx, 3
    and ecx, 0xFFFFFFFC
    cmp r12, rcx
    jb .bad

    ; Firmware image sections we keep for DMA load
    cmp eax, IWL_UCODE_TLV_INST
    je .store
    cmp eax, IWL_UCODE_TLV_DATA
    je .store
    cmp eax, IWL_UCODE_TLV_INIT
    je .store
    cmp eax, IWL_UCODE_TLV_INIT_DATA
    je .store
    cmp eax, IWL_UCODE_TLV_SEC_RT
    je .store
    cmp eax, IWL_UCODE_TLV_SEC_INIT
    je .store
    cmp eax, IWL_UCODE_TLV_SEC_WOWLAN
    je .store
    cmp eax, IWL_UCODE_TLV_SECURE_SEC_RT
    je .store
    cmp eax, IWL_UCODE_TLV_SECURE_SEC_INIT
    je .store
    cmp eax, IWL_UCODE_TLV_SECURE_SEC_WOWLAN
    je .store
    cmp eax, IWL_UCODE_TLV_PAGING
    je .store
    cmp eax, IWL_UCODE_TLV_SEC_RT_USNIFFER
    je .store
    cmp eax, IWL_UCODE_TLV_IML
    je .store
    jmp .next

.store:
    mov ebx, [fw_sec_count]
    cmp ebx, FW_MAX_SECS
    jae .next
    lea rdi, [fw_secs]
    mov eax, ebx
    imul eax, 16                    ; each sec: ptr(8)+len(4)+type(4)
    lea rdi, [rdi + rax]
    mov [rdi], rsi                  ; data ptr
    mov [rdi + 8], edx              ; length
    mov eax, [rsi - 8]              ; original type
    mov [rdi + 12], eax
    inc dword [fw_sec_count]

.next:
    add rsi, rcx
    sub r12, rcx
    jmp .tlv_loop

.finish:
    cmp dword [fw_sec_count], 0
    jz .bad
    mov rax, 1
    jmp .out
.bad:
    xor rax, rax
.out:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; RCX=index ??? RAX=ptr, RDX=len, R8=type (0 if bad)
iwl_fw_sec_info:
    xor eax, eax
    xor edx, edx
    xor r8d, r8d
    cmp ecx, [fw_sec_count]
    jae .done
    lea r9, [fw_secs]
    mov eax, ecx
    shl eax, 4
    add r9, rax
    mov rax, [r9]
    mov edx, [r9 + 8]
    mov r8d, [r9 + 12]
.done:
    ret

iwl_fw_sec_count:
    mov eax, [fw_sec_count]
    ret

iwl_fw_blob_ptr:
    lea rax, [fw_blob]
    ret

iwl_fw_blob_size:
    mov rax, [fw_blob_size]
    ret

section .data
fw_path_primary db "\EFI\FIRMWARE\IWLWIFI.UC", 0
fw_path_alt1    db "\EFI\FIRMWARE\IWLWIFI.UCODE", 0
fw_path_alt2    db "\EFI\FIRMWARE\FW.UC", 0

msg_fw_load db "WiFi: Loading iwlwifi firmware...", 13, 10, 0
msg_fw_size db "WiFi: Firmware bytes=0x", 0
msg_fw_ok   db "WiFi: Firmware TLV parse OK, sections=0x", 0
msg_fw_miss db "WiFi: Firmware file not found under \EFI\FIRMWARE\", 13, 10, 0
msg_fw_big  db "WiFi: Firmware too large (max 2MB).", 13, 10, 0
msg_fw_fail db "WiFi: Firmware load/parse failed.", 13, 10, 0

align 8
fw_blob_size dq 0
fw_sec_count dd 0

section .bss
alignb 16
; sec: qword ptr, dword len, dword type
fw_secs resb FW_MAX_SECS * 16
alignb 4096
fw_blob resb FW_MAX_SIZE
