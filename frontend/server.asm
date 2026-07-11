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
extern CreateFileA
extern ReadFile
extern CloseHandle
extern GetFileSize

extern index_html
extern radar_html

GENERIC_READ equ 0x80000000
FILE_SHARE_READ equ 1
OPEN_EXISTING equ 3
FILE_ATTRIBUTE_NORMAL equ 0x80

section .data
    wsa_version dw 2, 2
    sockaddr:
        sin_family dw 2
        sin_port dw 0x9B1F
        sin_addr dd 0

    http_header db "HTTP/1.1 200 OK", 13, 10
                db "Content-Type: text/html; charset=utf-8", 13, 10
                db "Content-Length: "
    header_len equ $ - http_header

    http_ok_type db "HTTP/1.1 200 OK", 13, 10
                 db "Content-Type: "
    http_ok_type_len equ $ - http_ok_type

    http_len_tag db 13, 10, "Content-Length: "
    http_len_tag_len equ $ - http_len_tag

    http_footer db 13, 10
                db "Connection: close", 13, 10
                db 13, 10
    footer_len equ $ - http_footer

    http_404 db "HTTP/1.1 404 Not Found", 13, 10
             db "Content-Type: text/plain", 13, 10
             db "Content-Length: 9", 13, 10
             db "Connection: close", 13, 10, 13, 10
             db "Not Found"
    http_404_len equ $ - http_404

    ctype_svg db "image/svg+xml", 0
    ctype_png db "image/png", 0
    ctype_jpg db "image/jpeg", 0
    ctype_bin db "application/octet-stream", 0

    static_prefix db "frontend\static", 0
    error_title db "Error", 0
    error_msg db "An error occurred.", 0

section .bss
    wsa_data resb 400
    listen_socket resq 1
    page_content resq 1
    page_length resq 1
    response_buffer resb 65536
    client_socket resq 1
    request_buffer resb 2048
    digit_buf resb 32
    path_buffer resb 1024
    file_path resb 2048
    file_handle resq 1
    file_size resd 1
    bytes_read resd 1
    ctype_ptr resq 1
    file_chunk resb 32768

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
    mov r8, 2048
    xor r9, r9
    call recv

    lea rdi, [request_buffer]
    call parse_path
    test eax, eax
    jz do_404

    lea rsi, [path_buffer]
    call path_is_root
    test eax, eax
    jnz serve_index

    lea rsi, [path_buffer]
    call path_is_radar
    test eax, eax
    jnz serve_radar

    call try_static
    jmp after_req

serve_index:
    call index_html
    jmp send_html

serve_radar:
    call radar_html

send_html:
    mov [page_content], rax
    mov [page_length], rdx

    lea rdi, [response_buffer]
    lea rsi, [http_header]
    mov rcx, header_len
    rep movsb

    mov rax, [page_length]
    call write_decimal

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
    jmp after_req

do_404:
    mov rcx, [client_socket]
    lea rdx, [http_404]
    mov r8, http_404_len
    xor r9, r9
    call send

after_req:
    mov rcx, [client_socket]
    call closesocket
    jmp server_loop

write_decimal:
    push rbx
    push rcx
    push rdx
    push rsi
    lea rsi, [digit_buf]
    mov rbx, 10
    xor ecx, ecx
    test rax, rax
    jnz .div
    mov byte [rsi], '0'
    mov ecx, 1
    jmp .emit
.div:
    xor rdx, rdx
    div rbx
    add dl, '0'
    mov [rsi + rcx], dl
    inc ecx
    test rax, rax
    jnz .div
.emit:
    mov ebx, ecx
.out:
    dec ebx
    mov al, [rsi + rbx]
    stosb
    test ebx, ebx
    jnz .out
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

parse_path:
    mov eax, [rdi]
    cmp eax, 0x20544547
    jne .fail
    add rdi, 4
    lea rsi, [path_buffer]
    xor ecx, ecx
.next:
    movzx eax, byte [rdi]
    test al, al
    jz .done
    cmp al, ' '
    je .done
    cmp al, '?'
    je .done
    cmp al, 13
    je .done
    cmp ecx, 1000
    jae .fail
    cmp al, '%'
    jne .plain
    movzx edx, byte [rdi + 1]
    movzx r8d, byte [rdi + 2]
    call hex_byte
    mov [rsi], al
    inc rsi
    add rdi, 3
    inc ecx
    jmp .next
.plain:
    cmp al, '+'
    jne .store
    mov al, ' '
.store:
    mov [rsi], al
    inc rsi
    inc rdi
    inc ecx
    jmp .next
.done:
    mov byte [rsi], 0
    test ecx, ecx
    jnz .ok
    mov byte [path_buffer], '/'
    mov byte [path_buffer + 1], 0
.ok:
    mov eax, 1
    ret
.fail:
    xor eax, eax
    ret

hex_byte:
    push rcx
    mov eax, edx
    call hex_val
    mov ecx, eax
    shl ecx, 4
    mov eax, r8d
    call hex_val
    or eax, ecx
    pop rcx
    ret

hex_val:
    cmp al, '0'
    jb .z
    cmp al, '9'
    jbe .d
    cmp al, 'A'
    jb .z
    cmp al, 'F'
    jbe .H
    cmp al, 'a'
    jb .z
    cmp al, 'f'
    ja .z
    sub al, 'a' - 10
    ret
.H:
    sub al, 'A' - 10
    ret
.d:
    sub al, '0'
    ret
.z:
    xor eax, eax
    ret

path_is_root:
    cmp byte [rsi], '/'
    jne .no
    cmp byte [rsi + 1], 0
    jne .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

path_is_radar:
    cmp byte [rsi], '/'
    jne .no
    cmp dword [rsi + 1], 'rada'
    jne .no
    cmp byte [rsi + 5], 'r'
    jne .no
    movzx eax, byte [rsi + 6]
    test al, al
    jz .yes
    cmp al, '/'
    je .yes
.no:
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

try_static:
    push rbx
    push rsi
    push rdi
    sub rsp, 64

    lea rsi, [path_buffer]
.dot:
    cmp byte [rsi], 0
    je .okdots
    cmp word [rsi], '..'
    je .fail
    inc rsi
    jmp .dot
.okdots:

    lea rsi, [static_prefix]
    lea rdi, [file_path]
.cp1:
    lodsb
    test al, al
    jz .cp1done
    stosb
    jmp .cp1
.cp1done:
    lea rsi, [path_buffer]
.cp2:
    lodsb
    test al, al
    jz .cp2done
    cmp al, '/'
    jne .put
    mov al, '\'
.put:
    stosb
    jmp .cp2
.cp2done:
    mov byte [rdi], 0

    lea rcx, [file_path]
    mov edx, GENERIC_READ
    mov r8d, FILE_SHARE_READ
    xor r9, r9
    mov dword [rsp + 32], OPEN_EXISTING
    mov dword [rsp + 40], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp + 48], 0
    call CreateFileA
    cmp rax, -1
    je .fail

    mov [file_handle], rax
    mov rcx, rax
    xor rdx, rdx
    call GetFileSize
    cmp eax, -1
    je .fail_close
    mov [file_size], eax

    call choose_ctype

    lea rdi, [response_buffer]
    lea rsi, [http_ok_type]
    mov rcx, http_ok_type_len
    rep movsb
    mov rsi, [ctype_ptr]
.ctype:
    lodsb
    test al, al
    jz .ctype_done
    stosb
    jmp .ctype
.ctype_done:
    lea rsi, [http_len_tag]
    mov rcx, http_len_tag_len
    rep movsb
    mov eax, [file_size]
    call write_decimal
    lea rsi, [http_footer]
    mov rcx, footer_len
    rep movsb

    mov rcx, [client_socket]
    lea rdx, [response_buffer]
    mov r8, rdi
    sub r8, rdx
    xor r9, r9
    call send

.read:
    mov rcx, [file_handle]
    lea rdx, [file_chunk]
    mov r8d, 32768
    lea r9, [bytes_read]
    mov qword [rsp + 32], 0
    call ReadFile
    test eax, eax
    jz .done
    mov eax, [bytes_read]
    test eax, eax
    jz .done
    mov rcx, [client_socket]
    lea rdx, [file_chunk]
    mov r8d, eax
    xor r9, r9
    call send
    jmp .read

.done:
    mov rcx, [file_handle]
    call CloseHandle
    add rsp, 64
    pop rdi
    pop rsi
    pop rbx
    ret

.fail_close:
    mov rcx, [file_handle]
    call CloseHandle
.fail:
    mov rcx, [client_socket]
    lea rdx, [http_404]
    mov r8, http_404_len
    xor r9, r9
    call send
    add rsp, 64
    pop rdi
    pop rsi
    pop rbx
    ret

choose_ctype:
    lea rsi, [path_buffer]
    xor ecx, ecx
.len:
    cmp byte [rsi + rcx], 0
    je .got
    inc ecx
    jmp .len
.got:
.find:
    test ecx, ecx
    jz .bin
    dec ecx
    cmp byte [rsi + rcx], '.'
    jne .find
    lea rdi, [rsi + rcx]
    cmp dword [rdi], '.svg'
    je .svg
    cmp dword [rdi], '.png'
    je .png
    cmp dword [rdi], '.jpg'
    je .jpg
    jmp .bin
.svg:
    lea rax, [ctype_svg]
    jmp .set
.png:
    lea rax, [ctype_png]
    jmp .set
.jpg:
    lea rax, [ctype_jpg]
    jmp .set
.bin:
    lea rax, [ctype_bin]
.set:
    mov [ctype_ptr], rax
    ret

close_listen:
    mov rcx, [listen_socket]
    call closesocket

cleanup_WSA:
    call WSACleanup

exit_process:
    xor ecx, ecx
    call ExitProcess

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
