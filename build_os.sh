#!/bin/bash
set -e

echo "=============================================================================="
echo "Building x86-24scope OS (Phase 1)"
echo "=============================================================================="

mkdir -p build

echo "Compiling Bootloader..."
nasm -f win64 os/boot/boot.asm -o build/boot.obj

echo "Compiling Kernel..."
nasm -f win64 os/kernel/kernel.asm -o build/kernel.obj
nasm -f win64 os/kernel/gdt.asm -o build/gdt.obj
nasm -f win64 os/kernel/idt.asm -o build/idt.obj
nasm -f win64 os/kernel/pmm.asm -o build/pmm.obj
nasm -f win64 os/kernel/vmm.asm -o build/vmm.obj

echo "Compiling Drivers..."
nasm -f win64 os/drivers/console.asm -o build/console.obj
nasm -f win64 os/drivers/font8x16.asm -o build/font8x16.obj
nasm -f win64 os/drivers/serial.asm -o build/serial.obj
nasm -f win64 os/drivers/apic.asm -o build/apic.obj
nasm -f win64 os/drivers/timer.asm -o build/timer.obj
nasm -f win64 os/drivers/pci.asm -o build/pci.obj
nasm -f win64 os/drivers/acpi.asm -o build/acpi.obj
nasm -f win64 os/drivers/disk.asm -o build/disk.obj
nasm -f win64 os/drivers/fat32.asm -o build/fat32.obj
nasm -f win64 os/net/crypto.asm -o build/crypto.obj
nasm -f win64 os/net/netdev.asm -o build/netdev.obj
nasm -f win64 os/drivers/net/loopback.asm -o build/loopback.obj
nasm -f win64 os/drivers/net/e1000.asm -o build/e1000.obj
nasm -f win64 os/drivers/wifi/iwl_dev.asm -o build/iwl_dev.obj
nasm -f win64 os/drivers/wifi/iwl_fw.asm -o build/iwl_fw.obj
nasm -f win64 os/drivers/wifi/iwl_cmd.asm -o build/iwl_cmd.obj
nasm -f win64 os/drivers/wifi/iwl_scan.asm -o build/iwl_scan.obj
nasm -f win64 os/drivers/wifi/iwl_connect.asm -o build/iwl_connect.obj
nasm -f win64 os/net/ieee80211.asm -o build/ieee80211.obj
nasm -f win64 os/net/arp.asm -o build/arp.obj
nasm -f win64 os/net/ip.asm -o build/ip.obj
nasm -f win64 os/net/udp.asm -o build/udp.obj
nasm -f win64 os/net/dhcp.asm -o build/dhcp.obj
nasm -f win64 os/net/tcp.asm -o build/tcp.obj
nasm -f win64 os/app/http.asm -o build/http.obj
nasm -f win64 frontend/pages/index.asm -o build/index.obj
nasm -f win64 frontend/pages/radar.asm -o build/radar.obj
nasm -f win64 os/app/tui.asm -o build/tui.obj

echo "Linking UEFI Application..."

# Find suitable PE/COFF linker
LINKER=""
LINKER_FLAGS=""

if command -v lld-link >/dev/null 2>&1; then
    LINKER="lld-link"
    LINKER_FLAGS="/entry:uefi_main /subsystem:efi_application /base:0x400000 /out:build/BOOTX64.EFI"
elif command -v ld.lld >/dev/null 2>&1; then
    LINKER="ld.lld"
    LINKER_FLAGS="-flavor link /entry:uefi_main /subsystem:efi_application /base:0x400000 /out:build/BOOTX64.EFI"
elif command -v x86_64-w64-mingw32-ld >/dev/null 2>&1; then
    LINKER="x86_64-w64-mingw32-ld"
    LINKER_FLAGS="-shared -Bsymbolic -nostdlib -entry uefi_main -subsystem 10 -o build/BOOTX64.EFI"
elif [ -x "/opt/homebrew/opt/llvm/bin/lld-link" ]; then
    LINKER="/opt/homebrew/opt/llvm/bin/lld-link"
    LINKER_FLAGS="/entry:uefi_main /subsystem:efi_application /base:0x400000 /out:build/BOOTX64.EFI"
elif [ -x "/usr/local/opt/llvm/bin/lld-link" ]; then
    LINKER="/usr/local/opt/llvm/bin/lld-link"
    LINKER_FLAGS="/entry:uefi_main /subsystem:efi_application /base:0x400000 /out:build/BOOTX64.EFI"
fi

if [ -z "$LINKER" ]; then
    echo "ERROR: PE/COFF Linker (lld-link, ld.lld, or x86_64-w64-mingw32-ld) not found!"
    echo "Please install lld (e.g., 'brew install lld' on macOS or 'apt install lld' on Debian/Ubuntu)"
    exit 1
fi

$LINKER $LINKER_FLAGS \
    build/boot.obj build/kernel.obj build/gdt.obj build/idt.obj build/pmm.obj build/vmm.obj \
    build/console.obj build/font8x16.obj build/serial.obj build/apic.obj build/timer.obj \
    build/pci.obj build/acpi.obj build/disk.obj build/fat32.obj build/crypto.obj \
    build/netdev.obj build/loopback.obj build/e1000.obj build/iwl_dev.obj build/iwl_fw.obj \
    build/iwl_cmd.obj build/iwl_scan.obj build/iwl_connect.obj build/ieee80211.obj \
    build/arp.obj build/ip.obj build/udp.obj build/dhcp.obj build/tcp.obj build/http.obj \
    build/index.obj build/radar.obj build/tui.obj

echo "Patching PE headers for UEFI subsystem..."
if command -v python3 >/dev/null 2>&1; then
    PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON="python"
else
    echo "ERROR: Python is required to build the UEFI image!"
    exit 1
fi

$PYTHON os/scratch/patch_efi.py build/BOOTX64.EFI
if [ $? -ne 0 ]; then
    echo "Failed to patch EFI headers."
    exit 1
fi

echo "Generating UEFI Bootable FAT Image and ISO..."
$PYTHON os/scratch/make_uefi_image.py
if [ $? -ne 0 ]; then
    echo "Failed to generate UEFI bootable FAT image/ISO."
    exit 1
fi

echo "=============================================================================="
echo "Build Completed Successfully!"
echo "Target: build/BOOTX64.EFI"
echo "ISO Image: build/24scope.iso"
echo "=============================================================================="
