bits 64
default rel

%ifdef MACOS
  %define index_html _index_html
%endif

section .data
    index_page:
        incbin "frontend/pages/source/index.html"
    index_len equ $ - index_page

section .text
    global index_html
    
index_html:
    lea rax, [index_page]
    mov rdx, index_len
    ret