@echo off
setlocal enabledelayedexpansion

echo ==============================================================================
echo Building x86-24scope OS (Phase 1)
echo ==============================================================================

if not exist build mkdir build

echo Compiling Bootloader...
"C:\Program Files\NASM\nasm.exe" -f win64 os\boot\boot.asm -o build\boot.obj
if errorlevel 1 goto error

echo Compiling Kernel...
"C:\Program Files\NASM\nasm.exe" -f win64 os\kernel\kernel.asm -o build\kernel.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\kernel\gdt.asm -o build\gdt.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\kernel\idt.asm -o build\idt.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\kernel\pmm.asm -o build\pmm.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\kernel\vmm.asm -o build\vmm.obj
if errorlevel 1 goto error

echo Compiling Drivers...
"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\console.asm -o build\console.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\font8x16.asm -o build\font8x16.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\serial.asm -o build\serial.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\kbd.asm -o build\kbd.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\apic.asm -o build\apic.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\timer.asm -o build\timer.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\pci.asm -o build\pci.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\acpi.asm -o build\acpi.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\disk.asm -o build\disk.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\fat32.asm -o build\fat32.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\net\crypto.asm -o build\crypto.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\net\netdev.asm -o build\netdev.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\net\loopback.asm -o build\loopback.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\net\e1000.asm -o build\e1000.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\net\rtl8169.asm -o build\rtl8169.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\net\generic_eth.asm -o build\generic_eth.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\wifi\wifi_config.asm -o build\wifi_config.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\wifi\generic_wifi.asm -o build\generic_wifi.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\wifi\iwl_dev.asm -o build\iwl_dev.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\wifi\iwl_fw.asm -o build\iwl_fw.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\wifi\iwl_cmd.asm -o build\iwl_cmd.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\wifi\iwl_scan.asm -o build\iwl_scan.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\drivers\wifi\iwl_connect.asm -o build\iwl_connect.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\net\ieee80211.asm -o build\ieee80211.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\net\arp.asm -o build\arp.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\net\ip.asm -o build\ip.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\net\udp.asm -o build\udp.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\net\dhcp.asm -o build\dhcp.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\net\tcp.asm -o build\tcp.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\app\http.asm -o build\http.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 frontend\pages\index.asm -o build\index.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 frontend\pages\radar.asm -o build\radar.obj
if errorlevel 1 goto error

"C:\Program Files\NASM\nasm.exe" -f win64 os\app\tui.asm -o build\tui.obj
if errorlevel 1 goto error

echo Linking UEFI Application...
"C:\Users\khans\Desktop\GoLink.exe" /entry uefi_main /largeaddressaware /base 0x400000 build\boot.obj build\kernel.obj build\gdt.obj build\idt.obj build\pmm.obj build\vmm.obj build\console.obj build\font8x16.obj build\serial.obj build\kbd.obj build\apic.obj build\timer.obj build\pci.obj build\acpi.obj build\disk.obj build\fat32.obj build\crypto.obj build\netdev.obj build\loopback.obj build\e1000.obj build\rtl8169.obj build\generic_eth.obj build\wifi_config.obj build\generic_wifi.obj build\iwl_dev.obj build\iwl_fw.obj build\iwl_cmd.obj build\iwl_scan.obj build\iwl_connect.obj build\ieee80211.obj build\arp.obj build\ip.obj build\udp.obj build\dhcp.obj build\tcp.obj build\http.obj build\index.obj build\radar.obj build\tui.obj /fo build\BOOTX64.EFI
if errorlevel 1 goto error

echo Patching PE headers for UEFI subsystem...
python os\scratch\patch_efi.py build\BOOTX64.EFI
if errorlevel 1 goto error

echo Generating UEFI Bootable FAT Image and ISO...
python os\scratch\make_uefi_image.py
if errorlevel 1 goto error

echo ==============================================================================
echo Build Completed Successfully!
echo Target: build\BOOTX64.EFI
echo ISO Image: build\24scope.iso
echo ==============================================================================
exit /b 0

:error
echo ==============================================================================
echo Build FAILED!
echo ==============================================================================
exit /b 1
