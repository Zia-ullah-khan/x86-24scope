from pathlib import Path
import os

p = Path(r"c:/Projects/x86-24scope-os/os/net/tcp.asm")
t = p.read_text(encoding="utf-8")
if "msg_tcp_syn db" not in t:
    repl = (
        'section .data\n'
        'msg_tcp_syn db "TCP: SYN received, sending SYN-ACK", 13, 10, 0\n'
        '\n'
        'section .bss\n'
        'align 16\n'
        'tcp_sockets'
    )
    t = t.replace("section .bss\nalign 16\ntcp_sockets", repl)
    tmp = Path(str(p) + ".new")
    tmp.write_text(t, encoding="utf-8")
    os.replace(tmp, p)
    print("added msg")
else:
    print("msg present")
