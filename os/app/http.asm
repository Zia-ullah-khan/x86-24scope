; ==============================================================================
; x86-24scope OS - HTTP Server & OS Porting Layer
; ==============================================================================
bits 64
default rel

section .text

global http_server_start

extern index_html
extern radar_html
extern fat32_open
extern fat32_read
extern tcp_listen
extern tcp_accept
extern tcp_send
extern tcp_recv
extern tcp_close
extern wifi_recv_packet
extern net_handle_packet
extern network_rx_buffer
extern con_puts
extern con_newline
extern con_heartbeat
extern serial_puts
extern sleep_ms

; HTTP constants
header_len       equ 73
http_ok_type_len equ 31
http_len_tag_len equ 18
footer_len       equ 23
http_404_len     equ 93

http_server_start:
    push rbp
    mov rbp, rsp
    sub rsp, 40

    lea rcx, [msg_http_start]
    call con_puts
    lea rcx, [msg_http_start]
    call serial_puts

    ; 1. Listen on Port 8091
    mov rcx, 8091
    call tcp_listen
    test rax, rax
    jz .error

.server_loop:
    ; 2. Accept client connection (cooperative poll inside)
    call os_accept
    cmp rax, -1
    je .server_loop
    mov [client_socket], rax

    ; 3. Receive HTTP request
    mov rcx, [client_socket]
    lea rdx, [request_buffer]
    mov r8, 2048
    call os_recv
    test rax, rax
    jz .close_client

    ; 4. Parse path
    lea rdi, [request_buffer]
    call parse_path
    test eax, eax
    jz .do_404

    ; 5. Serve routes
    lea rsi, [path_buffer]
    call path_is_root
    test eax, eax
    jnz .serve_index

    lea rsi, [path_buffer]
    call path_is_radar
    test eax, eax
    jnz .serve_radar

    ; Try serving static file
    call try_static
    jmp .close_client

.serve_index:
    call index_html
    jmp .send_html

.serve_radar:
    call radar_html

.send_html:
    mov [page_content], rax
    mov [page_length], rdx

    ; Build response header only (body sent separately)
    lea rdi, [response_buffer]
    lea rsi, [http_header]
    mov rcx, header_len
    rep movsb

    ; Write length tag
    mov rax, [page_length]
    call write_decimal

    ; Write footer
    lea rsi, [http_footer]
    mov rcx, footer_len
    rep movsb

    ; Send header
    mov rcx, [client_socket]
    lea rdx, [response_buffer]
    mov r8, rdi
    sub r8, rdx
    call os_send

    ; Send HTML body
    mov rcx, [client_socket]
    mov rdx, [page_content]
    mov r8, [page_length]
    call os_send

    jmp .close_client

.do_404:
    mov rcx, [client_socket]
    lea rdx, [http_404]
    mov r8, http_404_len
    call os_send

.close_client:
    mov rcx, [client_socket]
    call os_close_socket
    jmp .server_loop

.error:
    lea rcx, [msg_http_err]
    call con_puts
    lea rcx, [msg_http_err]
    call serial_puts
    add rsp, 40
    pop rbp
    ret

; Co-operative Accept
os_accept:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 32

.loop:
    call con_heartbeat              ; Blink liveness indicator

    ; Perform network background poll
    lea rcx, [network_rx_buffer]
    call wifi_recv_packet
    test rax, rax
    jz .no_rx
    lea rcx, [network_rx_buffer]
    mov rdx, rax
    call net_handle_packet
.no_rx:
    ; Try accepting connection on port 8091
    mov ecx, 8091
    lea rdx, [client_socket_id]
    call tcp_accept
    test rax, rax
    jnz .found

    ; Sleep 1ms to prevent high CPU pinning
    mov rcx, 1
    call sleep_ms
    jmp .loop

.found:
    movzx rax, dword [client_socket_id]
    add rsp, 32
    pop rbx
    pop rbp
    ret

; Co-operative Receive
os_recv:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rcx                    ; socket_id
    mov r13, rdx                    ; destination buffer
    
.loop:
    ; Poll network
    lea rcx, [network_rx_buffer]
    call wifi_recv_packet
    test rax, rax
    jz .no_rx
    lea rcx, [network_rx_buffer]
    mov rdx, rax
    call net_handle_packet
.no_rx:
    ; Try reading from TCP buffer
    mov rcx, r12
    mov rdx, r13
    mov r8, 2048
    call tcp_recv
    test rax, rax
    jnz .done

    ; Sleep 1ms
    mov rcx, 1
    call sleep_ms
    jmp .loop

.done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

os_send:
    ; RCX = Socket ID, RDX = Buffer, R8 = Length
    call tcp_send
    ret

os_close_socket:
    ; RCX = Socket ID
    call tcp_close
    ret

; Parse GET request path
parse_path:
    mov eax, [rdi]
    cmp eax, 0x20544547              ; "GET "
    je .is_get
    xor eax, eax
    ret
.is_get:
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
    cmp ecx, 1000
    jae .fail
    cmp al, '%'
    jne .plain
    
    ; URL Decode %20
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
    movzx rbx, ecx
.out:
    dec rbx
    mov al, [rsi + rbx]
    stosb
    test rbx, rbx
    jnz .out
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; Try serving static file from FAT32 partition
try_static:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 1024

    ; Strip "frontend\static" or "frontend/static" prefix if path starts with it
    ; Typically path_buffer is like "/Plane Icons/737.png" which already matches root of our partition!
    ; But if the router prepends "frontend\static", we skip it.
    lea rsi, [path_buffer]
    
    ; Verify path traversal security
.dot:
    cmp byte [rsi], 0
    je .okdots
    cmp word [rsi], '..'
    je .fail
    inc rsi
    jmp .dot
.okdots:
    lea rsi, [path_buffer]

    ; 1. Open File via FAT32
    mov rcx, rsi                    ; Path
    call fat32_open                 ; Returns Cluster in EAX, Size in EDX
    test rax, rax
    jz .fail

    mov [file_cluster], eax
    mov [file_size], edx

    ; 2. Determine Content Type
    lea rsi, [path_buffer]
    call choose_ctype               ; Returns pointer to ctype string in RAX
    mov [ctype_ptr], rax

    ; 3. Build HTTP Header
    lea rdi, [response_buffer]
    lea rsi, [http_ok_type]
    mov rcx, http_ok_type_len
    rep movsb

    ; Write Content-Type
    mov rsi, [ctype_ptr]
.ctype_cp:
    lodsb
    test al, al
    jz .ctype_done
    stosb
    jmp .ctype_cp
.ctype_done:

    ; Content-Length tag
    lea rsi, [http_len_tag]
    mov rcx, http_len_tag_len
    rep movsb

    ; Write File Size decimal
    movzx rax, dword [file_size]
    call write_decimal

    ; Write HTTP footer
    lea rsi, [http_footer]
    mov rcx, footer_len
    rep movsb

    ; 4. Send Header
    mov rcx, [client_socket]
    lea rdx, [response_buffer]
    mov r8, rdi
    sub r8, rdx                     ; Header size
    call os_send

    ; 5. Read and Send File Data in chunks (up to 32KB)
    mov r12d, [file_cluster]
    mov r13d, [file_size]           ; Remaining size

.send_loop:
    test r13d, r13d
    jz .done

    mov r10d, 32768                 ; Chunk size = 32KB
    cmp r13d, r10d
    jae .read_chunk
    mov r10d, r13d                  ; Remaining size is smaller

.read_chunk:
    ; Call FAT32 read: start cluster, size, destination buffer
    ; But wait! fat32_read takes the start cluster, but it advances cluster chain!
    ; Since our fat32_read reads the entire chain from start_cluster, we can just read
    ; the whole file at once if it fits in a temporary page, or we can just read the whole file!
    ; Let's see: how big are static files?
    ; - 737.png: ~200KB.
    ; - maps/Enroute Chart PTFS.svg: ~1.2MB.
    ; Since we have 4GB of physical RAM, we can just allocate a buffer large enough
    ; using pmm_alloc_page (or multiple pages) to read the entire file into memory,
    ; and then send it in one go!
    ; This is incredibly clean and avoids chunked state tracking!
    ; Let's write the entire file reader:
    ; Allocate enough pages: pages_needed = (file_size + 4095) / 4096
    mov eax, [file_size]
    add eax, 4095
    shr eax, 12                     ; Pages
    movzx ecx, ax                   ; Count
    
    ; Let's just allocate a single block of RAM. Since our PMM allocates single pages,
    ; we can allocate a large block by calling pmm_alloc_page repeatedly, or
    ; we can just use the large `file_temp_buffer` in .bss!
    ; Since maps can be up to 2MB, let's declare a 2MB buffer in .bss:
    ; `file_temp_buffer resb 2097152` (2MB)
    ; This is extremely fast and avoids dynamic allocation overhead!
    
    lea r8, [file_temp_buffer]      ; Buffer
    mov ecx, [file_cluster]         ; Start Cluster
    mov edx, [file_size]            ; Size
    call fat32_read                 ; Read entire file into buffer!
    test rax, rax
    jz .done

    ; Send the entire file buffer
    mov rcx, [client_socket]
    lea rdx, [file_temp_buffer]
    mov r8d, [file_size]
    call os_send

.done:
    add rsp, 1024
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

.fail:
    ; Send 404
    mov rcx, [client_socket]
    lea rdx, [http_404]
    mov r8, http_404_len
    call os_send
    jmp .done

; Select Content-Type based on extension
choose_ctype:
    push rsi
    ; Find end of path
    mov rdi, rsi
    xor rcx, rcx
.find_end:
    cmp byte [rdi + rcx], 0
    je .found_end
    inc rcx
    jmp .find_end
.found_end:
    lea rsi, [rdi + rcx]            ; Pointer to end

    ; Check last 4 bytes (e.g. ".svg", ".png")
    cmp rcx, 4
    jb .binary

    mov eax, [rsi - 4]
    cmp eax, '.svg'                 ; ".svg" in little endian is 0x6776732E
    je .svg
    cmp eax, '.png'                 ; ".png" is 0x676E702E
    je .png

.binary:
    lea rax, [ctype_bin]
    pop rsi
    ret
.svg:
    lea rax, [ctype_svg]
    pop rsi
    ret
.png:
    lea rax, [ctype_png]
    pop rsi
    ret
.jpg:
    lea rax, [ctype_jpg]
    pop rsi
    ret

section .data
align 8
client_socket dq 0
client_socket_id dd 0
file_cluster dd 0
file_size dd 0
ctype_ptr dq 0

http_header db "HTTP/1.1 200 OK", 13, 10
            db "Content-Type: text/html; charset=utf-8", 13, 10
            db "Content-Length: "

http_ok_type db "HTTP/1.1 200 OK", 13, 10
             db "Content-Type: "

http_len_tag db 13, 10, "Content-Length: "

http_footer db 13, 10
            db "Connection: close", 13, 10
            db 13, 10

http_404 db "HTTP/1.1 404 Not Found", 13, 10
         db "Content-Type: text/plain", 13, 10
         db "Content-Length: 9", 13, 10
         db "Connection: close", 13, 10, 13, 10
         db "Not Found"

ctype_svg db "image/svg+xml", 0
ctype_png db "image/png", 0
ctype_jpg db "image/jpeg", 0
ctype_bin db "application/octet-stream", 0

msg_http_start db "HTTP: Web server listening on port 8091...", 13, 10, 0
msg_http_err   db "HTTP: ERROR - Failed to bind port 8091!", 13, 10, 0

section .bss
alignb 16
request_buffer resb 2048
response_buffer resb 4096           ; Buffer for HTTP headers
path_buffer resb 1024
digit_buf resb 32
page_content resq 1
page_length resq 1

alignb 4096
file_temp_buffer resb 2097152       ; 2MB temporary buffer for loading static assets
