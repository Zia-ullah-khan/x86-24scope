; ==============================================================================
; x86-24scope OS - Intel iwlwifi Driver (multi-device AX/AC family)
; Supports many PCI IDs via pci.asm table. Full firmware/DMA bring-up still
; requires an on-disk firmware blob; until then we report status and fail
; cleanly so netdev can fall back.
; ==============================================================================
bits 64
default rel

section .text

global iwl_driver_init
global iwl_driver_send
global iwl_driver_recv
global iwl_driver_get_mac

extern con_puts
extern serial_puts
extern con_put_hex
extern con_newline
extern serial_put_hex
extern sleep_ms
extern wifi_load_firmware
extern wifi_send_cmd
extern fat32_open
extern fat32_read

; CSR offsets (iwlwifi)
CSR_HW_IF_CONFIG_REG equ 0x000
CSR_INT              equ 0x008
CSR_INT_MASK         equ 0x00C
CSR_FH_INT_STATUS    equ 0x010
CSR_GPIO_IN          equ 0x018
CSR_RESET            equ 0x020
CSR_GP_CNTRL         equ 0x024
CSR_HW_REV           equ 0x028
CSR_EEPROM_REG       equ 0x02C

CSR_RESET_SW_RESET   equ 0x00000080
CSR_GP_CNTRL_INIT_DONE equ 0x00000004

; RCX = BAR, EDX = BDF
; RAX = 1 success, 0 fail (netdev falls back to loopback)
iwl_driver_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi

    mov [iwl_mmio], rcx
    mov [iwl_bdf], edx

    lea rcx, [msg_iwl_init]
    call con_puts
    lea rcx, [msg_iwl_init]
    call serial_puts

    ; Metal / no-firmware path: do not poke hardware. Laptops often have
    ; iwlwifi PCI devices that hang INIT_DONE without a firmware blob.
    lea rcx, [msg_fw_try]
    call con_puts
    lea rcx, [msg_fw_try]
    call serial_puts

    lea rcx, [fw_path]
    call fat32_open
    test rax, rax
    jz .no_firmware

    mov rbx, [iwl_mmio]
    test rbx, rbx
    jz .fail

    ; Read HW revision
    mov eax, [rbx + CSR_HW_REV]
    mov [iwl_hw_rev], eax
    lea rcx, [msg_iwl_rev]
    call con_puts
    lea rcx, [msg_iwl_rev]
    call serial_puts
    mov ecx, [iwl_hw_rev]
    call con_put_hex
    call con_newline
    mov ecx, [iwl_hw_rev]
    call serial_put_hex
    lea rcx, [msg_nl]
    call serial_puts

    ; Software reset
    mov eax, [rbx + CSR_RESET]
    or eax, CSR_RESET_SW_RESET
    mov [rbx + CSR_RESET], eax
    mov rcx, 10
    call sleep_ms

    ; Clear pending interrupts / mask all
    mov dword [rbx + CSR_INT_MASK], 0
    mov dword [rbx + CSR_INT], 0xFFFFFFFF

    ; Wait for INIT_DONE (mac clock ready) — may fail without power/firmware
    mov eax, [rbx + CSR_GP_CNTRL]
    or eax, CSR_GP_CNTRL_INIT_DONE
    mov [rbx + CSR_GP_CNTRL], eax

    mov ecx, 100
.wait_init:
    mov eax, [rbx + CSR_GP_CNTRL]
    test eax, 0x00000001            ; MAC_CLOCK_READY-ish on some gens
    jnz .clock_ok
    push rcx
    mov rcx, 5
    call sleep_ms
    pop rcx
    loop .wait_init

.clock_ok:
    ; Attempt firmware load from FAT: \EFI\FIRMWARE\IWLWIFI.UC
    lea rcx, [msg_fw_try]
    call con_puts
    lea rcx, [msg_fw_try]
    call serial_puts

    lea rcx, [fw_path]
    call fat32_open
    test rax, rax
    jz .no_firmware

    ; File exists — call firmware loader stub (returns non-zero if OK)
    call wifi_load_firmware
    test rax, rax
    jz .no_firmware

    lea rcx, [msg_fw_ok]
    call con_puts
    lea rcx, [msg_fw_ok]
    call serial_puts

    mov byte [iwl_ready], 1
    mov rax, 1
    jmp .done

.no_firmware:
    lea rcx, [msg_fw_missing]
    call con_puts
    lea rcx, [msg_fw_missing]
    call serial_puts
    ; Hardware present but not usable without FW — fail so loopback takes over
    ; (avoids claiming a broken NIC)
    jmp .fail

.fail:
    mov byte [iwl_ready], 0
    xor rax, rax

.done:
    pop rdi
    pop rsi
    pop rbx
    pop rbp
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

iwl_driver_send:
    ; Without firmware/DMA rings, drop
    cmp byte [iwl_ready], 0
    jz .drop
    ; Future: enqueue TFD
.drop:
    ret

iwl_driver_recv:
    xor rax, rax
    cmp byte [iwl_ready], 0
    jz .done
    ; Future: poll RBD
.done:
    ret

section .data
align 8
iwl_mmio dq 0
iwl_bdf dd 0
iwl_hw_rev dd 0
iwl_ready db 0
iwl_mac db 0x00, 0x72, 0xEE, 0x86, 0xBC, 0x53

fw_path db "\EFI\FIRMWARE\IWLWIFI.UC", 0

msg_iwl_init db "Net: Intel iwlwifi device found, bringing up...", 13, 10, 0
msg_iwl_rev  db "Net: iwlwifi HW_REV = 0x", 0
msg_fw_try   db "Net: Looking for firmware \EFI\FIRMWARE\IWLWIFI.UC ...", 13, 10, 0
msg_fw_ok    db "Net: iwlwifi firmware loaded.", 13, 10, 0
msg_fw_missing db "Net: iwlwifi firmware missing — WiFi HW idle (use e1000 in QEMU).", 13, 10, 0
msg_nl db 13, 10, 0
