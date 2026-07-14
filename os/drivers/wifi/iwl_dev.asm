; ==============================================================================
; x86-24scope OS - Intel iwlwifi device bring-up (gen2/gen3 context info)
; ==============================================================================
bits 64
default rel

section .text

global iwl_driver_init
global iwl_driver_send
global iwl_driver_recv
global iwl_driver_get_mac
global iwl_mmio_ptr
global iwl_is_associated

extern con_puts
extern serial_puts
extern con_put_hex
extern con_newline
extern serial_put_hex
extern sleep_ms
extern wifi_load_firmware
extern iwl_fw_sec_count
extern iwl_fw_sec_info
extern iwl_cmd_init
extern iwl_cmd_wait_alive
extern iwl_cmd_poll_rx
extern iwl_get_last_rx
extern iwl_cmd_rx_free_addr
extern iwl_cmd_rx_used_addr
extern iwl_cmd_rx_status_addr
extern iwl_cmd_tx_tfd_addr
extern wifi_send_cmd
extern wifi_register_ops
extern wifi_set_ready
extern iwl_wifi_scan
extern iwl_wifi_connect
extern iwl_assoc_flag
extern pci_read_config
extern vmm_map_mmio

; CSR
CSR_HW_IF_CONFIG_REG            equ 0x000
CSR_INT                         equ 0x008
CSR_INT_MASK                    equ 0x00C
CSR_FH_INT_STATUS               equ 0x010
CSR_RESET                       equ 0x020
CSR_GP_CNTRL                    equ 0x024
CSR_HW_REV                      equ 0x028
CSR_DRAM_INT_TBL_REG            equ 0x0A0
CSR_CTXT_INFO_BA                equ 0x40
CSR_CTXT_INFO_ADDR              equ 0x118
CSR_CTXT_INFO_BOOT_CTRL         equ 0x0
CSR_RESET_SW_RESET              equ 0x80
CSR_GP_CNTRL_INIT_DONE          equ 0x04
CSR_GP_CNTRL_MAC_ACCESS_REQ     equ 0x08
CSR_GP_CNTRL_MAC_CLOCK_READY    equ 0x01
CSR_INT_BIT_ALIVE               equ 1
CSR_AUTO_FUNC_BOOT_ENA          equ 2
CSR_AUTO_FUNC_INIT              equ 0x80

IWL_MAX_DRAM_ENTRY              equ 64
IWL_CTXT_INFO_TFD_FORMAT_LONG   equ 0x100
IWL_CTXT_INFO_RB_SIZE_4K        equ 0x4
; control: RB_CB_SIZE in bits 4-7, RB_SIZE in bits 9-12
; exponent 6 = 64 entries ??? (6 << 4)
IWL_CTXT_CTRL_FLAGS             equ (IWL_CTXT_INFO_TFD_FORMAT_LONG | (6 << 4) | (IWL_CTXT_INFO_RB_SIZE_4K << 9))

iwl_driver_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov [iwl_mmio], rcx
    mov [iwl_mmio_ptr], rcx
    mov [iwl_bdf], edx

    lea rcx, [msg_iwl_init]
    call con_puts
    lea rcx, [msg_iwl_init]
    call serial_puts

    ; Read PCI device ID for gen2/gen3 selection
    mov eax, [iwl_bdf]
    movzx r14d, al
    mov ecx, eax
    shr ecx, 8
    movzx r13d, cl
    shr eax, 16
    movzx r12d, al
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, 0
    call pci_read_config
    mov [iwl_pci_id], eax
    shr eax, 16
    mov [iwl_device_id], ax

    ; Load + parse firmware (required)
    call wifi_load_firmware
    test rax, rax
    jz .fail

    mov rbx, [iwl_mmio]
    test rbx, rbx
    jz .fail

    ; Print BAR first so a map fault is diagnosable
    lea rcx, [msg_iwl_bar]
    call con_puts
    lea rcx, [msg_iwl_bar]
    call serial_puts
    mov rcx, rbx
    call con_put_hex
    call con_newline
    mov rcx, rbx
    call serial_put_hex
    lea rcx, [iwl_msg_crlf]
    call serial_puts

    ; Map PCI BAR into page tables (often >4GB on modern laptops)
    mov rcx, rbx
    mov rdx, 0x200000               ; at least one 2MB page
    call vmm_map_mmio
    test rax, rax
    jnz .mapped
    lea rcx, [msg_iwl_mapfail]
    call con_puts
    lea rcx, [msg_iwl_mapfail]
    call serial_puts
    jmp .fail

.mapped:
    mov eax, [rbx + CSR_HW_REV]
    mov [iwl_hw_rev], eax
    lea rcx, [msg_iwl_rev]
    call con_puts
    mov ecx, [iwl_hw_rev]
    call con_put_hex
    call con_newline

    ; Soft reset
    mov eax, [rbx + CSR_RESET]
    or eax, CSR_RESET_SW_RESET
    mov [rbx + CSR_RESET], eax
    mov rcx, 20
    call sleep_ms

    ; Request MAC access + INIT_DONE
    mov eax, [rbx + CSR_GP_CNTRL]
    or eax, CSR_GP_CNTRL_MAC_ACCESS_REQ | CSR_GP_CNTRL_INIT_DONE
    mov [rbx + CSR_GP_CNTRL], eax

    mov ecx, 100
.wait_clk:
    mov eax, [rbx + CSR_GP_CNTRL]
    test eax, CSR_GP_CNTRL_MAC_CLOCK_READY
    jnz .clk_ok
    push rcx
    mov rcx, 5
    call sleep_ms
    pop rcx
    loop .wait_clk
.clk_ok:

    mov dword [rbx + CSR_INT_MASK], 0
    mov dword [rbx + CSR_INT], 0xFFFFFFFF

    call iwl_cmd_init
    test rax, rax
    jz .fail

    call iwl_build_context
    test rax, rax
    jz .fail

    ; Enable ALIVE interrupt only during load
    mov dword [rbx + CSR_INT_MASK], CSR_INT_BIT_ALIVE

    call iwl_kick_fw_load
    test rax, rax
    jz .fail

    call iwl_cmd_wait_alive
    test rax, rax
    jz .fail

    ; Enable broader interrupts after alive
    mov dword [rbx + CSR_INT_MASK], 0xFFFFFFFF

    ; Register WiFi ops
    lea rcx, [iwl_ops_table]
    call wifi_register_ops
    mov al, 1
    call wifi_set_ready

    mov byte [iwl_ready], 1
    lea rcx, [msg_iwl_ok]
    call con_puts
    lea rcx, [msg_iwl_ok]
    call serial_puts
    mov rax, 1
    jmp .done

.fail:
    mov byte [iwl_ready], 0
    xor al, al
    call wifi_set_ready
    lea rcx, [msg_iwl_fail]
    call con_puts
    lea rcx, [msg_iwl_fail]
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

; Build gen2 or gen3 context structures in BSS (identity-mapped)
iwl_build_context:
    push rbx
    push rsi
    push rdi
    push r12

    ; Zero context info gen2 struct (~3KB with dram maps)
    lea rdi, [ctxt_info]
    mov rcx, ctxt_info_end - ctxt_info
    shr rcx, 3
    xor eax, eax
    rep stosq

    lea rdi, [ctxt_info]
    ; version.mac_id = HW_REV low 16
    mov ax, [iwl_hw_rev]
    mov [rdi], ax                   ; mac_id
    mov word [rdi + 2], 0           ; version
    mov eax, ctxt_info_end - ctxt_info
    shr eax, 2
    mov [rdi + 4], ax               ; size in DWs

    ; control_flags
    mov dword [rdi + 8], IWL_CTXT_CTRL_FLAGS

    ; rbd_cfg at offset 24
    call iwl_cmd_rx_free_addr
    mov [rdi + 24], rax
    call iwl_cmd_rx_used_addr
    mov [rdi + 32], rax
    call iwl_cmd_rx_status_addr
    mov [rdi + 40], rax

    ; hcmd_cfg at offset 48
    call iwl_cmd_tx_tfd_addr
    mov [rdi + 48], rax
    mov byte [rdi + 56], 5          ; log2(32)=5

    ; Fill dram maps from firmware sections (alternate LMAC/UMAC heuristic)
    call iwl_fw_sec_count
    mov r12d, eax
    xor ebx, ebx
    xor esi, esi                    ; lmac idx
    xor edi, edi                    ; umac idx
.fill_secs:
    cmp ebx, r12d
    jae .secs_done
    mov ecx, ebx
    call iwl_fw_sec_info
    test rax, rax
    jz .next_sec
    test ebx, 1
    jnz .umac
    cmp esi, IWL_MAX_DRAM_ENTRY
    jae .next_sec
    lea rcx, [ctxt_info + 0xC0]
    mov [rcx + rsi * 8], rax
    inc esi
    jmp .next_sec
.umac:
    cmp edi, IWL_MAX_DRAM_ENTRY
    jae .next_sec
    lea rcx, [ctxt_info + 0xC0 + IWL_MAX_DRAM_ENTRY * 8]
    mov [rcx + rdi * 8], rax
    inc edi
.next_sec:
    inc ebx
    jmp .fill_secs
.secs_done:

    ; Gen3 for AX210/AX211-class PCI IDs
    movzx eax, word [iwl_device_id]
    cmp eax, 0x2725
    je .gen3
    cmp eax, 0x7E40
    je .gen3
    cmp eax, 0x51F0
    je .gen3
    cmp eax, 0x51F1
    je .gen3
    cmp eax, 0x54F0
    je .gen3
    cmp eax, 0x7E20
    je .gen3
    mov byte [iwl_gen3], 0
    jmp .ok

.gen3:
    mov byte [iwl_gen3], 1
    call iwl_build_gen3

.ok:
    mov rax, 1
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

iwl_build_gen3:
    push rsi
    push rdi
    lea rdi, [prph_scratch]
    mov rcx, 4096 / 8
    xor eax, eax
    rep stosq
    lea rdi, [ctxt_gen3]
    mov rcx, 256 / 8
    xor eax, eax
    rep stosq

    lea rdi, [prph_scratch]
    mov ax, [iwl_hw_rev]
    mov [rdi], ax
    mov word [rdi + 4], 256
    lea rsi, [ctxt_info + 0xC0]
    lea rdi, [prph_scratch + 64]
    mov rcx, (IWL_MAX_DRAM_ENTRY * 3)
    rep movsq

    lea rdi, [ctxt_gen3]
    mov word [rdi], 1
    mov word [rdi + 2], 64
    lea rax, [prph_info]
    mov [rdi + 8], rax
    lea rax, [prph_scratch]
    mov [rdi + 0x50], rax
    pop rdi
    pop rsi
    ret

iwl_kick_fw_load:
    push rbx
    mov rbx, [iwl_mmio]
    cmp byte [iwl_gen3], 0
    jnz .kick_gen3

    lea rax, [ctxt_info]
    mov [rbx + CSR_CTXT_INFO_BA], eax
    shr rax, 32
    mov [rbx + CSR_CTXT_INFO_BA + 4], eax
    jmp .ok

.kick_gen3:
    lea rax, [ctxt_gen3]
    mov [rbx + CSR_CTXT_INFO_ADDR], eax
    shr rax, 32
    mov [rbx + CSR_CTXT_INFO_ADDR + 4], eax
    mov eax, CSR_AUTO_FUNC_BOOT_ENA | CSR_AUTO_FUNC_INIT
    mov [rbx + CSR_CTXT_INFO_BOOT_CTRL], eax

.ok:
    lea rcx, [msg_kick]
    call con_puts
    lea rcx, [msg_kick]
    call serial_puts
    mov rax, 1
    pop rbx
    ret

iwl_driver_get_mac:
    push rsi
    push rdi
    push rcx
    lea rsi, [iwl_mac]
    mov rdi, rcx
    mov rcx, 6
    rep movsb
    pop rcx
    pop rdi
    pop rsi
    ret

iwl_is_associated:
    movzx eax, byte [iwl_assoc_flag]
    ret

; RCX = Ethernet frame, RDX = length
iwl_driver_send:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov rsi, rcx
    mov r12, rdx

    cmp byte [iwl_ready], 0
    jz .done
    cmp byte [iwl_assoc_flag], 0
    jz .done
    test r12, r12
    jz .done
    cmp r12, 1514
    jbe .len_ok
    mov r12, 1514
.len_ok:

    ; TX_CMD id 0x1c ??? payload: 64-byte stub header + frame
    lea rdi, [tx_frame_buf]
    mov rcx, 64
    xor eax, eax
    rep stosb
    lea rdi, [tx_frame_buf + 64]
    mov rcx, r12
    rep movsb

    mov ecx, 0x1c
    lea rdx, [tx_frame_buf]
    mov r8, r12
    add r8, 64
    xor r9, r9
    call wifi_send_cmd

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; RCX = dest -> RAX = len
iwl_driver_recv:
    push rbx
    push rsi
    push rdi
    mov rbx, rcx
    cmp byte [iwl_ready], 0
    jz .empty
    call iwl_cmd_poll_rx
    test rax, rax
    jz .empty
    mov edx, eax
    call iwl_get_last_rx
    mov rsi, rax
    mov rdi, rbx
    mov rcx, rdx
    cmp rcx, 2048
    jbe .copy
    mov rcx, 1514
.copy:
    mov rax, rcx
    rep movsb
    jmp .done
.empty:
    xor rax, rax
.done:
    pop rdi
    pop rsi
    pop rbx
    ret

section .data
align 8
iwl_mmio dq 0
iwl_mmio_ptr dq 0
iwl_bdf dd 0
iwl_hw_rev dd 0
iwl_pci_id dd 0
iwl_device_id dw 0
iwl_ready db 0
iwl_gen3 db 0
iwl_mac db 0x00, 0x72, 0xEE, 0x86, 0xBC, 0x53

align 8
iwl_ops_table:
    dq iwl_wifi_scan
    dq iwl_wifi_connect
    dq iwl_is_associated

msg_iwl_init db "Net: Intel iwlwifi bring-up...", 13, 10, 0
msg_iwl_bar  db "Net: iwlwifi MMIO BAR=0x", 0
msg_iwl_mapfail db "Net: iwlwifi MMIO map failed.", 13, 10, 0
msg_iwl_rev  db "Net: iwlwifi HW_REV=0x", 0
msg_iwl_ok   db "Net: iwlwifi ready (ALIVE). Use wifi_config for SSID.", 13, 10, 0
msg_iwl_fail db "Net: iwlwifi bring-up failed.", 13, 10, 0
iwl_msg_crlf db 13, 10, 0
msg_kick     db "WiFi: Context info programmed; waiting for ALIVE...", 13, 10, 0

section .bss
alignb 4096
ctxt_info resb 4096
ctxt_info_end:
alignb 4096
prph_scratch resb 4096
alignb 64
ctxt_gen3 resb 256
prph_info resb 64
alignb 16
tx_frame_buf resb 2048
