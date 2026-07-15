; ==============================================================================
; x86-24scope OS - Intel e1000 (82540EM / 82545EM) Ethernet Driver
; Used in QEMU for host <-> guest TCP (HTTP on port 8091)
; ==============================================================================
bits 64
default rel

section .text

global e1000_driver_init
global e1000_driver_send
global e1000_driver_recv
global e1000_driver_get_mac
global e1000_is_qemu
global e1000_dump_stats

extern con_puts
extern serial_puts
extern con_put_hex
extern con_newline
extern serial_put_hex
extern sleep_ms
extern pmm_alloc_page
extern vmm_map_mmio
extern pci_read_config
extern pci_write_config

; MMIO register offsets
E1000_CTRL     equ 0x0000
E1000_STATUS   equ 0x0008
E1000_EECD     equ 0x0010
E1000_EERD     equ 0x0014
E1000_CTRL_EXT equ 0x0018
E1000_MDIC     equ 0x0020
E1000_FEXTNVM3 equ 0x003C
E1000_ICR      equ 0x00C0
E1000_IMS      equ 0x00D0
E1000_IMC      equ 0x00D8
E1000_RCTL     equ 0x0100
E1000_TCTL     equ 0x0400
E1000_TIPG     equ 0x0410
E1000_KABGTXD  equ 0x3004
E1000_RDBAL    equ 0x2800
E1000_RDBAH    equ 0x2804
E1000_RDLEN    equ 0x2808
E1000_RDH      equ 0x2810
E1000_RDT      equ 0x2818
E1000_RXDCTL   equ 0x2828
E1000_TDBAL    equ 0x3800
E1000_TDBAH    equ 0x3804
E1000_TDLEN    equ 0x3808
E1000_TDH      equ 0x3810
E1000_TDT      equ 0x3818
E1000_TIDV     equ 0x3820
E1000_TXDCTL   equ 0x3828
E1000_TARC0    equ 0x3840
E1000_TXDCTL1  equ 0x3928
E1000_TARC1    equ 0x3940
E1000_GPRC     equ 0x4074
E1000_GPTC     equ 0x4080
E1000_TPT      equ 0x40D4
E1000_RXCSUM   equ 0x5000
E1000_RFCTL    equ 0x5008
E1000_MTA      equ 0x5200
E1000_RAL0     equ 0x5400
E1000_RAH0     equ 0x5404
E1000_WUC      equ 0x5800
E1000_WUFC     equ 0x5808
E1000_MANC     equ 0x5820
E1000_FEXTNVM7 equ 0x00E4
E1000_FEXTNVM9 equ 0x5BB4
E1000_FEXTNVM11 equ 0x5BBC
E1000_EXTCNF_CTRL equ 0x0F00
E1000_PHY_CTRL equ 0x0F10
E1000_PBECCSTS equ 0x100C
E1000_IOSFPC   equ 0x0F28
E1000_SWSM     equ 0x5B50
E1000_FWSM     equ 0x5B54

; CTRL bits
CTRL_ASDE      equ 0x20
CTRL_SLU       equ 0x40
CTRL_GIO_MASTER_DISABLE equ 0x4
CTRL_LANPHYPC_OVERRIDE equ 0x10000
CTRL_LANPHYPC_VALUE    equ 0x20000
CTRL_RST       equ 0x04000000
CTRL_PHY_RST   equ 0x80000000
CTRL_MEHE      equ 0x80000

; CTRL_EXT
CTRL_EXT_LPCD        equ 0x4
CTRL_EXT_FORCE_SMBUS equ 0x800
CTRL_EXT_RO_DIS      equ 0x20000
CTRL_EXT_DRV_LOAD    equ 0x10000000
CTRL_EXT_BIT22       equ (1 << 22)
ICH_FWSM_PCIM2PCI    equ 0x01000000
ICH_FWSM_PCIM2PCI_COUNT equ 2000
KABGTXD_BGSQLBIAS    equ 0x00050000
PCI_CAP_PTR          equ 0x34
PCI_CAP_ID_PM        equ 0x01
PCI_EXP_CAP_ID       equ 0x10
PCI_EXP_DEVCTL_FLR   equ 0x8000
PCI_EXP_LNKCTL_ASPMC equ 0x3          ; ASPM L0s|L1 in Link Control
PCI_PM_CTRL          equ 0x4          ; offset within PM cap
PCI_PM_CTRL_STATE_MASK equ 0x3
PCI_PM_CTRL_STATE_D3HOT equ 0x3

; STATUS bits
STATUS_LU            equ 0x2
STATUS_LAN_INIT_DONE equ 0x200
STATUS_PHYRA         equ 0x400

; EXTCNF_CTRL
EXTCNF_SWFLAG        equ 0x20
EXTCNF_GATE_PHY_CFG  equ 0x80

; FEXTNVM3
FEXTNVM3_PHY_CFG_COUNTER_MASK  equ 0x0C000000
FEXTNVM3_PHY_CFG_COUNTER_50MS  equ 0x08000000

; PHY_CTRL (MAC CSR) — clear LPLU / gig disable for link
PHY_CTRL_D0A_LPLU        equ 0x2
PHY_CTRL_NOND0A_LPLU     equ 0x4
PHY_CTRL_NOND0A_GBE_DIS  equ 0x8
PHY_CTRL_GBE_DISABLE     equ 0x40

; RFCTL / MANC / SWSM
RFCTL_NFSW_DIS           equ 0x40
RFCTL_NFSR_DIS           equ 0x80
MANC_ARP_EN              equ 0x2000
MANC_EN_MAC_ADDR_FILTER  equ 0x100000
MANC_EN_MNG2HOST         equ 0x200000
SWSM_DRV_LOAD            equ 0x8
TXDCTL_FULL_WB           equ 0x01010000
TXDCTL_MAX_PREFETCH      equ 0x0100001F
TXDCTL_BIT22             equ (1 << 22)
TARC0_MULTIQ_3           equ 0x30000000
TARC0_MULTIQ_2           equ 0x20000000
FEXTNVM7_SIDE_CLK_UNGATE equ 0x4
FEXTNVM9_CLKGATE_DIS     equ 0x800
FEXTNVM9_CLKREQ_DIS      equ 0x1000
FEXTNVM11_DISABLE_MULR   equ 0x2000
PBECCSTS_ECC_ENABLE      equ 0x10000
PCICFG_DESC_RING_STATUS  equ 0xE4
FLUSH_DESC_REQUIRED      equ 0x100
TCTL_RTLC                equ 0x01000000

; MDIC / PHY
MDIC_REG_SHIFT equ 16
MDIC_PHY_SHIFT equ 21
MDIC_OP_WRITE  equ 0x04000000
MDIC_OP_READ   equ 0x08000000
MDIC_READY     equ 0x10000000
MDIC_ERROR     equ 0x40000000
PHY_ADDR       equ 1
PHY_BMCR       equ 0
PHY_PAGE_SELECT equ 31
IGP_PAGE_SHIFT equ 5
BMCR_ANENABLE  equ 0x1000
BMCR_ANRESTART equ 0x0200
HV_OEM_PAGE    equ 768
HV_OEM_REG     equ 25
HV_OEM_LPLU    equ 0x0004
HV_OEM_GBE_DIS equ 0x0040
HV_OEM_RESTART_AN equ 0x0400
ICH_FWSM_FW_VALID equ 0x8000

; RCTL bits
RCTL_EN        equ 0x00000002
RCTL_SBP       equ 0x00000004
RCTL_UPE       equ 0x00000008
RCTL_MPE       equ 0x00000010
RCTL_LBM_NONE  equ 0x00000000
RCTL_RDMTS_HALF equ 0x00000000
RCTL_BAM       equ 0x00008000
RCTL_BSIZE_2048 equ 0x00000000
RCTL_SECRC     equ 0x04000000

; TCTL bits
TCTL_EN        equ 0x00000002
TCTL_PSP       equ 0x00000008
TCTL_CT_SHIFT  equ 4
TCTL_COLD_SHIFT equ 12

NUM_RX_DESC    equ 32
NUM_TX_DESC    equ 32
RX_BUF_SIZE    equ 2048

; RCX = BAR physical, EDX = BDF
; Returns RAX = 1 on success, 0 on failure
e1000_driver_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov [e1000_mmio], rcx
    mov [e1000_bdf], edx

    ; Unpack BDF and read PCI ID (vendor:device)
    mov eax, edx
    movzx r8d, al                   ; function
    mov ecx, eax
    shr ecx, 8
    movzx edx, cl                   ; device
    shr eax, 16
    movzx ecx, al                   ; bus
    mov r9, 0
    call pci_read_config
    mov [e1000_pci_id], eax
    shr eax, 16
    mov [e1000_device_id], ax

    lea rcx, [msg_e1000_init]
    call con_puts
    lea rcx, [msg_e1000_init]
    call serial_puts
    lea rcx, [msg_e1000_devid]
    call con_puts
    movzx ecx, word [e1000_device_id]
    call con_put_hex
    call con_newline
    cmp word [e1000_device_id], 0x0D4E
    jne .after_chip_name
    lea rcx, [msg_e1000_i219]
    call con_puts
    lea rcx, [msg_e1000_i219]
    call serial_puts
.after_chip_name:
    mov rbx, [e1000_mmio]
    test rbx, rbx
    jz .fail

    ; Map BAR for metal (BARs may sit above the 4GB identity map)
    mov rcx, rbx
    mov rdx, 0x200000
    call vmm_map_mmio

    ; Read MAC before any reset (RAL cleared by RST on I219)
    call e1000_read_mac

    ; NOTE: PCI FLR skipped — I219 (PCH-integrated) freezes the platform.
    mov rbx, [e1000_mmio]
    call e1000_pci_set_master
    call e1000_pci_disable_aspm

    ; QEMU needs MAC soft-reset. On I219, CTRL.RST after a hang often
    ; leaves the TX DMA unit dead (TDH stuck at 0) — skip it on metal.
    cmp word [e1000_device_id], 0x100E
    je .do_soft_rst
    cmp word [e1000_device_id], 0x100F
    je .do_soft_rst
    lea rcx, [msg_e1000_skiprst]
    call con_puts
    jmp .after_rst

.do_soft_rst:
    call e1000_mmio_wait_me
    mov eax, [rbx + E1000_CTRL]
    or eax, CTRL_GIO_MASTER_DISABLE
    call e1000_ew32_ctrl
    mov rcx, 10
    call sleep_ms
    call e1000_mmio_wait_me
    mov eax, [rbx + E1000_CTRL]
    and eax, ~CTRL_GIO_MASTER_DISABLE
    or eax, CTRL_RST
    call e1000_ew32_ctrl
    ; Do NOT MMIO-read during reset window — hangs PCIe bus on I219
    mov rcx, 100
    call sleep_ms
    call e1000_pci_set_master

.after_rst:

    ; ICH reset follow-up
    call e1000_mmio_wait_me
    mov eax, [rbx + E1000_KABGTXD]
    or eax, KABGTXD_BGSQLBIAS
    mov ecx, E1000_KABGTXD
    call e1000_ew32

    ; Claim NIC + program TARC/IOSFPC BEFORE hang-flush and PHY.
    ; IFCS-only can advance TDH without TARC; EOP (real packets) needs it.
    call e1000_take_ownership
    call e1000_init_hw_bits

    ; Flush TX hang only AFTER TARC is correct (then skip D3/D0 if TDH moves)
    call e1000_i219_recover_tx
    call e1000_pci_set_master
    call e1000_pci_disable_aspm

    ; Re-program MAC into RAL after reset
    mov eax, dword [e1000_mac]
    mov ecx, E1000_RAL0
    call e1000_ew32
    movzx eax, word [e1000_mac + 4]
    or eax, 0x80000000
    mov ecx, E1000_RAH0
    call e1000_ew32

    ; Metal e1000e/I219: take PHY out of reset and force power-on
    call e1000_phy_bringup

    ; Set link up + auto-speed detect (TX enable comes AFTER link)
    call e1000_mmio_wait_me
    mov eax, [rbx + E1000_CTRL]
    and eax, ~(CTRL_PHY_RST | CTRL_GIO_MASTER_DISABLE)
    or eax, CTRL_SLU | CTRL_ASDE
    call e1000_ew32_ctrl

    ; Disable interrupts
    mov eax, 0xFFFFFFFF
    mov ecx, E1000_IMC
    call e1000_ew32
    mov eax, [rbx + E1000_ICR]

    ; Clear multicast table
    xor r8d, r8d
.clear_mta:
    call e1000_mmio_wait_me
    mov dword [rbx + E1000_MTA + r8 * 4], 0
    inc r8d
    cmp r8d, 128
    jb .clear_mta

    call e1000_read_mac
    call e1000_setup_rx
    test rax, rax
    jz .fail
    call e1000_setup_tx
    test rax, rax
    jz .fail

    ; Match the working flush programming order:
    ;   rings already set by setup_tx → TXDCTL → TIPG → TCTL (EN later on link)
    mov eax, 0x00602008
    mov ecx, E1000_TIPG
    call e1000_ew32
    mov eax, TXDCTL_FULL_WB | TXDCTL_BIT22
    mov ecx, E1000_TXDCTL
    call e1000_ew32
    mov ecx, E1000_TXDCTL1
    call e1000_ew32
    mov eax, TCTL_PSP | TCTL_RTLC
    or eax, (15 << TCTL_CT_SHIFT)
    or eax, (63 << TCTL_COLD_SHIFT)
    mov ecx, E1000_TCTL
    call e1000_ew32

    ; Enable RX only for now
    mov eax, RCTL_EN | RCTL_UPE | RCTL_MPE | RCTL_BAM | RCTL_BSIZE_2048 | RCTL_SECRC
    mov ecx, E1000_RCTL
    call e1000_ew32
    mov eax, NUM_RX_DESC - 1
    mov ecx, E1000_RDT
    call e1000_ew32

    ; Print MAC so we can verify UEFI/RAL vs synthetic
    lea rcx, [msg_e1000_mac]
    call con_puts
    movzx ecx, byte [e1000_mac]
    call con_put_hex
    lea rcx, [msg_colon]
    call con_puts
    movzx ecx, byte [e1000_mac + 1]
    call con_put_hex
    lea rcx, [msg_colon]
    call con_puts
    movzx ecx, byte [e1000_mac + 2]
    call con_put_hex
    lea rcx, [msg_colon]
    call con_puts
    movzx ecx, byte [e1000_mac + 3]
    call con_put_hex
    lea rcx, [msg_colon]
    call con_puts
    movzx ecx, byte [e1000_mac + 4]
    call con_put_hex
    lea rcx, [msg_colon]
    call con_puts
    movzx ecx, byte [e1000_mac + 5]
    call con_put_hex
    call con_newline

    ; Wait up to ~5s for link (STATUS.LU)
    mov ecx, 250
.wait_link:
    mov eax, [rbx + E1000_STATUS]
    test eax, STATUS_LU
    jnz .link_up
    push rcx
    mov rcx, 20
    call sleep_ms
    pop rcx
    loop .wait_link

    lea rcx, [msg_e1000_nolink]
    call con_puts
    lea rcx, [msg_e1000_nolink]
    call serial_puts
    lea rcx, [msg_e1000_status]
    call con_puts
    mov eax, [rbx + E1000_STATUS]
    mov rcx, rax
    call con_put_hex
    call con_newline
    mov eax, [rbx + E1000_STATUS]
    test eax, STATUS_PHYRA
    jz .nolink_done
    lea rcx, [msg_e1000_phyra]
    call con_puts
    lea rcx, [msg_e1000_phyra]
    call serial_puts
.nolink_done:
    mov byte [e1000_have_link], 0
    mov rax, 1                      ; init OK; DHCP may still fail without cable
    jmp .done

.link_up:
    mov byte [e1000_have_link], 1

    ; Linux: enable TX only after link is up; adjust TARC speed bit
    mov eax, [rbx + E1000_STATUS]
    and eax, 0xC0                    ; SPEED field
    cmp eax, 0x80                    ; 1000 Mbps?
    je .tarc_ok
    call e1000_mmio_wait_me
    mov eax, [rbx + E1000_TARC0]
    and eax, ~(1 << 21)
    mov [rbx + E1000_TARC0], eax
.tarc_ok:
    ; Same order as working flush: reset heads → TIPG → TXDCTL → TCTL.EN → doorbell
    call e1000_mmio_wait_me
    mov eax, [rbx + E1000_TCTL]
    and eax, ~TCTL_EN
    mov [rbx + E1000_TCTL], eax
    mov dword [rbx + E1000_TDH], 0
    mov dword [rbx + E1000_TDT], 0
    mov dword [tx_cur], 0
    mov dword [rbx + E1000_TIDV], 0
    mov dword [rbx + E1000_TIPG], 0x00602008
    mov eax, TXDCTL_FULL_WB | TXDCTL_BIT22
    mov [rbx + E1000_TXDCTL], eax
    mov [rbx + E1000_TXDCTL1], eax
    mov eax, [rbx + E1000_TCTL]
    or eax, TCTL_EN
    mov [rbx + E1000_TCTL], eax
    mov eax, [rbx + E1000_STATUS]
    sfence

    ; Smoke-test TX on the real ring before DHCP
    call e1000_tx_probe
    lea rcx, [msg_e1000_probe]
    call con_puts
    movzx ecx, word [e1000_probe_tdh]
    call con_put_hex
    call con_newline
    lea rcx, [msg_e1000_tarc]
    call con_puts
    mov eax, [rbx + E1000_TARC0]
    mov rcx, rax
    call con_put_hex
    call con_newline

    lea rcx, [msg_e1000_txdctl]
    call con_puts
    mov eax, [rbx + E1000_TXDCTL]
    mov rcx, rax
    call con_put_hex
    call con_newline
    lea rcx, [msg_e1000_tctl_diag]
    call con_puts
    mov eax, [rbx + E1000_TCTL]
    mov rcx, rax
    call con_put_hex
    call con_newline

    ; Reprint recover results here (early messages scroll off under DHCP spam)
    lea rcx, [msg_e1000_recap]
    call con_puts
    movzx ecx, word [e1000_flush_tdh]
    call con_put_hex
    lea rcx, [msg_slash]
    call con_puts
    mov eax, [e1000_hang_stat]
    mov rcx, rax
    call con_put_hex
    call con_newline
    lea rcx, [msg_e1000_tdbal]
    call con_puts
    mov rax, [tx_ring_phys]
    mov rcx, rax
    call con_put_hex
    call con_newline

    lea rcx, [msg_e1000_ok]
    call con_puts
    lea rcx, [msg_e1000_ok]
    call serial_puts
    mov rax, 1
    jmp .done

.fail:
    lea rcx, [msg_e1000_fail]
    call con_puts
    lea rcx, [msg_e1000_fail]
    call serial_puts
    xor rax, rax

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; Claim device from ME/firmware and open host packet path
; RBX = mmio
e1000_take_ownership:
    push rax

    mov eax, [rbx + E1000_CTRL_EXT]
    or eax, CTRL_EXT_DRV_LOAD | CTRL_EXT_RO_DIS | CTRL_EXT_BIT22
    and eax, ~CTRL_EXT_FORCE_SMBUS
    mov [rbx + E1000_CTRL_EXT], eax

    mov eax, [rbx + E1000_SWSM]
    or eax, SWSM_DRV_LOAD
    mov [rbx + E1000_SWSM], eax

    ; SPT/CNP clock ungates (needed for reliable TX on I219)
    mov eax, [rbx + E1000_FEXTNVM7]
    or eax, FEXTNVM7_SIDE_CLK_UNGATE
    mov [rbx + E1000_FEXTNVM7], eax
    mov eax, [rbx + E1000_FEXTNVM9]
    or eax, FEXTNVM9_CLKGATE_DIS | FEXTNVM9_CLKREQ_DIS
    mov [rbx + E1000_FEXTNVM9], eax

    mov dword [rbx + E1000_RXCSUM], 0
    mov eax, [rbx + E1000_RFCTL]
    or eax, RFCTL_NFSW_DIS | RFCTL_NFSR_DIS
    mov [rbx + E1000_RFCTL], eax

    mov dword [rbx + E1000_WUC], 0
    mov dword [rbx + E1000_WUFC], 0

    mov eax, [rbx + E1000_MANC]
    and eax, ~(MANC_ARP_EN | MANC_EN_MAC_ADDR_FILTER)
    or eax, MANC_EN_MNG2HOST
    mov [rbx + E1000_MANC], eax

    mov eax, dword [e1000_mac]
    mov [rbx + E1000_RAL0], eax
    movzx eax, word [e1000_mac + 4]
    or eax, 0x80000000
    mov [rbx + E1000_RAH0], eax

    pop rax
    ret

; Linux e1000_initialize_hw_bits_ich8lan (subset for I219 TX)
e1000_init_hw_bits:
    push rax

    ; SPT/KBL Si errata: limit outstanding TX DMA requests (avoids hangs)
    mov eax, [rbx + E1000_IOSFPC]
    or eax, 1
    mov [rbx + E1000_IOSFPC], eax

    mov eax, [rbx + E1000_TARC0]
    or eax, (1 << 0) | (1 << 21) | (1 << 23) | (1 << 24) | (1 << 26) | (1 << 27)
    and eax, ~TARC0_MULTIQ_3
    or eax, TARC0_MULTIQ_2            ; clear bit28, set bit29
    mov [rbx + E1000_TARC0], eax

    mov eax, [rbx + E1000_TARC1]
    or eax, (1 << 0) | (1 << 24) | (1 << 26) | (1 << 28) | (1 << 30)
    mov [rbx + E1000_TARC1], eax

    ; ECC + MEHE on LPT and newer (I219 included)
    mov eax, [rbx + E1000_PBECCSTS]
    or eax, PBECCSTS_ECC_ENABLE
    mov [rbx + E1000_PBECCSTS], eax
    mov eax, [rbx + E1000_CTRL]
    or eax, CTRL_MEHE
    mov [rbx + E1000_CTRL], eax

    pop rax
    ret

; Wait if ME is accessing MAC CSR (FWSM.PCIM2PCI)
e1000_mmio_wait_me:
    push rax
    push rcx
    mov ecx, ICH_FWSM_PCIM2PCI_COUNT
.wait:
    mov eax, [rbx + E1000_FWSM]
    test eax, ICH_FWSM_PCIM2PCI
    jz .ok
    pause
    dec ecx
    jnz .wait
.ok:
    pop rcx
    pop rax
    ret

; ECX = register offset, EAX = value, RBX = mmio
e1000_ew32:
    push rax
    call e1000_mmio_wait_me
    pop rax
    mov [rbx + rcx], eax
    ret

; EAX = CTRL value
e1000_ew32_ctrl:
    push rcx
    mov ecx, E1000_CTRL
    call e1000_ew32
    pop rcx
    ret

; Re-enable PCI Memory Space + Bus Master for e1000_bdf (preserves all regs except rax)
e1000_pci_set_master:
    push rbx
    push rcx
    push rdx
    push r8
    push r9

    mov eax, [e1000_bdf]
    movzx r8d, al                   ; function
    mov ecx, eax
    shr ecx, 8
    movzx edx, cl                   ; device
    shr eax, 16
    movzx ecx, al                   ; bus
    mov r9, 0x04
    push rcx
    push rdx
    push r8
    call pci_read_config
    pop r8
    pop rdx
    pop rcx
    or eax, 0x06                    ; Memory Space | Bus Master
    mov r9, 0x04
    push rax
    sub rsp, 32
    call pci_write_config
    add rsp, 40

    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; PCI Function Level Reset — only reliable way to clear I219 TX unit hang
e1000_pci_flr:
    push rax
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    cmp word [e1000_device_id], 0x100E
    je .done
    cmp word [e1000_device_id], 0x100F
    je .done

    lea rcx, [msg_e1000_flr]
    call con_puts

    ; Unpack BDF
    mov eax, [e1000_bdf]
    movzx r11d, al                  ; func
    mov ecx, eax
    shr ecx, 8
    movzx r10d, cl                  ; dev
    shr eax, 16
    movzx r9d, al                   ; bus (keep in r9d awkwardly)
    ; Use: rcx=bus, rdx=dev, r8=func
    mov ecx, r9d
    mov edx, r10d
    mov r8d, r11d

    ; Find PCIe capability
    mov r9, PCI_CAP_PTR
    push rcx
    push rdx
    push r8
    call pci_read_config
    pop r8
    pop rdx
    pop rcx
    movzx eax, al                   ; cap pointer
    test eax, eax
    jz .reenable

.cap_walk:
    and eax, 0xFC
    jz .reenable
    mov r9, rax
    push rax
    push rcx
    push rdx
    push r8
    call pci_read_config
    pop r8
    pop rdx
    pop rcx
    pop r9                          ; current cap offset
    cmp al, PCI_EXP_CAP_ID
    je .got_pcie
    movzx eax, ah                   ; next ptr
    jmp .cap_walk

.got_pcie:
    ; Device Control at cap+8, set FLR bit 15
    lea r9, [r9 + 8]
    and r9, 0xFC
    push rcx
    push rdx
    push r8
    push r9
    call pci_read_config
    pop r9
    pop r8
    pop rdx
    pop rcx
    or eax, PCI_EXP_DEVCTL_FLR
    push rax
    sub rsp, 32
    call pci_write_config
    add rsp, 40

    mov rcx, 100
    call sleep_ms

.reenable:
    ; Restore Memory Space + Bus Master
    mov eax, [e1000_bdf]
    movzx r8d, al
    mov ecx, eax
    shr ecx, 8
    movzx edx, cl
    shr eax, 16
    movzx ecx, al
    mov r9, 0x04
    push rcx
    push rdx
    push r8
    call pci_read_config
    pop r8
    pop rdx
    pop rcx
    or eax, 0x06
    mov r9, 0x04
    push rax
    sub rsp, 32
    call pci_write_config
    add rsp, 40

.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rax
    ret

; Unpack e1000_bdf → RCX=bus, RDX=dev, R8=func
e1000_unpack_bdf:
    mov eax, [e1000_bdf]
    movzx r8d, al
    mov ecx, eax
    shr ecx, 8
    movzx edx, cl
    shr eax, 16
    movzx ecx, al
    ret

; Find PCI capability ID in AL. Returns R9=cap offset, CF=1 if missing.
e1000_pci_find_cap:
    push rax
    push rbx
    mov bl, al                      ; wanted ID
    call e1000_unpack_bdf
    mov r9, PCI_CAP_PTR
    push rcx
    push rdx
    push r8
    call pci_read_config
    pop r8
    pop rdx
    pop rcx
    movzx eax, al
.walk:
    and eax, 0xFC
    jz .miss
    mov r9, rax
    push rax
    push rcx
    push rdx
    push r8
    call pci_read_config
    pop r8
    pop rdx
    pop rcx
    pop r9
    cmp al, bl
    je .hit
    movzx eax, ah
    jmp .walk
.hit:
    pop rbx
    pop rax
    clc
    ret
.miss:
    pop rbx
    pop rax
    stc
    ret

; Disable ASPM on I219 — known to stall TX DMA on some PCH parts
e1000_pci_disable_aspm:
    push rax
    push rcx
    push rdx
    push r8
    push r9
    mov al, PCI_EXP_CAP_ID
    call e1000_pci_find_cap
    jc .done
    ; Link Control is at PCIe cap + 0x10
    lea r9, [r9 + 0x10]
    and r9, 0xFC
    call e1000_unpack_bdf
    push rcx
    push rdx
    push r8
    push r9
    call pci_read_config
    pop r9
    pop r8
    pop rdx
    pop rcx
    and eax, ~PCI_EXP_LNKCTL_ASPMC
    push rax
    sub rsp, 32
    call pci_write_config
    add rsp, 40
.done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rax
    ret

; PCI D3hot → D0 power cycle (FLR alternative to clear I219 TX hang)
e1000_pci_pm_cycle:
    push rax
    push rbx
    push rcx
    push rdx
    push r8
    push r9

    lea rcx, [msg_e1000_pm]
    call con_puts

    mov al, PCI_CAP_ID_PM
    call e1000_pci_find_cap
    jc .done

    lea ebx, [r9d + PCI_PM_CTRL]
    and ebx, 0xFC                   ; EBX = PMCSR offset (stable across calls)

    call e1000_unpack_bdf
    mov r9d, ebx
    push rcx
    push rdx
    push r8
    push r9
    call pci_read_config
    pop r9
    pop r8
    pop rdx
    pop rcx

    and eax, ~PCI_PM_CTRL_STATE_MASK
    or eax, PCI_PM_CTRL_STATE_D3HOT
    mov r9d, ebx
    push rax
    sub rsp, 32
    call pci_write_config
    add rsp, 40
    mov rcx, 50
    call sleep_ms

    call e1000_unpack_bdf
    mov r9d, ebx
    push rcx
    push rdx
    push r8
    push r9
    call pci_read_config
    pop r9
    pop r8
    pop rdx
    pop rcx
    and eax, ~PCI_PM_CTRL_STATE_MASK
    mov r9d, ebx
    push rax
    sub rsp, 32
    call pci_write_config
    add rsp, 40
    mov rcx, 20
    call sleep_ms

.done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; Always flush TX ring on I219, then D3/D0 + ASPM off (before CTRL.RST)
; RBX = mmio
e1000_i219_recover_tx:
    push rax
    push rcx
    push rdx
    push r8
    push r9
    push rsi
    push rdi

    cmp word [e1000_device_id], 0x100E
    je .done
    cmp word [e1000_device_id], 0x100F
    je .done

    lea rcx, [msg_e1000_hang]
    call con_puts

    call e1000_mmio_wait_me
    mov eax, [rbx + E1000_FEXTNVM11]
    or eax, FEXTNVM11_DISABLE_MULR
    mov [rbx + E1000_FEXTNVM11], eax

    ; Print hang flag for diagnostics
    call e1000_unpack_bdf
    mov r9, PCICFG_DESC_RING_STATUS
    call pci_read_config
    mov [e1000_hang_stat], eax
    lea rcx, [msg_e1000_hangstat]
    call con_puts
    mov rcx, rax
    call con_put_hex
    call con_newline

    mov word [e1000_flush_tdh], 0

    ; --- Always force a dummy TX drain (Linux flush_tx_ring) ---
    call pmm_alloc_page
    test rax, rax
    jz .force_pm
    mov rsi, rax
    mov rdi, rax
    mov rcx, 4096 / 8
    xor rax, rax
    rep stosq

    mov rax, rsi
    mov [rsi], rax
    ; lower.data = length | (CMD << 24); CMD = IFCS only for flush (Linux)
    mov dword [rsi + 8], 512 | (0x02 << 24)
    mov dword [rsi + 12], 0
    clflush [rsi]
    clflush [rsi + 15]
    sfence

    call e1000_mmio_wait_me
    mov eax, [rbx + E1000_TCTL]
    and eax, ~TCTL_EN
    mov [rbx + E1000_TCTL], eax

    mov rax, rsi
    mov [rbx + E1000_TDBAL], eax
    shr rax, 32
    mov [rbx + E1000_TDBAH], eax
    mov dword [rbx + E1000_TDLEN], 128
    mov dword [rbx + E1000_TDH], 0
    mov dword [rbx + E1000_TDT], 0
    mov dword [rbx + E1000_TIPG], 0x00602008
    mov eax, TXDCTL_FULL_WB | TXDCTL_BIT22
    mov [rbx + E1000_TXDCTL], eax
    mov eax, TCTL_PSP | TCTL_RTLC
    or eax, (15 << TCTL_CT_SHIFT)
    or eax, (63 << TCTL_COLD_SHIFT)
    or eax, TCTL_EN
    mov [rbx + E1000_TCTL], eax
    sfence
    call e1000_mmio_wait_me
    mov dword [rbx + E1000_TDT], 1

    mov ecx, 50
.wait_flush:
    mov eax, [rbx + E1000_TDH]
    test eax, eax
    jnz .flush_ok
    push rcx
    mov rcx, 2
    call sleep_ms
    pop rcx
    loop .wait_flush
.flush_ok:
    mov eax, [rbx + E1000_TDH]
    mov [e1000_flush_tdh], ax
    lea rcx, [msg_e1000_flush_diag]
    call con_puts
    movzx ecx, word [e1000_flush_tdh]
    call con_put_hex
    lea rcx, [msg_slash]
    call con_puts
    movzx eax, byte [rsi + 12]
    mov rcx, rax
    call con_put_hex
    call con_newline

    call e1000_mmio_wait_me
    mov eax, [rbx + E1000_TCTL]
    and eax, ~TCTL_EN
    mov [rbx + E1000_TCTL], eax
    ; Leave TDLEN installed; setup_tx reprograms the real ring next.

    call e1000_pci_disable_aspm

    ; Flush TDH advanced → TX DMA is alive. D3/D0 was killing it again.
    cmp word [e1000_flush_tdh], 0
    jne .skip_pm

.force_pm:
    lea rcx, [msg_e1000_pm_need]
    call con_puts
    call e1000_pci_disable_aspm
    call e1000_pci_pm_cycle
    call e1000_pci_set_master
    mov rbx, [e1000_mmio]
    jmp .done

.skip_pm:
    lea rcx, [msg_e1000_pm_skip]
    call con_puts
    call e1000_pci_set_master

.done:
    pop rdi
    pop rsi
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rax
    ret

; Print GPTC/GPRC (clears on read) — useful when DHCP fails
e1000_dump_stats:
    push rbx
    push rax
    push rcx
    mov rbx, [e1000_mmio]
    test rbx, rbx
    jz .done
    lea rcx, [msg_e1000_gptc]
    call con_puts
    mov eax, [rbx + E1000_GPTC]
    mov rcx, rax
    call con_put_hex
    call con_newline
    lea rcx, [msg_e1000_gprc]
    call con_puts
    mov eax, [rbx + E1000_GPRC]
    mov rcx, rax
    call con_put_hex
    call con_newline
.done:
    pop rcx
    pop rax
    pop rbx
    ret

; Bring PHY out of reset / power-down (ICH/PCH/I219; no-op-ish on QEMU)
; Uses RBX = mmio base
e1000_phy_bringup:
    push rax
    push rcx
    push rdx

    ; QEMU 82540EM does not need PCH PHY gymnastics
    cmp word [e1000_device_id], 0x100E
    je .qemu_simple
    cmp word [e1000_device_id], 0x100F
    je .qemu_simple

    ; Gate automatic PHY config by hardware
    mov eax, [rbx + E1000_EXTCNF_CTRL]
    or eax, EXTCNF_GATE_PHY_CFG
    mov [rbx + E1000_EXTCNF_CTRL], eax

    ; Ensure MAC is not stuck in forced SMBus mode
    mov eax, [rbx + E1000_CTRL_EXT]
    and eax, ~CTRL_EXT_FORCE_SMBUS
    mov [rbx + E1000_CTRL_EXT], eax

    ; FEXTNVM3: 50ms PHY config counter (Linux e1000e)
    mov eax, [rbx + E1000_FEXTNVM3]
    and eax, ~FEXTNVM3_PHY_CFG_COUNTER_MASK
    or eax, FEXTNVM3_PHY_CFG_COUNTER_50MS
    mov [rbx + E1000_FEXTNVM3], eax

    ; Toggle LANPHYPC: OVERRIDE=1, VALUE=0, then drop OVERRIDE
    mov eax, [rbx + E1000_CTRL]
    or eax, CTRL_LANPHYPC_OVERRIDE
    and eax, ~CTRL_LANPHYPC_VALUE
    mov [rbx + E1000_CTRL], eax
    mov rcx, 1
    call sleep_ms
    mov eax, [rbx + E1000_CTRL]
    and eax, ~CTRL_LANPHYPC_OVERRIDE
    mov [rbx + E1000_CTRL], eax

    ; Wait for LCD power-cycle done (CTRL_EXT.LPCD), then settle
    mov ecx, 40
.wait_lpcd:
    mov eax, [rbx + E1000_CTRL_EXT]
    test eax, CTRL_EXT_LPCD
    jnz .lpcd_ok
    push rcx
    mov rcx, 5
    call sleep_ms
    pop rcx
    loop .wait_lpcd
.lpcd_ok:
    mov rcx, 50
    call sleep_ms

    ; Pulse CTRL.PHY_RST
    mov eax, [rbx + E1000_CTRL]
    or eax, CTRL_PHY_RST
    mov [rbx + E1000_CTRL], eax
    mov rcx, 20
    call sleep_ms
    mov eax, [rbx + E1000_CTRL]
    and eax, ~CTRL_PHY_RST
    mov [rbx + E1000_CTRL], eax

    ; Wait for NVM/LAN init done
    mov ecx, 100
.wait_lan_init:
    mov eax, [rbx + E1000_STATUS]
    test eax, STATUS_LAN_INIT_DONE
    jnz .lan_init_ok
    push rcx
    mov rcx, 10
    call sleep_ms
    pop rcx
    loop .wait_lan_init
.lan_init_ok:

    ; PHYRA is sticky — software must clear it by writing STATUS
    mov eax, [rbx + E1000_STATUS]
    and eax, ~STATUS_PHYRA
    mov [rbx + E1000_STATUS], eax

    ; Clear MAC-side LPLU / gig-disable so copper can link
    mov eax, [rbx + E1000_PHY_CTRL]
    and eax, ~(PHY_CTRL_D0A_LPLU | PHY_CTRL_NOND0A_LPLU | PHY_CTRL_NOND0A_GBE_DIS | PHY_CTRL_GBE_DISABLE)
    mov [rbx + E1000_PHY_CTRL], eax

    ; Acquire SWFLAG before MDIO (ME/firmware semaphore)
    call e1000_acquire_swflag
    test rax, rax
    jz .skip_mdio

    ; Restart AN via BMCR
    mov edx, BMCR_ANENABLE | BMCR_ANRESTART
    mov ecx, PHY_BMCR
    call e1000_mdic_write

    ; HV_OEM_BITS (page 768, reg 25): clear LPLU/GBE_DIS, set RESTART_AN
    mov edx, HV_OEM_PAGE << IGP_PAGE_SHIFT
    mov ecx, PHY_PAGE_SELECT
    call e1000_mdic_write
    mov edx, HV_OEM_RESTART_AN
    mov ecx, HV_OEM_REG
    call e1000_mdic_write
    ; Restore page 0
    xor edx, edx
    mov ecx, PHY_PAGE_SELECT
    call e1000_mdic_write

    call e1000_release_swflag
.skip_mdio:

    ; Ungate HW PHY config
    mov eax, [rbx + E1000_EXTCNF_CTRL]
    and eax, ~EXTCNF_GATE_PHY_CFG
    mov [rbx + E1000_EXTCNF_CTRL], eax
    mov rcx, 100
    call sleep_ms
    jmp .done

.qemu_simple:
    mov eax, [rbx + E1000_CTRL]
    and eax, ~CTRL_PHY_RST
    or eax, CTRL_SLU | CTRL_ASDE
    mov [rbx + E1000_CTRL], eax

.done:
    pop rdx
    pop rcx
    pop rax
    ret

; RAX = 1 if SWFLAG acquired
e1000_acquire_swflag:
    push rcx
    push rdx
    mov ecx, 100
.swflag_try:
    mov eax, [rbx + E1000_EXTCNF_CTRL]
    test eax, EXTCNF_SWFLAG
    jnz .swflag_wait
    or eax, EXTCNF_SWFLAG
    mov [rbx + E1000_EXTCNF_CTRL], eax
    mov eax, [rbx + E1000_EXTCNF_CTRL]
    test eax, EXTCNF_SWFLAG
    jnz .swflag_ok
.swflag_wait:
    push rcx
    mov rcx, 10
    call sleep_ms
    pop rcx
    loop .swflag_try
    xor eax, eax
    pop rdx
    pop rcx
    ret
.swflag_ok:
    mov eax, 1
    pop rdx
    pop rcx
    ret

e1000_release_swflag:
    push rax
    mov eax, [rbx + E1000_EXTCNF_CTRL]
    and eax, ~EXTCNF_SWFLAG
    mov [rbx + E1000_EXTCNF_CTRL], eax
    pop rax
    ret

; ECX = PHY register (low 5 bits), EDX = 16-bit data. RBX = mmio. RAX=1 ok.
e1000_mdic_write:
    push rcx
    mov eax, edx
    and eax, 0xFFFF
    and ecx, 0x1F
    shl ecx, MDIC_REG_SHIFT
    or eax, ecx
    mov ecx, PHY_ADDR
    shl ecx, MDIC_PHY_SHIFT
    or eax, ecx
    or eax, MDIC_OP_WRITE
    mov [rbx + E1000_MDIC], eax

    mov ecx, 1000
.wait_mdic:
    mov eax, [rbx + E1000_MDIC]
    test eax, MDIC_READY
    jnz .mdic_done
    push rcx
    mov rcx, 1
    call sleep_ms
    pop rcx
    loop .wait_mdic
    xor eax, eax
    pop rcx
    ret
.mdic_done:
    test eax, MDIC_ERROR
    jnz .mdic_err
    mov eax, 1
    pop rcx
    ret
.mdic_err:
    xor eax, eax
    pop rcx
    ret

e1000_read_mac:
    push rbx
    push rsi
    mov rbx, [e1000_mmio]

    ; Prefer RAL first (UEFI often left a valid MAC; EEPROM/EERD varies by chip)
    mov eax, [rbx + E1000_RAL0]
    mov edx, [rbx + E1000_RAH0]
    mov [e1000_mac], eax
    mov [e1000_mac + 4], dx
    mov eax, dword [e1000_mac]
    or eax, dword [e1000_mac + 2]
    test eax, eax
    jnz .mac_ok

    ; Fallback: legacy EERD (82540/QEMU). ICH/I219 uses different DONE bit.
    xor esi, esi
.eeprom_loop:
    mov eax, esi
    shl eax, 2
    or eax, 0x00000001
    mov [rbx + E1000_EERD], eax
    mov ecx, 1000
.wait_eerd:
    mov eax, [rbx + E1000_EERD]
    test eax, 0x02                  ; ICH DONE
    jnz .eerd_done
    test eax, 0x10                  ; legacy DONE
    jnz .eerd_done
    loop .wait_eerd
    jmp .mac_ok                     ; leave zeros / whatever we have
.eerd_done:
    shr eax, 16
    mov [e1000_mac + rsi * 2], ax
    inc esi
    cmp esi, 3
    jb .eeprom_loop

.mac_ok:
    ; If still zero, synthesize a locally-administered MAC so stack can run
    mov eax, dword [e1000_mac]
    or eax, dword [e1000_mac + 2]
    test eax, eax
    jnz .program
    mov dword [e1000_mac], 0x005E0200
    mov word [e1000_mac + 4], 0x86BC

.program:
    mov eax, dword [e1000_mac]
    mov [rbx + E1000_RAL0], eax
    movzx eax, word [e1000_mac + 4]
    or eax, 0x80000000
    mov [rbx + E1000_RAH0], eax

    pop rsi
    pop rbx
    ret

e1000_setup_rx:
    push rbx
    push rsi
    push rdi

    ; Allocate RX descriptor ring page
    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [rx_ring_phys], rax
    mov rdi, rax
    mov rcx, 4096 / 8
    xor rax, rax
    rep stosq

    ; Allocate one page per RX buffer (32 * need space - pack 2 per page = 16 pages)
    ; Simpler: allocate NUM_RX_DESC pages
    xor ebx, ebx
.alloc_rx_bufs:
    call pmm_alloc_page
    test rax, rax
    jz .fail
    lea rdi, [rx_bufs]
    mov [rdi + rbx * 8], rax

    ; Fill descriptor (16 bytes each: index << 4)
    mov rsi, [rx_ring_phys]
    mov rax, [rdi + rbx * 8]
    mov rcx, rbx
    shl rcx, 4
    mov [rsi + rcx], rax
    mov qword [rsi + rcx + 8], 0
    inc ebx
    cmp ebx, NUM_RX_DESC
    jb .alloc_rx_bufs

    mov rbx, [e1000_mmio]
    mov rax, [rx_ring_phys]
    mov [rbx + E1000_RDBAL], eax
    shr rax, 32
    mov [rbx + E1000_RDBAH], eax
    mov dword [rbx + E1000_RDLEN], NUM_RX_DESC * 16
    mov dword [rbx + E1000_RDH], 0
    mov dword [rbx + E1000_RDT], NUM_RX_DESC - 1
    mov dword [rx_cur], 0

    mov rax, 1
    jmp .done
.fail:
    xor rax, rax
.done:
    pop rdi
    pop rsi
    pop rbx
    ret

e1000_setup_tx:
    push rbx
    push rdi

    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [tx_ring_phys], rax
    mov rdi, rax
    mov rcx, 4096 / 8
    xor rax, rax
    rep stosq

    ; One shared TX bounce buffer
    call pmm_alloc_page
    test rax, rax
    jz .fail
    mov [tx_buf_phys], rax

    mov rbx, [e1000_mmio]
    call e1000_mmio_wait_me
    mov eax, [rbx + E1000_TCTL]
    and eax, ~TCTL_EN
    mov [rbx + E1000_TCTL], eax

    mov rax, [tx_ring_phys]
    mov [rbx + E1000_TDBAL], eax
    shr rax, 32
    mov [rbx + E1000_TDBAH], eax
    mov dword [rbx + E1000_TDLEN], NUM_TX_DESC * 16
    mov dword [rbx + E1000_TDH], 0
    mov dword [rbx + E1000_TDT], 0
    mov dword [tx_cur], 0

    mov rax, 1
    jmp .done
.fail:
    xor rax, rax
.done:
    pop rdi
    pop rbx
    ret

; Queue one complete dummy TX on the live ring (after TCTL.EN).
; Do NOT set RS — on this ME-managed I219, status writeback appears to stall
; the TX DMA unit (IFCS-only advanced TDH; EOP|IFCS|RS left TDH at 0).
; Completion is TDH advancing. Stores TDH in e1000_probe_tdh.
e1000_tx_probe:
    push rax
    push rbx
    push rcx
    push rdi
    push rsi

    mov word [e1000_probe_tdh], 0
    mov rbx, [e1000_mmio]
    mov rsi, [tx_buf_phys]
    test rsi, rsi
    jz .done
    mov rdi, rsi
    mov rcx, 512 / 8
    xor rax, rax
    rep stosq
    clflush [rsi]
    clflush [rsi + 511]

    mov rsi, [tx_ring_phys]
    mov rdi, rsi                    ; desc 0
    mov rax, [tx_buf_phys]
    mov [rdi], rax
    ; length | (CMD << 24); CMD = EOP|IFCS (close packet, no RS)
    mov dword [rdi + 8], 512 | (0x03 << 24)
    mov dword [rdi + 12], 0
    clflush [rdi]
    clflush [rdi + 15]
    sfence

    call e1000_mmio_wait_me
    mov dword [rbx + E1000_TDT], 1
    mov dword [tx_cur], 1

    mov ecx, 50
.wait_probe:
    mov eax, [rbx + E1000_TDH]
    test eax, eax
    jnz .probe_ok
    push rcx
    mov rcx, 2
    call sleep_ms
    pop rcx
    loop .wait_probe
.probe_ok:
    mov eax, [rbx + E1000_TDH]
    mov [e1000_probe_tdh], ax

.done:
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    pop rax
    ret

; RAX = 1 if this is QEMU's 82540EM (0x100E) — safe for fake 10.0.2.15 fallback
e1000_is_qemu:
    cmp word [e1000_device_id], 0x100E
    sete al
    movzx eax, al
    ret

; RCX = destination buffer (6 bytes)
e1000_driver_get_mac:
    push rsi
    push rdi
    push rcx
    lea rsi, [e1000_mac]
    mov rdi, rcx
    mov rcx, 6
    rep movsb
    pop rcx
    pop rdi
    pop rsi
    ret

; RCX = packet, RDX = length
e1000_driver_send:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov rsi, rcx
    mov r12, rdx
    cmp r12, 1518
    jbe .len_ok
    mov r12, 1518
.len_ok:
    test r12, r12
    jz .done

    ; Copy into TX bounce buffer
    mov rdi, [tx_buf_phys]
    mov rcx, r12
    rep movsb

    mov ebx, [tx_cur]
    mov rsi, [tx_ring_phys]
    mov rcx, rbx
    shl rcx, 4
    lea rdi, [rsi + rcx]

    mov rax, [tx_buf_phys]
    mov [rdi], rax                  ; buffer address
    ; EOP|IFCS — no RS (I219 ME path stalls TX DMA on status writeback)
    mov eax, r12d
    and eax, 0xFFFF
    or eax, (0x03 << 24)
    mov [rdi + 8], eax
    mov dword [rdi + 12], 0

    ; Force descriptor + packet out of CPU caches (DMA may not snoop WB on some PCH)
    clflush [rdi]
    clflush [rdi + 15]
    mov rax, [tx_buf_phys]
    clflush [rax]
    test r12, r12
    jz .flushed
    lea rax, [rax + r12 - 1]
    clflush [rax]
.flushed:
    sfence
    call e1000_mmio_wait_me

    ; Advance TDT
    inc ebx
    and ebx, NUM_TX_DESC - 1
    mov [tx_cur], ebx
    mov rax, [e1000_mmio]
    mov [rax + E1000_TDT], ebx

    ; ME workaround: confirm TDT stuck
    call e1000_mmio_wait_me
    mov rax, [e1000_mmio]
    mov eax, [rax + E1000_TDT]
    cmp eax, ebx
    je .tdt_ok
    lea rcx, [msg_e1000_tdtbad]
    call con_puts
.tdt_ok:

    ; Wait for TDH to catch TDT (no RS/DD — see probe comment)
    mov ecx, 100
.wait_tx_tdh:
    mov rax, [e1000_mmio]
    mov eax, [rax + E1000_TDH]
    cmp eax, ebx
    je .tx_ok
    push rcx
    mov rcx, 1
    call sleep_ms
    pop rcx
    loop .wait_tx_tdh
    lea rcx, [msg_e1000_txfail]
    call con_puts
    lea rcx, [msg_e1000_tdh]
    call con_puts
    mov rax, [e1000_mmio]
    mov eax, [rax + E1000_TDH]
    mov rcx, rax
    call con_put_hex
    lea rcx, [msg_slash]
    call con_puts
    mov rax, [e1000_mmio]
    mov eax, [rax + E1000_TDT]
    mov rcx, rax
    call con_put_hex
    call con_newline
    lea rcx, [msg_e1000_tctl_diag]
    call con_puts
    mov rax, [e1000_mmio]
    mov eax, [rax + E1000_TCTL]
    mov rcx, rax
    call con_put_hex
    call con_newline
    lea rcx, [msg_e1000_txdctl]
    call con_puts
    mov rax, [e1000_mmio]
    mov eax, [rax + E1000_TXDCTL]
    mov rcx, rax
    call con_put_hex
    call con_newline
    lea rcx, [msg_e1000_fwsm]
    call con_puts
    mov rax, [e1000_mmio]
    mov eax, [rax + E1000_FWSM]
    mov rcx, rax
    call con_put_hex
    call con_newline
    jmp .done
.tx_ok:
    push rcx
    lea rcx, [msg_tx]
    call serial_puts
    pop rcx

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; RCX = dest buffer -> RAX = length
e1000_driver_recv:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12

    mov r12, rcx                    ; dest
    mov ebx, [rx_cur]
    mov rsi, [rx_ring_phys]
    mov rcx, rbx
    shl rcx, 4
    lea rdi, [rsi + rcx]

    movzx eax, byte [rdi + 12]      ; status
    test al, 0x01                   ; DD
    jz .empty

    push rax
    push rcx
    lea rcx, [msg_rx]
    call serial_puts
    pop rcx
    pop rax

    movzx edx, word [rdi + 8]       ; length
    mov eax, edx

    ; Copy from RX buffer
    lea rsi, [rx_bufs]
    mov rsi, [rsi + rbx * 8]
    mov rdi, r12
    mov rcx, rdx
    cmp rcx, 2048
    jbe .copy
    mov rcx, 2048
.copy:
    push rax
    rep movsb
    pop rax

    ; Recycle descriptor
    mov rsi, [rx_ring_phys]
    mov rcx, rbx
    shl rcx, 4
    lea rdi, [rsi + rcx]
    mov qword [rdi + 8], 0

    ; Advance RDT / rx_cur
    mov ecx, ebx
    inc ebx
    and ebx, NUM_RX_DESC - 1
    mov [rx_cur], ebx
    mov rsi, [e1000_mmio]
    mov [rsi + E1000_RDT], ecx
    jmp .done

.empty:
    xor rax, rax

.done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

section .data
align 8
e1000_mmio dq 0
e1000_bdf dd 0
e1000_pci_id dd 0
e1000_device_id dw 0
e1000_have_link db 0
e1000_flush_tdh dw 0
e1000_probe_tdh dw 0
e1000_hang_stat dd 0
e1000_mac db 0x52, 0x54, 0x00, 0x12, 0x34, 0x56, 0, 0
rx_ring_phys dq 0
tx_ring_phys dq 0
tx_buf_phys dq 0
rx_cur dd 0
tx_cur dd 0

msg_e1000_init db "Net: Intel e1000 Ethernet initializing...", 13, 10, 0
msg_e1000_devid db "Net: e1000 PCI device ID: 0x", 0
msg_e1000_i219 db "Net: chip is I219-LM10 (PCH) — using e1000e PHY path.", 13, 10, 0
msg_e1000_mac db "Net: e1000 MAC ", 0
msg_colon db ":", 0
msg_e1000_txdctl db "Net: e1000 TXDCTL=0x", 0
msg_e1000_flr db "Net: e1000 issuing PCI function-level reset...", 13, 10, 0
msg_e1000_hang db "Net: e1000 I219 TX recover (flush; D3/D0 only if needed)...", 13, 10, 0
msg_e1000_hangstat db "Net: e1000 PCI hang status=0x", 0
msg_e1000_pm db "Net: e1000 PCI D3hot->D0 power cycle...", 13, 10, 0
msg_e1000_pm_need db "Net: e1000 flush did not advance TDH — trying D3/D0...", 13, 10, 0
msg_e1000_pm_skip db "Net: e1000 flush advanced TDH — skipping D3/D0 (keeps TX alive).", 13, 10, 0
msg_e1000_probe db "Net: e1000 TX probe TDH=0x", 0
msg_e1000_tarc db "Net: e1000 TARC0=0x", 0
msg_e1000_skiprst db "Net: e1000 skipping CTRL.RST on I219 (avoids TX hang).", 13, 10, 0
msg_e1000_recap db "Net: e1000 recover flush_tdh/hang=0x", 0
msg_e1000_tdbal db "Net: e1000 TDBAL(ring)=0x", 0
msg_e1000_tdtbad db "Net: e1000 TDT write ignored (ME arbiter?).", 13, 10, 0
msg_e1000_ok   db "Net: e1000 link ready.", 13, 10, 0
msg_e1000_nolink db "Net: e1000 init OK but no cable link yet.", 13, 10, 0
msg_e1000_status db "Net: e1000 STATUS=0x", 0
msg_e1000_phyra db "Net: e1000 PHYRA still set (ME may own PHY).", 13, 10, 0
msg_e1000_gptc db "Net: e1000 GPTC (tx good)=0x", 0
msg_e1000_gprc db "Net: e1000 GPRC (rx good)=0x", 0
msg_e1000_txfail db "Net: e1000 TX descriptor timeout (queue not running?).", 13, 10, 0
msg_e1000_tctl_diag db "Net: e1000 TCTL=0x", 0
msg_e1000_fwsm db "Net: e1000 FWSM=0x", 0
msg_e1000_flush_diag db "Net: e1000 flush TDH/DD=0x", 0
msg_e1000_tdh db "Net: e1000 TDH/TDT=0x", 0
msg_slash db "/", 0
msg_e1000_fail db "Net: e1000 init FAILED.", 13, 10, 0
msg_rx db "RX", 13, 10, 0
msg_tx db "TX", 13, 10, 0

section .bss
align 8
rx_bufs resq NUM_RX_DESC
