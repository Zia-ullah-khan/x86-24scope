; ==============================================================================
; x86-24scope OS - Kernel Entry & Main Initializer
; ==============================================================================
bits 64
default rel

section .text

global kernel_main
extern gdt_init
extern idt_init
extern pmm_init
extern vmm_init
extern console_init
extern serial_init
extern apic_init
extern timer_init
extern pci_init
extern acpi_init
extern disk_init
extern fat32_init
extern wifi_init
extern arp_init
extern dhcp_init
extern wifi_try_connect
extern wifi_needs_association
extern wifi_is_associated
extern wifi_recv_packet
extern net_handle_packet
extern http_server_start
extern tui_init
extern con_puts
extern con_clear
extern serial_puts

; kernel_main is called from bootloader with RCX = pointer to BootInfo struct
kernel_main:
    ; 1. Establish kernel stack frame
    cli                             ; Ensure interrupts are off during init
    cld                             ; UEFI may leave DF=1; string ops must go forward
    lea rsp, [kernel_stack_top]     ; Load our kernel stack (RIP-relative, safe after relocation)

    push rbp
    mov rbp, rsp
    sub rsp, 32                     ; Align stack + shadow space

    ; Save BootInfo pointer
    mov [boot_info_ptr], rcx

    ; 2. Initialize GDT (Global Descriptor Table)
    call gdt_init

    ; 3. Initialize IDT (Interrupt Descriptor Table) & Exceptions
    call idt_init

    ; 4. Initialize COM1 Serial port for debugging
    call serial_init
    lea rcx, [msg_serial_init]
    call serial_puts

    ; 5. Initialize Framebuffer TUI Console
    mov rcx, [boot_info_ptr]
    call console_init
    call con_clear

    lea rcx, [msg_kernel_start]
    call con_puts
    lea rcx, [msg_kernel_start]
    call serial_puts

    ; 6. Initialize Physical Memory Manager (PMM)
    mov rcx, [boot_info_ptr]
    call pmm_init
    lea rcx, [msg_pmm_init]
    call con_puts
    lea rcx, [msg_pmm_init]
    call serial_puts

    ; 7. Initialize Virtual Memory Manager (VMM)
    mov rcx, [boot_info_ptr]
    call vmm_init
    lea rcx, [msg_vmm_init]
    call con_puts
    lea rcx, [msg_vmm_init]
    call serial_puts

    ; 8. Parse ACPI Tables
    mov rcx, [boot_info_ptr]
    call acpi_init

    ; 9. Initialize APIC and Interrupt Controllers
    call apic_init

    ; 10. Initialize System Timer
    call timer_init

    ; 11. Initialize RAM Disk block layer
    mov rcx, [boot_info_ptr]
    call disk_init

    ; 12. Mount FAT32 Partition
    call fat32_init

    ; 13. Scan PCI bus
    call pci_init

    ; 14. Initialize WiFi / Virtual Network Driver
    call wifi_init

    ; 15. Initialize ARP Table
    call arp_init

    ; 15b. Associate WiFi before DHCP when a wireless backend is active
    call wifi_needs_association
    test rax, rax
    jz .dhcp
    call wifi_try_connect
    test rax, rax
    jnz .dhcp
    lea rcx, [msg_wifi_skip_dhcp]
    call con_puts
    lea rcx, [msg_wifi_skip_dhcp]
    call serial_puts
    jmp .after_dhcp

.dhcp:
    ; 16. Start DHCP Configuration
    call dhcp_init

.after_dhcp:

    ; 17. Initialize TUI Dashboard Layout
    call tui_init

    ; Display boot success banner
    lea rcx, [msg_banner]
    call con_puts
    lea rcx, [msg_banner]
    call serial_puts

    ; Start the HTTP Web Server
    call http_server_start

    ; Fallback to idle loop if HTTP server ever exits
    lea rcx, [msg_idle]
    call con_puts
    lea rcx, [msg_idle]
    call serial_puts

.idle_loop:
    extern con_heartbeat
    call con_heartbeat
    lea rcx, [network_rx_buffer]
    call wifi_recv_packet
    test rax, rax
    jz .no_packet

    lea rcx, [network_rx_buffer]
    mov rdx, rax                    ; Length
    call net_handle_packet
    jmp .idle_loop

.no_packet:
    hlt                             ; Halt CPU until interrupt (like 1ms timer)
    jmp .idle_loop

section .data

align 8
global boot_info_ptr
boot_info_ptr dq 0

msg_serial_init db "Serial debug port initialized at COM1 (115200 8N1)", 13, 10, 0
msg_kernel_start db "Kernel initialized. Welcome to x86-24scope OS!", 13, 10, 0
msg_pmm_init db "PMM: Physical Memory Manager initialized.", 13, 10, 0
msg_vmm_init db "VMM: Virtual Memory Manager (Paging) initialized.", 13, 10, 0
msg_banner db "--------------------------------------------------------", 13, 10
           db " x86-24scope Bare-Metal OS - Phase 1 Boot Successful!  ", 13, 10
           db "--------------------------------------------------------", 13, 10, 0
msg_idle   db "System idle. Halting CPU...", 13, 10, 0
msg_wifi_skip_dhcp db "WiFi: Not associated; skipping DHCP until connect succeeds.", 13, 10, 0

section .bss

align 16
kernel_stack_bottom:
    resb 65536                      ; 64KB stack
kernel_stack_top:

align 16
global network_rx_buffer
network_rx_buffer resb 2048
