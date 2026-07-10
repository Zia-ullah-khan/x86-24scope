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

section .data
    wsa_version dw 2, 2
    sockaddr:
        sin_family dw 2
        sin_port dw 0x901F
        sin_addr dd 0
    
    http_response db "HTTP/1.1 200 OK", 13, 10
                  db "Content-Type: text/html; charset=utf-8", 13, 10
                  db "Content-Length: 39", 13, 10
                  db "Connection: close", 13, 10
                  db 13, 10
                  db "<html><body><h1>Frontend</h1></body></html>"
    resp_len      equ $ - http_response

section .bss
    wsa_data resb 400
    listen_socket resq 1
    client_socket resq 1
    request_buffer resb 1024

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

    mov rcx, [client_socket]
    lea rdx, [http_response]
    mov r8, resp_len
    xor r9, r9
    call send

    mov rcx, [client_socket]
    call closesocket
    jmp server_loop

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

section .data
    error_title db "Error", 0
    error_msg db "An error occurred.", 0