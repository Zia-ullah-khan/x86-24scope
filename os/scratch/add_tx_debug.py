from pathlib import Path
import os

# Log ARP fail and TX in ip_send / e1000
p = Path(r"c:/Projects/x86-24scope-os/os/net/ip.asm")
t = p.read_text(encoding="utf-8")
if "msg_arp_fail" not in t:
    if "extern serial_puts" not in t:
        # try add after other externs
        t = t.replace("extern eth_send_packet\n", "extern eth_send_packet\nextern serial_puts\n", 1)
        if "extern serial_puts" not in t:
            t = "extern serial_puts\n" + t
    t = t.replace(
        "    call arp_resolve\n    test rax, rax\n    jz .error                       ; ARP resolution failed, drop packet",
        "    call arp_resolve\n    test rax, rax\n    jnz .arp_ok\n    push rcx\n    lea rcx, [msg_arp_fail]\n    call serial_puts\n    pop rcx\n    jmp .error\n.arp_ok:",
    )
    # add message in data
    if "section .data" in t:
        t = t.replace("section .data", "section .data\nmsg_arp_fail db \"ARP-FAIL\", 13, 10, 0\nmsg_ip_tx db \"IP-TX\", 13, 10, 0", 1)
    t = t.replace(
        "    call eth_send_packet\n",
        "    push rcx\n    lea rcx, [msg_ip_tx]\n    call serial_puts\n    pop rcx\n    call eth_send_packet\n",
        1,
    )
    tmp = Path(str(p) + ".new")
    tmp.write_text(t, encoding="utf-8")
    os.replace(tmp, p)
    print("ip tx debug")
else:
    print("ip debug exists")

# e1000 TX debug
p = Path(r"c:/Projects/x86-24scope-os/os/drivers/net/e1000.asm")
t = p.read_text(encoding="utf-8")
if "msg_tx db" not in t:
    t = t.replace(
        "    mov rax, [e1000_mmio]\n    mov [rax + E1000_TDT], ebx\n\n.done:",
        "    mov rax, [e1000_mmio]\n    mov [rax + E1000_TDT], ebx\n    push rcx\n    lea rcx, [msg_tx]\n    call serial_puts\n    pop rcx\n\n.done:",
    )
    t = t.replace(
        "msg_rx db \"RX\", 13, 10, 0",
        "msg_rx db \"RX\", 13, 10, 0\nmsg_tx db \"TX\", 13, 10, 0",
    )
    tmp = Path(str(p) + ".new")
    tmp.write_text(t, encoding="utf-8")
    os.replace(tmp, p)
    print("e1000 tx debug")
else:
    print("e1000 tx exists")

# On SYN retransmit while SYN_RECEIVED, resend SYN-ACK
p = Path(r"c:/Projects/x86-24scope-os/os/net/tcp.asm")
t = p.read_text(encoding="utf-8")
old = """    cmp r10b, TCP_STATE_SYN_RECEIVED
    jne .check_established

    ; Expecting ACK (flags at eax)
    test al, TCP_FLAG_ACK
    jz .done

    ; Transition to ESTABLISHED!
    mov byte [r11 + 0], TCP_STATE_ESTABLISHED
    jmp .done"""
new = """    cmp r10b, TCP_STATE_SYN_RECEIVED
    jne .check_established

    ; Retransmitted SYN: resend SYN-ACK
    test al, TCP_FLAG_SYN
    jz .synrecv_ack
    lea rcx, [r11]
    mov edx, TCP_FLAG_SYN | TCP_FLAG_ACK
    call tcp_send_control
    jmp .done

.synrecv_ack:
    ; Expecting ACK (flags at eax)
    test al, TCP_FLAG_ACK
    jz .done

    ; Transition to ESTABLISHED!
    mov byte [r11 + 0], TCP_STATE_ESTABLISHED
    lea rcx, [msg_tcp_est]
    call serial_puts
    jmp .done"""
if old in t and "msg_tcp_est" not in t:
    t = t.replace(old, new)
    t = t.replace(
        'msg_tcp_pkt db "TCP-PKT", 13, 10, 0',
        'msg_tcp_pkt db "TCP-PKT", 13, 10, 0\nmsg_tcp_est db "TCP: ESTABLISHED", 13, 10, 0',
    )
    tmp = Path(str(p) + ".new")
    tmp.write_text(t, encoding="utf-8")
    os.replace(tmp, p)
    print("syn retransmit fix")
else:
    print("syn retransmit skip", old in t)
