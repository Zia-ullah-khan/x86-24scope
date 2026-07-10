bits 64
default rel

extern WSAStartup
extern WSACleanup
extern socket
extern bind
extern listen
extern accept
extern recv
extern send
extern closesocket
extern ExitProcess
extern MessageBoxA
extern InternetOpenA
extern InternetOpenUrlA
extern InternetCloseHandle

section .data
    wsa_version dw 2, 2
    sockaddr:
        sin_family dw 2
        sin_port dw 0x901F
        sin_addr dd 0

    user_agent db "x86-24scope/1.0", 0
    status_url db "https://24data.ptfs.app/controllers", 0

    http_header db "HTTP/1.1 200 OK", 13, 10
                db "Content-Type: text/html; charset=utf-8", 13, 10
                db "Content-Length: "
    header_len equ $ - http_header

    http_footer db 13, 10
                db "Connection: close", 13, 10
                db 13, 10
    footer_len equ $ - http_footer

    online_page db "<!DOCTYPE html>", 13, 10
                db "<html>", 13, 10
                db "<head>", 13, 10
                db '<meta charset="utf-8">', 13, 10
                db '<meta name="viewport" content="width=device-width, initial-scale=1.0">', 13, 10
                db "<title>24data Status</title>", 13, 10
                db "<style>", 13, 10
                db "  :root { color-scheme: dark; --bg: #06111b; --panel: rgba(10, 20, 32, 0.9); --text: #e8f4ff; --muted: #8aa0b8; --accent: #29d38f; }", 13, 10
                db "  * { box-sizing: border-box; }", 13, 10
                db "  body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: Arial, Helvetica, sans-serif; color: var(--text); background: radial-gradient(circle at top, rgba(41, 211, 143, 0.14), transparent 32%), linear-gradient(135deg, #050b12 0%, #081521 55%, #0d1f2f 100%); padding: 32px; }", 13, 10
                db "  .card { width: min(720px, 100%); padding: 40px; border: 1px solid rgba(137, 180, 220, 0.18); border-radius: 24px; background: var(--panel); box-shadow: 0 24px 80px rgba(0, 0, 0, 0.4); }", 13, 10
                db "  .eyebrow { margin: 0 0 14px; color: #7fd6ff; text-transform: uppercase; letter-spacing: 0.2em; font-size: 0.78rem; font-weight: 700; }", 13, 10
                db "  h1 { margin: 0; font-size: clamp(2.5rem, 7vw, 5rem); line-height: 0.95; letter-spacing: -0.05em; }", 13, 10
                db "  .online { color: var(--accent); }", 13, 10
                db "  p { margin: 18px 0 0; max-width: 58ch; color: var(--muted); font-size: 1.05rem; line-height: 1.7; }", 13, 10
                db "</style>", 13, 10
                db "</head>", 13, 10
                db "<body>", 13, 10
                db '<main class="card">', 13, 10
                db '<p class="eyebrow">24data listener</p>', 13, 10
                db '<h1>24data is <span class="online">online</span>.</h1>', 13, 10
                db "<p>The server reached https://24data.ptfs.app/controllers and got a response, so the upstream is up.</p>", 13, 10
                db "</main>", 13, 10
                db "</body>", 13, 10
                db "</html>"
    online_len equ $ - online_page

    offline_page db "<!DOCTYPE html>", 13, 10
                 db "<html>", 13, 10
                 db "<head>", 13, 10
                 db '<meta charset="utf-8">', 13, 10
                 db '<meta name="viewport" content="width=device-width, initial-scale=1.0">', 13, 10
                 db "<title>24data Status</title>", 13, 10
                 db "<style>", 13, 10
                 db "  :root { color-scheme: dark; --bg: #160b0b; --panel: rgba(35, 12, 12, 0.9); --text: #fff1f1; --muted: #d6a6a6; --accent: #ff6b6b; }", 13, 10
                 db "  * { box-sizing: border-box; }", 13, 10
                 db "  body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: Arial, Helvetica, sans-serif; color: var(--text); background: radial-gradient(circle at top, rgba(255, 107, 107, 0.14), transparent 32%), linear-gradient(135deg, #110505 0%, #240909 55%, #350f0f 100%); padding: 32px; }", 13, 10
                 db "  .card { width: min(720px, 100%); padding: 40px; border: 1px solid rgba(220, 137, 137, 0.18); border-radius: 24px; background: var(--panel); box-shadow: 0 24px 80px rgba(0, 0, 0, 0.4); }", 13, 10
                 db "  .eyebrow { margin: 0 0 14px; color: #ffb0b0; text-transform: uppercase; letter-spacing: 0.2em; font-size: 0.78rem; font-weight: 700; }", 13, 10
                 db "  h1 { margin: 0; font-size: clamp(2.5rem, 7vw, 5rem); line-height: 0.95; letter-spacing: -0.05em; }", 13, 10
                 db "  .offline { color: var(--accent); }", 13, 10
                 db "  p { margin: 18px 0 0; max-width: 58ch; color: var(--muted); font-size: 1.05rem; line-height: 1.7; }", 13, 10
                 db "</style>", 13, 10
                 db "</head>", 13, 10
                 db "<body>", 13, 10
                 db '<main class="card">', 13, 10
                 db '<p class="eyebrow">24data listener</p>', 13, 10
                 db '<h1>24data is <span class="offline">offline</span>.</h1>', 13, 10
                 db "<p>The server could not reach https://24data.ptfs.app/controllers right now.</p>", 13, 10
                 db "</main>", 13, 10
                 db "</body>", 13, 10
                 db "</html>"
    offline_len equ $ - offline_page

    error_title db "Error", 0
    error_msg db "An error occurred.", 0

section .bss
    wsa_data resb 400
    listen_socket resq 1
    page_content resq 1
    page_length resq 1
    response_buffer resb 4096
    client_socket resq 1
    request_buffer resb 1024
    internet_session resq 1
    internet_handle resq 1

section .text
global _start

_start:
    sub rsp, 40
    mov rcx, [wsa_version]
    lea rdx, [wsa_data]
    call WSAStartup
    test eax, eax
    jnz error

    mov rcx, 2
    mov rdx, 1
    xor r8, r8
    call socket
    mov [listen_socket], rax
    cmp rax, -1
    je cleanup_WSA

    mov rcx, [listen_socket]
    lea rdx, [sockaddr]
    mov r8, 16
    call bind
    test eax, eax
    js close_listen

    mov rcx, [listen_socket]
    mov rdx, 5
    call listen
    test eax, eax
    js close_listen

server_loop:
    mov rcx, [listen_socket]
    xor rdx, rdx
    xor r8, r8
    call accept
    cmp rax, -1
    je server_loop
    mov [client_socket], rax

    mov rcx, [client_socket]
    lea rdx, [request_buffer]
    mov r8, 1024
    xor r9, r9
    call recv

    call check_24data_online
    test eax, eax
    jz use_offline_page
    lea rax, [online_page]
    mov [page_content], rax
    mov qword [page_length], online_len
    jmp build_response

use_offline_page:
    lea rax, [offline_page]
    mov [page_content], rax
    mov qword [page_length], offline_len

build_response:
    lea rdi, [response_buffer]

    lea rsi, [http_header]
    mov rcx, header_len
    rep movsb

    mov rax, [page_length]
    mov rcx, 10
    mov rbx, rdi
.convert_length:
    xor rdx, rdx
    div rcx
    push rdx
    test rax, rax
    jnz .convert_length

    cmp rdi, rbx
    je .skip_digits
.write_digits:
    pop rax
    add al, '0'
    stosb
    cmp rdi, rbx
    jne .write_digits
.skip_digits:

    lea rsi, [http_footer]
    mov rcx, footer_len
    rep movsb

    mov rsi, [page_content]
    mov rcx, [page_length]
    rep movsb

    mov rcx, [client_socket]
    lea rdx, [response_buffer]
    mov r8, rdi
    sub r8, rdx
    xor r9, r9
    call send

    mov rcx, [client_socket]
    call closesocket
    jmp server_loop

check_24data_online:
    sub rsp, 56

    lea rcx, [user_agent]
    mov rdx, 1
    xor r8, r8
    xor r9, r9
    call InternetOpenA
    test rax, rax
    jz .offline
    mov [internet_session], rax

    mov rcx, rax
    lea rdx, [status_url]
    xor r8, r8
    xor r9, r9
    mov qword [rsp + 32], 0x00800000
    mov qword [rsp + 40], 0
    call InternetOpenUrlA
    test rax, rax
    jz .close_session_offline
    mov [internet_handle], rax

    mov rcx, [internet_handle]
    call InternetCloseHandle
    mov rcx, [internet_session]
    call InternetCloseHandle
    mov eax, 1
    add rsp, 56
    ret

.close_session_offline:
    mov rcx, [internet_session]
    call InternetCloseHandle
.offline:
    xor eax, eax
    add rsp, 56
    ret

close_listen:
    mov rcx, [listen_socket]
    call closesocket

cleanup_WSA:
    call WSACleanup

error:
    sub rsp, 40
    xor rcx, rcx
    lea rdx, [error_msg]
    lea r8, [error_title]
    xor r9, r9
    call MessageBoxA
    add rsp, 40

    mov rcx, 1
    call ExitProcess