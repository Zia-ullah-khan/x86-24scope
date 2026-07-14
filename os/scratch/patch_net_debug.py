from pathlib import Path
import os

p = Path(r"c:/Projects/x86-24scope-os/os/kernel/kernel.asm")
t = p.read_text(encoding="utf-8")
if "global network_rx_buffer" not in t:
    t = t.replace(
        "network_rx_buffer resb 2048",
        "global network_rx_buffer\nnetwork_rx_buffer resb 2048",
    )
    tmp = Path(str(p) + ".new")
    tmp.write_text(t, encoding="utf-8")
    os.replace(tmp, p)
    print("kernel global added")
else:
    print("kernel already global")

p = Path(r"c:/Projects/x86-24scope-os/os/net/tcp.asm")
t = p.read_text(encoding="utf-8")
if "msg_tcp_syn" not in t:
    needle = ".spawn_socket:\n    ; To keep things simple"
    if needle not in t:
        # try after previous edit
        needle = ".spawn_socket:\n"
        if ".spawn_socket:\n    lea rcx, [msg_tcp_syn]" in t:
            print("tcp debug already present")
        else:
            raise SystemExit("spawn_socket not found")
    else:
        t = t.replace(
            ".spawn_socket:\n    ; To keep things simple",
            ".spawn_socket:\n    lea rcx, [msg_tcp_syn]\n    call serial_puts\n    ; To keep things simple",
            1,
        )
        if "section .data" in t and "msg_tcp_syn" not in t:
            # append data near end before bss if possible
            if "section .bss" in t:
                t = t.replace(
                    "section .bss",
                    "section .data\nmsg_tcp_syn db \"TCP: SYN received, sending SYN-ACK\", 13, 10, 0\n\nsection .bss",
                    1,
                )
            else:
                t = t.rstrip() + "\n\nsection .data\nmsg_tcp_syn db \"TCP: SYN received, sending SYN-ACK\", 13, 10, 0\n"
        tmp = Path(str(p) + ".new")
        tmp.write_text(t, encoding="utf-8")
        os.replace(tmp, p)
        print("tcp debug added")
else:
    print("tcp debug exists")
