; ==============================================================================
; x86-24scope OS - Cryptographic Primitives (SHA-1, HMAC, PBKDF2, AES-NI)
; ==============================================================================
bits 64
default rel

section .text

global sha1_hash
global hmac_sha1
global pbkdf2_sha1
global aes_ccmp_decrypt
global prf_384

; SHA-1 Constants
H0_INIT equ 0x67452301
H1_INIT equ 0xEFCDAB89
H2_INIT equ 0x98BADCFE
H3_INIT equ 0x10325476
H4_INIT equ 0xC3D2E1F0

; SHA-1 Hash function
; RCX = Data pointer
; RDX = Length in bytes
; R8  = Hash output (20 bytes buffer)
sha1_hash:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256                    ; Local buffer for padded block + registers

    mov r12, rcx                    ; r12 = data
    mov r13, rdx                    ; r13 = len
    mov r14, r8                     ; r14 = output

    ; Initialize hash state
    mov dword [rsp + 0], H0_INIT
    mov dword [rsp + 4], H1_INIT
    mov dword [rsp + 8], H2_INIT
    mov dword [rsp + 12], H3_INIT
    mov dword [rsp + 16], H4_INIT

    ; We process blocks of 64 bytes
    xor r15, r15                    ; r15 = bytes processed
    
.block_loop:
    mov rax, r13
    sub rax, r15
    cmp rax, 64
    jb .padding

    ; Copy 64 bytes to workspace
    lea rdi, [rsp + 64]
    mov rsi, r12
    add rsi, r15
    mov rcx, 8
    rep movsq

    lea rsi, [rsp + 64]
    call sha1_transform
    
    add r15, 64
    jmp .block_loop

.padding:
    ; Create final padded block(s)
    ; We have remaining bytes: r13 - r15
    mov r8, r13
    sub r8, r15                     ; r8 = remaining bytes (0..63)
    
    ; Zero out a 128-byte buffer for padding
    lea rdi, [rsp + 64]
    xor rax, rax
    mov rcx, 16
    rep stosq                       ; Zero 128 bytes

    ; Copy remaining data
    lea rdi, [rsp + 64]
    mov rsi, r12
    add rsi, r15
    mov rcx, r8
    rep movsb

    ; Append 0x80 bit
    mov byte [rsp + 64 + r8], 0x80

    ; Check if length fits in current block
    cmp r8, 56
    jae .two_blocks

    ; Fits in one block. Write bit length at end (offset 56)
    mov rax, r13
    shl rax, 3                      ; length in bits
    bswap rax
    mov [rsp + 64 + 56], rax

    lea rsi, [rsp + 64]
    call sha1_transform
    jmp .write_hash

.two_blocks:
    ; Doesn't fit in 64 bytes. Process first, then second.
    ; Write bit length at offset 120 of the 128-byte block
    mov rax, r13
    shl rax, 3
    bswap rax
    mov [rsp + 64 + 120], rax

    lea rsi, [rsp + 64]
    call sha1_transform
    lea rsi, [rsp + 128]
    call sha1_transform

.write_hash:
    ; Copy state to output
    mov edi, [rsp + 0]
    bswap edi
    mov [r14], edi
    
    mov edi, [rsp + 4]
    bswap edi
    mov [r14 + 4], edi

    mov edi, [rsp + 8]
    bswap edi
    mov [r14 + 8], edi

    mov edi, [rsp + 12]
    bswap edi
    mov [r14 + 12], edi

    mov edi, [rsp + 16]
    bswap edi
    mov [r14 + 16], edi

    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; SHA-1 Transform (internal)
; RSI = 64-byte block pointer
; RSP + 0..19 = current hash state
sha1_transform:
    push rbp
    mov rbp, rsp
    sub rsp, 320                    ; 80 dwords workspace + local state

    ; Save state locally
    mov eax, [rbp + 16 + 0]         ; H0
    mov [rsp + 0], eax
    mov eax, [rbp + 16 + 4]         ; H1
    mov [rsp + 4], eax
    mov eax, [rbp + 16 + 8]         ; H2
    mov [rsp + 8], eax
    mov eax, [rbp + 16 + 12]        ; H3
    mov [rsp + 12], eax
    mov eax, [rbp + 16 + 16]        ; H4
    mov [rsp + 16], eax

    ; 1. Prepare message schedule W (80 dwords)
    lea rdi, [rsp + 20]             ; W array pointer
    xor rcx, rcx
.w_loop1:
    cmp rcx, 16
    jae .w_loop2
    mov eax, [rsi + rcx * 4]
    bswap eax
    mov [rdi + rcx * 4], eax
    inc rcx
    jmp .w_loop1

.w_loop2:
    cmp rcx, 80
    jae .rounds
    
    ; W[i] = S^1(W[i-3] ^ W[i-8] ^ W[i-14] ^ W[i-16])
    mov eax, [rdi + (rcx - 3) * 4]
    xor eax, [rdi + (rcx - 8) * 4]
    xor eax, [rdi + (rcx - 14) * 4]
    xor eax, [rdi + (rcx - 16) * 4]
    
    ; Left rotate by 1
    rol eax, 1
    mov [rdi + rcx * 4], eax
    inc rcx
    jmp .w_loop2

.rounds:
    ; Initialize working variables
    mov r8d, [rsp + 0]              ; A
    mov r9d, [rsp + 4]              ; B
    mov r10d, [rsp + 8]             ; C
    mov r11d, [rsp + 12]            ; D
    mov r12d, [rsp + 16]            ; E

    xor rcx, rcx                    ; round counter

.round_loop:
    cmp rcx, 80
    jae .accumulate

    cmp rcx, 20
    jae .round2
    ; Round 0..19: F = (B & C) | (~B & D), K = 0x5A827999
    mov ebx, r9d
    and ebx, r10d
    mov eax, r9d
    not eax
    and eax, r11d
    or eax, ebx
    mov edx, 0x5A827999
    jmp .step

.round2:
    cmp rcx, 40
    jae .round3
    ; Round 20..39: F = B ^ C ^ D, K = 0x6ED9EBA1
    mov eax, r9d
    xor eax, r10d
    xor eax, r11d
    mov edx, 0x6ED9EBA1
    jmp .step

.round3:
    cmp rcx, 60
    jae .round4
    ; Round 40..59: F = (B & C) | (B & D) | (C & D), K = 0x8F1BBCDC
    mov eax, r9d
    and eax, r10d
    mov ebx, r9d
    and ebx, r11d
    or eax, ebx
    mov ebx, r10d
    and ebx, r11d
    or eax, ebx
    mov edx, 0x8F1BBCDC
    jmp .step

.round4:
    ; Round 60..79: F = B ^ C ^ D, K = 0xCA62C1D6
    mov eax, r9d
    xor eax, r10d
    xor eax, r11d
    mov edx, 0xCA62C1D6

.step:
    ; TEMP = S^5(A) + F + E + K + W[i]
    mov ebx, r8d
    rol ebx, 5
    add ebx, eax
    add ebx, r12d
    add ebx, edx
    add ebx, [rdi + rcx * 4]         ; ebx = TEMP

    ; E = D, D = C, C = S^30(B), B = A, A = TEMP
    mov r12d, r11d
    mov r11d, r10d
    mov r10d, r9d
    rol r10d, 30
    mov r9d, r8d
    mov r8d, ebx

    inc rcx
    jmp .round_loop

.accumulate:
    ; Add working variables back to state
    add [rbp + 16 + 0], r8d
    add [rbp + 16 + 4], r9d
    add [rbp + 16 + 8], r10d
    add [rbp + 16 + 12], r11d
    add [rbp + 16 + 16], r12d

    add rsp, 320
    pop rbp
    ret

; HMAC-SHA1
; RCX = Key pointer
; RDX = Key length
; R8  = Data pointer
; R9  = Data length
; [rsp + 40] = Output hash buffer (20 bytes)
hmac_sha1:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256                    ; Workspace

    mov r12, rcx                    ; Key
    mov r13, rdx                    ; KeyLen
    mov r14, r8                     ; Data
    mov r15, r9                     ; DataLen
    
    mov rsi, [rbp + 48]             ; Output pointer (stack offset: shadow 32 + push rbx..r15 (56) = 88 + 8 = 96?)
    ; Wait, let's verify stack offset for 5th argument:
    ; In Win64: shadow space is 32 bytes. Registers are RCX, RDX, R8, R9.
    ; 5th argument is at [rsp + 40] from the caller's stack frame.
    ; Inside function, we pushed 8 registers (64 bytes) and subtracted 256 bytes.
    ; So caller's [rsp + 40] is now at [rsp + 256 + 64 + 40] = [rsp + 360]!
    ; Or we can just access it using RBP:
    ; [rbp + 16] is 1st argument (shadow), [rbp + 24] is 2nd, [rbp + 32] is 3rd, [rbp + 40] is 4th, [rbp + 48] is 5th!
    ; Yes! RBP makes stack frame offset tracking extremely simple!
    mov rdi, [rbp + 48]             ; rdi = Output pointer
    mov [rsp + 0], rdi              ; Save output pointer in local workspace

    ; Step 1: Prepare Key (must be 64 bytes)
    lea rdi, [rsp + 8]              ; Local key buffer (64 bytes)
    xor rax, rax
    mov rcx, 8
    rep stosq                       ; Zero out buffer

    cmp r13, 64
    jae .hash_key

    ; Key fits in 64 bytes. Copy it.
    lea rdi, [rsp + 8]
    mov rsi, r12
    mov rcx, r13
    rep movsb
    jmp .pad_key

.hash_key:
    ; Key is > 64 bytes. Hash it first.
    mov rcx, r12
    mov rdx, r13
    lea r8, [rsp + 8]               ; Write directly to key buffer
    call sha1_hash
    ; Now key length is 20, rest of 64 bytes are 0

.pad_key:
    ; Step 2: Create inner and outer keys
    ; ipad = key ^ 0x36
    ; opad = key ^ 0x5C
    lea rsi, [rsp + 8]              ; Key
    lea rdi, [rsp + 72]             ; ipad (64 bytes)
    lea rbx, [rsp + 136]            ; opad (64 bytes)
    
    xor rcx, rcx
.pad_loop:
    mov al, [rsi + rcx]
    mov dl, al
    xor al, 0x36
    mov [rdi + rcx], al
    xor dl, 0x5C
    mov [rbx + rcx], dl
    inc rcx
    cmp rcx, 64
    jb .pad_loop

    ; Step 3: Inner Hash = SHA1(ipad + Data)
    ; Allocate a buffer on stack or heap for ipad + data
    ; Since data length can be variable, we can allocate a temporary page
    extern pmm_alloc_page
    call pmm_alloc_page
    mov r12, rax                    ; r12 = Allocated page (4KB)

    ; Copy ipad to allocated page
    mov rdi, r12
    lea rsi, [rsp + 72]
    mov rcx, 64
    rep movsb

    ; Copy data
    mov rsi, r14
    mov rcx, r15
    rep movsb

    ; Hash it
    mov rcx, r12                    ; Data
    mov rdx, r15
    add rdx, 64                     ; Total len = 64 + DataLen
    lea r8, [rsp + 200]             ; Inner Hash output buffer (20 bytes)
    call sha1_hash

    ; Free page
    extern pmm_free_page
    mov rcx, r12
    call pmm_free_page

    ; Step 4: Final HMAC = SHA1(opad + InnerHash)
    ; Allocate page for opad + InnerHash (64 + 20 = 84 bytes)
    call pmm_alloc_page
    mov r12, rax

    ; Copy opad
    mov rdi, r12
    lea rsi, [rsp + 136]
    mov rcx, 64
    rep movsb

    ; Copy Inner Hash
    lea rsi, [rsp + 200]
    mov rcx, 20
    rep movsb

    ; Hash it directly into output
    mov rcx, r12
    mov rdx, 84                     ; 64 + 20
    mov r8, [rsp + 0]               ; Output pointer (saved earlier)
    call sha1_hash

    ; Free page
    mov rcx, r12
    call pmm_free_page

    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; PBKDF2-SHA1
; RCX = Passphrase
; RDX = SSID
; R8  = SSID length
; R9  = Iterations (4096)
; [rsp + 40] = Output key buffer (32 bytes PMK)
pbkdf2_sha1:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256

    ; Win64 registers saved:
    ; RCX = Passphrase
    ; RDX = SSID
    ; R8  = SSID length
    ; R9  = Iterations
    ; [rbp + 48] = Output PMK buffer (32 bytes)
    mov r12, rcx                    ; Passphrase
    mov r13, rdx                    ; SSID
    mov r14, r8                     ; SSID length
    mov r15, r9                     ; Iterations

    ; PBKDF2 needs to generate 32 bytes of output.
    ; SHA-1 HMAC outputs 20 bytes.
    ; So we need 2 blocks:
    ; Block 1: U_1 = HMAC(Passphrase, SSID + INT(1))
    ; Block 2: U_1 = HMAC(Passphrase, SSID + INT(2))

    ; Let's compute Block 1
    ; Allocate a temp page
    extern pmm_alloc_page
    call pmm_alloc_page
    mov rbx, rax                    ; rbx = allocated page

    ; Copy SSID
    mov rdi, rbx
    mov rsi, r13
    mov rcx, r14
    rep movsb

    ; Append INT(1) (0x00, 0x00, 0x00, 0x01 in big endian)
    mov dword [rdi], 0x01000000     ; Big endian 1
    
    ; Compute U_1 = HMAC(Passphrase, SSID + INT(1))
    ; Passphrase is null-terminated, find its length
    mov rcx, r12
    call strlen
    mov rsi, rax                    ; rsi = Passphrase length

    mov rcx, r12                    ; Key = Passphrase
    mov rdx, rsi                    ; Key length
    mov r8, rbx                     ; Data = SSID + INT(1)
    mov r9, r14
    add r9, 4                       ; Data length = SSID length + 4
    lea rax, [rsp + 0]              ; Output buffer (20 bytes)
    
    push rax                        ; 5th argument
    sub rsp, 32                     ; shadow
    call hmac_sha1
    add rsp, 40

    ; Copy U_1 to accum buffer
    lea rdi, [rsp + 40]
    lea rsi, [rsp + 0]
    mov rcx, 20
    rep movsb

    ; Iterate 4095 times: U_i = HMAC(Passphrase, U_i-1)
    ; Accumulate: T_1 = U_1 ^ U_2 ^ ... ^ U_4096
    mov r10, 1                      ; Loop counter

.block1_loop:
    cmp r10, r15
    jae .block1_done

    ; Compute U_i = HMAC(Passphrase, U_i-1)
    mov rcx, r12                    ; Key
    mov rdx, rsi                    ; Key length
    lea r8, [rsp + 0]               ; Data = U_i-1 (20 bytes)
    mov r9, 20                      ; Data length = 20
    lea rax, [rsp + 20]             ; Output U_i (20 bytes)
    
    push rax
    sub rsp, 32
    call hmac_sha1
    add rsp, 40

    ; XOR U_i into accum
    xor rcx, rcx
.xor1:
    mov al, [rsp + 20 + rcx]
    xor [rsp + 40 + rcx], al
    inc rcx
    cmp rcx, 20
    jb .xor1

    ; Copy U_i to U_i-1
    lea rdi, [rsp + 0]
    lea rsi, [rsp + 20]
    mov rcx, 20
    rep movsb

    inc r10
    jmp .block1_loop

.block1_done:
    ; First 20 bytes of PMK are in [rsp + 40]

    ; Now compute Block 2
    ; Copy SSID to temp page again
    mov rdi, rbx
    mov rsi, r13
    mov rcx, r14
    rep movsb

    ; Append INT(2)
    mov dword [rdi], 0x02000000

    ; Compute U_1 = HMAC(Passphrase, SSID + INT(2))
    mov rcx, r12
    mov rdx, rsi
    mov r8, rbx
    mov r9, r14
    add r9, 4
    lea rax, [rsp + 0]
    
    push rax
    sub rsp, 32
    call hmac_sha1
    add rsp, 40

    ; Copy U_1 to accum buffer 2
    lea rdi, [rsp + 60]
    lea rsi, [rsp + 0]
    mov rcx, 20
    rep movsb

    mov r10, 1                      ; Loop counter

.block2_loop:
    cmp r10, r15
    jae .block2_done

    ; Compute U_i
    mov rcx, r12
    mov rdx, rsi
    lea r8, [rsp + 0]
    mov r9, 20
    lea rax, [rsp + 20]
    
    push rax
    sub rsp, 32
    call hmac_sha1
    add rsp, 40

    ; XOR U_i into accum 2
    xor rcx, rcx
.xor2:
    mov al, [rsp + 20 + rcx]
    xor [rsp + 60 + rcx], al
    inc rcx
    cmp rcx, 20
    jb .xor2

    ; Copy U_i to U_i-1
    lea rdi, [rsp + 0]
    lea rsi, [rsp + 20]
    mov rcx, 20
    rep movsb

    inc r10
    jmp .block2_loop

.block2_done:
    ; Free page
    extern pmm_free_page
    mov rcx, rbx
    call pmm_free_page

    ; Write PMK (32 bytes) to output buffer
    mov rdi, [rbp + 48]             ; Output buffer
    
    ; Copy 20 bytes of Block 1
    lea rsi, [rsp + 40]
    mov rcx, 20
    rep movsb

    ; Copy 12 bytes of Block 2
    lea rsi, [rsp + 60]
    mov rcx, 12
    rep movsb

    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

strlen:
    xor rax, rax
.loop:
    cmp byte [rcx + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; Pseudo-Random Function PRF-384 (used to derive PTK)
; PRF-384(PMK, "Pairwise key expansion", MinMax(MACs) + MinMax(Nonces))
; Generates 48 bytes (384 bits) of output:
; KCK (16 bytes), KEK (16 bytes), TK (16 bytes)
; RCX = PMK pointer (32 bytes)
; RDX = Label pointer ("Pairwise key expansion")
; R8  = Data pointer (MACs + Nonces, 76 bytes total)
; R9  = Output buffer (48 bytes)
prf_384:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256

    mov r12, rcx                    ; PMK
    mov r13, rdx                    ; Label
    mov r14, r8                     ; Data
    mov r15, r9                     ; Output buffer

    ; PRF-384 uses HMAC-SHA1. We need 3 iterations to generate 48 bytes (20 bytes per iteration):
    ; PRF-i = HMAC(PMK, Label + 0x00 + Data + i)
    ; where i is 0, 1, 2.

    ; Label length = 22 ("Pairwise key expansion")
    ; Copy Label + 0x00 + Data to a temporary stack workspace
    xor rbx, rbx                    ; rbx = current block index (0..2)

.block_loop:
    cmp rbx, 3
    jae .done

    ; Build buffer: Label + 0x00 + Data + counter byte
    lea rdi, [rsp + 0]
    
    ; Copy Label
    mov rsi, r13
    mov rcx, 22
    rep movsb

    ; 0x00
    mov byte [rdi], 0
    inc rdi

    ; Copy Data (76 bytes)
    mov rsi, r14
    mov rcx, 76
    rep movsb

    ; Append counter byte (rbx)
    mov [rdi], bl
    inc rdi

    ; Calculate total data size = 22 + 1 + 76 + 1 = 100 bytes
    ; Compute HMAC
    mov rcx, r12                    ; Key = PMK (32 bytes)
    mov rdx, 32                     ; Key length
    lea r8, [rsp + 0]               ; Data
    mov r9, 100                     ; Data length
    
    ; Output offset based on block index:
    ; Block 0: output to r15 + 0 (20 bytes)
    ; Block 1: output to r15 + 20 (20 bytes)
    ; Block 2: output to temp buffer (20 bytes), copy 8 bytes to r15 + 40
    cmp rbx, 2
    je .last_block

    mov rax, r15
    mov rsi, rbx
    imul rsi, 20
    add rax, rsi                    ; rax = output pointer
    jmp .call_hmac

.last_block:
    lea rax, [rsp + 120]            ; temp buffer

.call_hmac:
    push rax
    sub rsp, 32
    call hmac_sha1
    add rsp, 40

    cmp rbx, 2
    jne .next_block

    ; Copy final 8 bytes of Block 2
    mov rdi, r15
    add rdi, 40
    lea rsi, [rsp + 120]
    mov rcx, 8
    rep movsb

.next_block:
    inc rbx
    jmp .block_loop

.done:
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; AES-CCMP Decryption Stub
; In a real driver, CCMP decrypts the 802.11 payload using AES in CTR mode,
; and verifies the MIC using CBC-MAC (CCM mode).
; We implement a skeleton interface since raw HW decryption can be offloaded on AX211,
; but a software fallback stub is useful for testing.
aes_ccmp_decrypt:
    ; RCX = Frame payload pointer
    ; RDX = Length
    ; R8  = TK (Temporal Key, 16 bytes)
    ; Returns RAX = 1 (Success)
    mov rax, 1
    ret
