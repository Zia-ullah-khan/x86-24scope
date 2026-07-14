from pathlib import Path
import os

# e1000 RX debug
p = Path(r"c:/Projects/x86-24scope-os/os/drivers/net/e1000.asm")
t = p.read_text(encoding="utf-8")
if "extern serial_puts" not in t:
    t = t.replace("extern sleep_ms\n", "extern sleep_ms\nextern serial_puts\n")
if "msg_rx db" not in t:
    t = t.replace(
        "movzx eax, byte [rdi + 12]      ; status\n    test al, 0x01                   ; DD\n    jz .empty",
        "movzx eax, byte [rdi + 12]      ; status\n    test al, 0x01                   ; DD\n    jz .empty\n\n    push rax\n    push rcx\n    lea rcx, [msg_rx]\n    call serial_puts\n    pop rcx\n    pop rax",
    )
    t = t.replace(
        "msg_e1000_fail db \"Net: e1000 init FAILED.\", 13, 10, 0",
        "msg_e1000_fail db \"Net: e1000 init FAILED.\", 13, 10, 0\nmsg_rx db \"RX\", 13, 10, 0",
    )
    tmp = Path(str(p) + ".new")
    tmp.write_text(t, encoding="utf-8")
    os.replace(tmp, p)
    print("e1000 rx debug")
else:
    print("e1000 debug exists")

# tcp entry debug
p = Path(r"c:/Projects/x86-24scope-os/os/net/tcp.asm")
t = p.read_text(encoding="utf-8")
if "msg_tcp_pkt" not in t:
    t = t.replace(
        "mov rsi, rcx                    ; rsi = TCP start\n    mov r12, rdx                    ; r12 = length",
        "mov rsi, rcx                    ; rsi = TCP start\n    push rcx\n    lea rcx, [msg_tcp_pkt]\n    call serial_puts\n    pop rcx\n    mov rsi, rcx\n    mov r12, rdx                    ; r12 = length",
    )
    t = t.replace(
        'msg_tcp_syn db "TCP: SYN received, sending SYN-ACK", 13, 10, 0',
        'msg_tcp_syn db "TCP: SYN received, sending SYN-ACK", 13, 10, 0\nmsg_tcp_pkt db "TCP-PKT", 13, 10, 0',
    )
    tmp = Path(str(p) + ".new")
    tmp.write_text(t, encoding="utf-8")
    os.replace(tmp, p)
    print("tcp pkt debug")
else:
    print("tcp debug exists")

# print IP to serial too
p = Path(r"c:/Projects/x86-24scope-os/os/net/dhcp.asm")
t = p.read_text(encoding="utf-8")
if "serial_put_dec" not in t and "print_ip uses serial hex" not in t:
    # replace print_ip to also dump hex via serial_put_hex
    old = """print_ip:
    push rbx
    mov ebx, ecx

    ; Byte 1
    movzx ecx, bl
    call con_put_dec
    call print_dot"""
    new = """print_ip:
    push rbx
    mov ebx, ecx
    ; Also dump raw LE dword to serial for debugging
    push rcx
    call serial_put_hex
    pop rcx

    ; Byte 1
    movzx ecx, bl
    call con_put_dec
    call print_dot"""
    if old in t:
        t = t.replace(old, new)
        tmp = Path(str(p) + ".new")
        tmp.write_text(t, encoding="utf-8")
        os.replace(tmp, p)
        print("dhcp print hex")
    else:
        print("print_ip pattern missing")
