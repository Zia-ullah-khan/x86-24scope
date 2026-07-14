bits 64
default rel

%ifdef MACOS
  %define radar_html _radar_html
%endif

section .data
    radar_page:
        incbin "frontend/pages/source/radar.html"
    radar_len equ $ - radar_page

section .text
    global radar_html

radar_html:
    lea rax, [radar_page]
    mov rdx, radar_len
    ret