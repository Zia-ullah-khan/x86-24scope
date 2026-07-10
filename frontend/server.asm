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

extern index_html

section .data
    wsa_version dw 2, 2
    sockaddr:
        sin_family dw 2
        sin_port dw 0x901F
        sin_addr dd 0
    
    http_header db "HTTP/1.1 200 OK", 13, 10
                db "Content-Type: text/html; charset=utf-8", 13, 10
                db "Content-Length: "
    header_len equ $ - http_header
    
    http_footer db 13, 10
                db "Connection: close", 13, 10
                db 13, 10
    footer_len equ $ - http_footer
    
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

    call index_html
    mov [page_content], rax
    mov [page_length], rdx

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