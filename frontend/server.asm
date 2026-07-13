bits 64
default rel

%ifndef LINUX
  %ifndef MACOS
    %define WINDOWS 1
  %endif
%endif

%ifdef WINDOWS
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

%elifdef MACOS
extern _socket
extern _bind
extern _listen
extern _accept
extern _recv
extern _send
extern _close
extern _open
extern _read
extern _lseek
extern _exit
extern _write

extern _index_html
extern _radar_html

%define socket _socket
%define bind _bind
%define listen _listen
%define accept _accept
%define recv _recv
%define send _send
%define close _close
%define open _open
%define read _read
%define lseek _lseek
%define exit _exit
%define write _write
%define index_html _index_html
%define radar_html _radar_html

%elifdef LINUX
extern socket
extern bind
extern listen
extern accept
extern recv
extern send
extern close
extern open
extern read
extern lseek
extern exit
extern write

extern index_html
extern radar_html
%endif

section .data
%ifdef WINDOWS
    wsa_version dw 2, 2
%endif
    sockaddr:
%ifdef MACOS
        sin_len db 16
        sin_family db 2
%else
        sin_family dw 2
%endif
        sin_port dw 0x9B1F
        sin_addr dd 0
        sin_zero times 8 db 0

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

%ifdef WINDOWS
    static_prefix db "frontend\static", 0
%else
    static_prefix db "frontend/static", 0
%endif
    error_title db "Error", 0
    error_msg db "An error occurred.", 0

section .bss
%ifdef WINDOWS
    wsa_data resb 400
%endif
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
%ifdef WINDOWS
global _start
_start:
%else
global main
main:
%endif
    sub rsp, 40
    call os_init
    test eax, eax
    jnz error

    mov rcx, 2
    mov rdx, 1
    xor r8, r8
    call os_socket
    mov [listen_socket], rax
    cmp rax, -1
    je cleanup_WSA

    mov rcx, [listen_socket]
    lea rdx, [sockaddr]
    mov r8, 16
    call os_bind
    test eax, eax
    js close_listen

    mov rcx, [listen_socket]
    mov rdx, 5
    call os_listen
    test eax, eax
    js close_listen

server_loop:
    mov rcx, [listen_socket]
    xor rdx, rdx
    xor r8, r8
    call os_accept
    cmp rax, -1
    je server_loop
    mov [client_socket], rax

    mov rcx, [client_socket]
    lea rdx, [request_buffer]
    mov r8, 2048
    xor r9, r9
    call os_recv

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
    call os_send
    jmp after_req

do_404:
    mov rcx, [client_socket]
    lea rdx, [http_404]
    mov r8, http_404_len
    xor r9, r9
    call os_send

after_req:
    mov rcx, [client_socket]
    call os_close_socket
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
    cmp eax, 0x20544547  ; "GET "
    je .is_get
    cmp eax, 0x44414548  ; "HEAD"
    jne .fail
    cmp byte [rdi + 4], ' '
    jne .fail
    add rdi, 5
    jmp .parse_body
.is_get:
    add rdi, 4
.parse_body:
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
%ifdef WINDOWS
    cmp al, '/'
    jne .put
    mov al, '\'
.put:
%endif
    stosb
    jmp .cp2
.cp2done:
    mov byte [rdi], 0

    lea rcx, [file_path]
    call os_open_file
    cmp rax, -1
    je .fail

    mov [file_handle], rax
    mov rcx, rax
    call os_get_file_size
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
    call os_send

.read:
    mov rcx, [file_handle]
    lea rdx, [file_chunk]
    mov r8d, 32768
    lea r9, [bytes_read]
    call os_read_file
    test eax, eax
    jz .done
    mov eax, [bytes_read]
    test eax, eax
    jz .done
    mov rcx, [client_socket]
    lea rdx, [file_chunk]
    mov r8d, eax
    xor r9, r9
    call os_send
    jmp .read

.done:
    mov rcx, [file_handle]
    call os_close_file
    add rsp, 64
    pop rdi
    pop rsi
    pop rbx
    ret

.fail_close:
    mov rcx, [file_handle]
    call os_close_file
.fail:
    mov rcx, [client_socket]
    lea rdx, [http_404]
    mov r8, http_404_len
    xor r9, r9
    call os_send
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
    call os_close_socket

cleanup_WSA:
    call os_cleanup

exit_process:
    xor ecx, ecx
    call os_exit

error:
    call os_error
    mov rcx, 1
    call os_exit

%ifdef WINDOWS

os_init:
    sub rsp, 40
    mov rcx, [wsa_version]
    lea rdx, [wsa_data]
    call WSAStartup
    add rsp, 40
    ret

os_cleanup:
    sub rsp, 40
    call WSACleanup
    add rsp, 40
    ret

os_socket:
    sub rsp, 40
    call socket
    add rsp, 40
    ret

os_bind:
    sub rsp, 40
    call bind
    add rsp, 40
    ret

os_listen:
    sub rsp, 40
    call listen
    add rsp, 40
    ret

os_accept:
    sub rsp, 40
    call accept
    add rsp, 40
    ret

os_recv:
    sub rsp, 40
    call recv
    add rsp, 40
    ret

os_send:
    sub rsp, 40
    call send
    add rsp, 40
    ret

os_close_socket:
    sub rsp, 40
    call closesocket
    add rsp, 40
    ret

os_open_file:
    sub rsp, 64
    mov rdx, GENERIC_READ
    mov r8d, FILE_SHARE_READ
    xor r9, r9
    mov dword [rsp + 32], OPEN_EXISTING
    mov dword [rsp + 40], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp + 48], 0
    call CreateFileA
    add rsp, 64
    ret

os_get_file_size:
    sub rsp, 40
    xor rdx, rdx
    call GetFileSize
    add rsp, 40
    ret

os_read_file:
    sub rsp, 40
    mov qword [rsp + 32], 0
    call ReadFile
    add rsp, 40
    ret

os_close_file:
    sub rsp, 40
    call CloseHandle
    add rsp, 40
    ret

os_exit:
    sub rsp, 40
    call ExitProcess
    add rsp, 40
    ret

os_error:
    sub rsp, 40
    xor rcx, rcx
    lea rdx, [error_msg]
    lea r8, [error_title]
    xor r9, r9
    call MessageBoxA
    add rsp, 40
    ret

%else ; LINUX or MACOS

os_init:
    xor eax, eax
    ret

os_cleanup:
    ret

os_socket:
    mov rdi, rcx
    mov rsi, rdx
    mov rdx, r8
    jmp socket

os_bind:
    mov rdi, rcx
    mov rsi, rdx
    mov rdx, r8
    jmp bind

os_listen:
    mov rdi, rcx
    mov rsi, rdx
    jmp listen

os_accept:
    mov rdi, rcx
    mov rsi, rdx
    mov rdx, r8
    jmp accept

os_recv:
    mov rdi, rcx
    mov rsi, rdx
    mov rdx, r8
    mov rcx, r9
    jmp recv

os_send:
    mov rdi, rcx
    mov rsi, rdx
    mov rdx, r8
    mov rcx, r9
    jmp send

os_close_socket:
    mov rdi, rcx
    jmp close

os_open_file:
    mov rdi, rcx
    xor esi, esi
    jmp open

os_get_file_size:
    push rbx
    push r12
    sub rsp, 8
    
    mov rbx, rcx ; fd
    
    mov rdi, rbx
    xor rsi, rsi
    mov rdx, 2   ; SEEK_END = 2
    call lseek
    mov r12, rax ; save size in r12
    
    mov rdi, rbx
    xor rsi, rsi
    xor rdx, rdx ; SEEK_SET = 0
    call lseek
    
    mov rax, r12 ; restore size to return in rax
    
    add rsp, 8
    pop r12
    pop rbx
    ret

os_read_file:
    push rbp
    mov rbp, rsp
    push rbx
    
    mov rbx, r9
    
    mov rdi, rcx
    mov rsi, rdx
    mov rdx, r8
    sub rsp, 8
    call read
    add rsp, 8
    
    test rax, rax
    js .error
    
    mov [rbx], eax
    mov eax, 1
    jmp .done
.error:
    xor eax, eax
.done:
    pop rbx
    pop rbp
    ret

os_close_file:
    mov rdi, rcx
    jmp close

os_exit:
    mov rdi, rcx
    jmp exit

os_error:
    mov rdi, 2
    lea rsi, [error_msg]
    mov rdx, 18
    sub rsp, 8
    call write
    add rsp, 8
    ret

%endif
