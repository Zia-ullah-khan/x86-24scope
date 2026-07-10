section .data
    index_page db "<!DOCTYPE html>", 13, 10
                db "<html>", 13, 10
                db "<head>", 13, 10
                db '<meta charset="utf-8">', 13, 10
                db '<meta name="viewport" content="width=device-width, initial-scale=1.0">', 13, 10
                db "<title>24Scope</title>", 13, 10
                db "<style>", 13, 10
                db "  :root {", 13, 10
                db "    color-scheme: dark;", 13, 10
                db "    --bg: #08111f;", 13, 10
                db "    --panel: rgba(15, 23, 42, 0.88);", 13, 10
                db "    --text: #e5eefc;", 13, 10
                db "    --muted: #8ea2c8;", 13, 10
                db "    --accent: #56d4ff;", 13, 10
                db "    --accent-2: #8b5cf6;", 13, 10
                db "  }", 13, 10
                db "  * { box-sizing: border-box; }", 13, 10
                db "  body {", 13, 10
                db "    margin: 0;", 13, 10
                db "    min-height: 100vh;", 13, 10
                db "    display: grid;", 13, 10
                db "    place-items: center;", 13, 10
                db "    font-family: Arial, Helvetica, sans-serif;", 13, 10
                db "    color: var(--text);", 13, 10
                db "    background:", 13, 10
                db "      radial-gradient(circle at top, rgba(86, 212, 255, 0.18), transparent 34%),", 13, 10
                db "      radial-gradient(circle at bottom right, rgba(139, 92, 246, 0.16), transparent 30%),", 13, 10
                db "      linear-gradient(135deg, #050914 0%, #0a1322 45%, #111c33 100%);", 13, 10
                db "    padding: 32px;", 13, 10
                db "  }", 13, 10
                db "  .card {", 13, 10
                db "    width: min(760px, 100%);", 13, 10
                db "    padding: 40px 36px;", 13, 10
                db "    border: 1px solid rgba(134, 166, 221, 0.22);", 13, 10
                db "    border-radius: 24px;", 13, 10
                db "    background: var(--panel);", 13, 10
                db "    box-shadow: 0 24px 80px rgba(0, 0, 0, 0.4);", 13, 10
                db "    backdrop-filter: blur(14px);", 13, 10
                db "  }", 13, 10
                db "  .eyebrow {", 13, 10
                db "    margin: 0 0 14px;", 13, 10
                db "    color: var(--accent);", 13, 10
                db "    text-transform: uppercase;", 13, 10
                db "    letter-spacing: 0.2em;", 13, 10
                db "    font-size: 0.78rem;", 13, 10
                db "    font-weight: 700;", 13, 10
                db "  }", 13, 10
                db "  h1 {", 13, 10
                db "    margin: 0;", 13, 10
                db "    font-size: clamp(2.4rem, 6vw, 4.8rem);", 13, 10
                db "    line-height: 0.95;", 13, 10
                db "    letter-spacing: -0.05em;", 13, 10
                db "  }", 13, 10
                db "  .accent { color: var(--accent); }", 13, 10
                db "  .accent-2 { color: var(--accent-2); }", 13, 10
                db "  p {", 13, 10
                db "    margin: 18px 0 0;", 13, 10
                db "    max-width: 60ch;", 13, 10
                db "    color: var(--muted);", 13, 10
                db "    font-size: 1.05rem;", 13, 10
                db "    line-height: 1.7;", 13, 10
                db "  }", 13, 10
                db "  .tag {", 13, 10
                db "    display: inline-block;", 13, 10
                db "    margin-top: 26px;", 13, 10
                db "    padding: 10px 14px;", 13, 10
                db "    border-radius: 999px;", 13, 10
                db "    border: 1px solid rgba(86, 212, 255, 0.3);", 13, 10
                db "    background: rgba(86, 212, 255, 0.08);", 13, 10
                db "    color: #bfeeff;", 13, 10
                db "    font-size: 0.95rem;", 13, 10
                db "  }", 13, 10
                db "</style>", 13, 10
                db "</head>", 13, 10
                db "<body>", 13, 10
                db '<main class="card">', 13, 10
                db '<p class="eyebrow">x86 assembly webapp</p>', 13, 10
                db '<h1>This will be an <span class="accent">x86 ASM</span> webapp.</h1>', 13, 10
                db '<h1>It will be a <span class="accent-2">duplicate of 24Spy</span>.</h1>', 13, 10
                db "<p>Low-level code, direct HTTP responses, and a custom frontend shell built entirely in assembly.</p>", 13, 10
                db '<div class="tag">Prototype interface in progress</div>', 13, 10
                db "</main>", 13, 10
                db "</body>", 13, 10
                db "</html>"
    index_len equ $ - index_page

section .text
    global index_html
    
index_html:
    lea rax, [index_page]
    mov rdx, index_len
    ret

