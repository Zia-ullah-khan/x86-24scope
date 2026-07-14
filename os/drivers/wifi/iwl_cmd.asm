; ==============================================================================
; x86-24scope OS - Intel iwlwifi host command transport
; Synchronous HCMD via command TX queue + RX response poll.
; ==============================================================================
bits 64
default rel

section .text

global wifi_send_cmd
global iwl_cmd_init
global iwl_cmd_poll_rx
global iwl_cmd_wait_alive
global iwl_txq_kick
global iwl_get_last_rx
global iwl_assoc_flag
global iwl_cmd_rx_free_addr
global iwl_cmd_rx_used_addr
global iwl_cmd_rx_status_addr
global iwl_cmd_tx_tfd_addr

extern iwl_mmio_ptr
extern con_puts
extern serial_puts
extern sleep_ms
extern pmm_alloc_page

; CSR
CSR_INT                 equ 0x008
CSR_INT_MASK            equ 0x00C
CSR_INT_BIT_ALIVE       equ 1
CSR_INT_BIT_FH_RX       equ (1 << 31)
CSR_INT_BIT_SW_ERR      equ (1 << 25)
CSR_INT_BIT_HW_ERR      equ (1 << 29)
CSR_CTXT_INFO_BA        equ 0x40
CSR_CTXT_INFO_ADDR      equ 0x118
CSR_CTXT_INFO_BOOT_CTRL equ 0x0
CSR_AUTO_FUNC_BOOT_ENA  equ 2
CSR_AUTO_FUNC_INIT      equ 0x80

CMD_QUEUE_SIZE          equ 32
RX_QUEUE_SIZE           equ 16
RB_SIZE                 equ 2048
TFD_SIZE                equ 128
MAX_CMD_PAYLOAD         equ 1024

; wifi_send_cmd:
;   RCX = cmd id (low 8) | group<<8 (optional)
;   RDX = payload ptr (may be 0)
;   R8  = payload len
;   R9  = flags (bit0 = want response)
; Returns RAX = 1 success, 0 fail. Response in iwl_cmd_resp if any.
wifi_send_cmd:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    cmp byte [cmd_ready], 0
    jz .fail

    mov r12d, ecx                   ; cmd
    mov r13, rdx                    ; payload
    mov r14, r8                     ; len
    cmp r14, MAX_CMD_PAYLOAD
    jbe .len_ok
    mov r14, MAX_CMD_PAYLOAD
.len_ok:

    ; Build command header in iwl_hcmd_buf: 4-byte iwl_cmd_header + payload
    ; struct iwl_cmd_header { u8 cmd; u8 group_id; __le16 sequence; }
    lea rdi, [iwl_hcmd_buf]
    mov eax, r12d
    mov [rdi], al                   ; cmd
    shr eax, 8
    mov [rdi + 1], al               ; group
    mov ax, [cmd_seq]
    mov [rdi + 2], ax
    inc word [cmd_seq]

    test r13, r13
    jz .no_pay
    lea rdi, [iwl_hcmd_buf + 4]
    mov rsi, r13
    mov rcx, r14
    rep movsb
.no_pay:
    lea rax, [iwl_hcmd_buf]
    mov edx, r14d
    add edx, 4
    call iwl_enqueue_hcmd
    test rax, rax
    jz .fail

    ; Poll for response / FH activity
    mov ecx, 200
.wait:
    push rcx
    call iwl_cmd_poll_rx
    pop rcx
    test rax, rax
    jnz .got
    push rcx
    mov rcx, 5
    call sleep_ms
    pop rcx
    loop .wait
    ; Timeout still OK for fire-and-forget
    test r9b, 1
    jz .ok
    jmp .fail

.got:
.ok:
    mov rax, 1
    jmp .done
.fail:
    xor rax, rax
.done:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; RAX = iwl_hcmd_buf phys, EDX = total len
iwl_enqueue_hcmd:
    push rbx
    push rsi
    push rdi

    mov ebx, [tx_write]
    and ebx, CMD_QUEUE_SIZE - 1

    ; Simple TFD: one TB pointing at iwl_hcmd_buf (identity mapped)
    lea rsi, [tx_tfd]
    mov eax, ebx
    imul eax, TFD_SIZE
    add rsi, rax
    ; zero TFD
    mov rdi, rsi
    mov rcx, TFD_SIZE / 8
    xor eax, eax
    push rsi
    rep stosq
    pop rsi

    ; num_tbs = 1 at offset depending on format ??? long TFD:
    ; Use short-compatible: first qword = addr, then len
    lea rax, [iwl_hcmd_buf]
    mov [rsi], rax
    mov dword [rsi + 8], edx
    mov byte [rsi + 12], 1          ; num_tbs hint

    ; Write index
    inc ebx
    and ebx, CMD_QUEUE_SIZE - 1
    mov [tx_write], ebx

    ; DoorBell / WRPTR ??? gen2 uses HBUS_TARG_WRPTR style; gen3 uses MTR
    ; Store write pointer for host; device polls via ctxt hcmd cfg
    mov [tx_wrptr_mirror], ebx

    call iwl_txq_kick
    mov rax, 1
    pop rdi
    pop rsi
    pop rbx
    ret

iwl_txq_kick:
    ; Device-specific doorbell. For gen2 FH: HBUS_TARG_WRPTR
    ; Offset 0x460 + queue. Soft kick via CSR write if mapped.
    mov rax, [iwl_mmio_ptr]
    test rax, rax
    jz .done
    ; Write mirrored wrptr into a known scratch ??? real HW needs PRPH
    ; CSR mailbox poke to wake firmware
    mov edx, [tx_wrptr_mirror]
    mov [rax + 0x470], edx          ; HBUS_TARG_WRPTR-ish
.done:
    ret

; Initialize cmd/rx rings. RAX=1
iwl_cmd_init:
    push rbx
    push rdi

    ; Clear TFDs / RX bookkeeping
    lea rdi, [tx_tfd]
    mov rcx, (CMD_QUEUE_SIZE * TFD_SIZE) / 8
    xor eax, eax
    rep stosq

    lea rdi, [rx_used]
    mov rcx, (RX_QUEUE_SIZE * 8) / 8
    xor eax, eax
    rep stosq

    mov dword [tx_write], 0
    mov dword [tx_read], 0
    mov dword [rx_read], 0
    mov dword [rx_write], 0
    mov word [cmd_seq], 1
    mov byte [cmd_ready], 1
    mov byte [alive_seen], 0
    mov byte [iwl_assoc_flag], 0

    ; Pre-post RX buffers: each entry points into iwl_rx_bufs
    xor ebx, ebx
.fill_rx:
    lea rax, [iwl_rx_bufs]
    mov ecx, ebx
    imul ecx, RB_SIZE
    add rax, rcx
    lea rdi, [rx_free]
    mov [rdi + rbx * 8], rax
    inc ebx
    cmp ebx, RX_QUEUE_SIZE
    jb .fill_rx
    mov dword [rx_write], RX_QUEUE_SIZE

    mov rax, 1
    pop rdi
    pop rbx
    ret

; Poll CSR_INT for ALIVE; RAX=1 if seen
iwl_cmd_wait_alive:
    push rbx
    mov rax, [iwl_mmio_ptr]
    test rax, rax
    jz .fail
    mov rbx, rax
    mov ecx, 500
.poll:
    mov eax, [rbx + CSR_INT]
    test eax, CSR_INT_BIT_ALIVE
    jnz .hit
    ; Also check FH_RX (alive notif arrives as RX)
    test eax, CSR_INT_BIT_FH_RX
    jnz .hit_rx
    push rcx
    mov rcx, 10
    call sleep_ms
    pop rcx
    loop .poll
    jmp .fail

.hit_rx:
    call iwl_cmd_poll_rx
.hit:
    ; ACK interrupt
    mov dword [rbx + CSR_INT], 0xFFFFFFFF
    mov byte [alive_seen], 1
    lea rcx, [msg_alive]
    call con_puts
    lea rcx, [msg_alive]
    call serial_puts
    mov rax, 1
    jmp .done
.fail:
    lea rcx, [msg_alive_fail]
    call con_puts
    lea rcx, [msg_alive_fail]
    call serial_puts
    xor rax, rax
.done:
    pop rbx
    ret

; Drain one RX buffer if available. RAX = length (0 none)
; Copies Ethernet-ish payload to last_rx_buf when possible.
iwl_cmd_poll_rx:
    push rbx
    push rsi
    push rdi

    mov ebx, [rx_read]
    cmp ebx, [rx_write]
    je .empty

    and ebx, RX_QUEUE_SIZE - 1
    lea rsi, [iwl_rx_bufs]
    imul eax, ebx, RB_SIZE
    add rsi, rax

    ; RX packet: iwl firmware frames start with rx metadata.
    ; Minimal parse: look for ethertype at common offsets; else copy raw.
    mov edx, 1518
    ; Try offset 0x2a (common MVM rx mpdu payload offset ballpark) else 0
    lea rdi, [last_rx_buf]
    mov rcx, 64
    ; Heuristic: if bytes look like Ethernet dest (not all zero), copy from 0
    mov eax, [rsi]
    test eax, eax
    jz .try_off
    mov rcx, 1514
    jmp .do_copy
.try_off:
    add rsi, 0x2a
    mov rcx, 1514
.do_copy:
    rep movsb
    mov dword [last_rx_len], 1514

    inc dword [rx_read]
    mov eax, [last_rx_len]
    jmp .done

.empty:
    ; Check hardware INT for RX and restock
    mov rax, [iwl_mmio_ptr]
    test rax, rax
    jz .none
    mov edx, [rax + CSR_INT]
    test edx, CSR_INT_BIT_FH_RX | CSR_INT_BIT_ALIVE
    jz .none
    mov dword [rax + CSR_INT], edx
    ; Soft: mark a synthetic write if firmware DMA'd into our buffers
    ; Without full RFH programming, RX may stay empty until rings bind.
.none:
    xor eax, eax
.done:
    pop rdi
    pop rsi
    pop rbx
    ret

; RAX = ptr, RDX = len of last RX frame
iwl_get_last_rx:
    lea rax, [last_rx_buf]
    mov edx, [last_rx_len]
    ret

iwl_cmd_rx_free_addr:
    lea rax, [rx_free]
    ret

iwl_cmd_rx_used_addr:
    lea rax, [rx_used]
    ret

iwl_cmd_rx_status_addr:
    lea rax, [rx_status]
    ret

iwl_cmd_tx_tfd_addr:
    lea rax, [tx_tfd]
    ret

section .data
align 8
cmd_ready db 0
alive_seen db 0
iwl_assoc_flag db 0
align 8
cmd_seq dw 1
tx_write dd 0
tx_read dd 0
tx_wrptr_mirror dd 0
rx_read dd 0
rx_write dd 0
last_rx_len dd 0

msg_alive db "WiFi: Firmware ALIVE.", 13, 10, 0
msg_alive_fail db "WiFi: Timed out waiting for ALIVE.", 13, 10, 0

section .bss
alignb 16
iwl_hcmd_buf resb MAX_CMD_PAYLOAD + 16
alignb 4096
tx_tfd resb CMD_QUEUE_SIZE * TFD_SIZE
alignb 16
rx_free resq RX_QUEUE_SIZE
rx_used resq RX_QUEUE_SIZE
alignb 4096
iwl_rx_bufs resb RX_QUEUE_SIZE * RB_SIZE
alignb 16
rx_status resq 4
alignb 16
last_rx_buf resb 2048

