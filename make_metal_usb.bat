@echo off
setlocal
REM Prepare a UEFI USB stick for bare-metal boot.
REM Usage: make_metal_usb.bat E:
REM   where E: is the USB drive letter (FAT32 / EFI System Partition).

if "%~1"=="" (
    echo Usage: make_metal_usb.bat ^<drive-letter^>:
    echo Example: make_metal_usb.bat E:
    echo.
    echo Format the USB as FAT32 first, then run this script.
    exit /b 1
)

set "USB=%~1"
REM Normalize: allow "D" or "D:"
if "%USB:~-1%"==":" (
    rem already has colon
) else (
    set "USB=%USB%:"
)

if not exist "%USB%\" (
    echo ERROR: Drive %USB% is not accessible.
    echo.
    echo Windows sees the letter but no filesystem on it ^(RAW / unformatted^).
    echo Format the USB as FAT32 first, then re-run this script.
    echo.
    echo Example ^(admin PowerShell^):
    echo   format %USB% /FS:FAT32 /Q /V:24SCOPE
    echo Or use Disk Management / Rufus and assign letter %USB%.
    exit /b 1
)

if not exist "build\BOOTX64.EFI" (
    echo ERROR: build\BOOTX64.EFI missing. Run build_os.bat first.
    exit /b 1
)

echo Copying EFI loader to %USB%\EFI\BOOT\BOOTX64.EFI
mkdir "%USB%\EFI\BOOT" 2>nul
copy /Y "build\BOOTX64.EFI" "%USB%\EFI\BOOT\BOOTX64.EFI" >nul
if errorlevel 1 (
    echo ERROR: copy failed. Is the USB writable FAT32?
    exit /b 1
)

echo Copying WiFi firmware to %USB%\EFI\FIRMWARE\
mkdir "%USB%\EFI\FIRMWARE" 2>nul
if exist "firmware\*" (
    copy /Y "firmware\*" "%USB%\EFI\FIRMWARE\" >nul
    echo Firmware files copied from firmware\
) else (
    echo WARNING: no files in firmware\ — place IWLWIFI.UC there for WiFi.
)
REM Also install 8.3 name IWLWIFI.UC (FAT short-name path used by the loader)
if exist "firmware\IWLWIFI.UC" (
    copy /Y "firmware\IWLWIFI.UC" "%USB%\EFI\FIRMWARE\IWLWIFI.UC" >nul
) else if exist "firmware\IWLWIFI.UCODE" (
    copy /Y "firmware\IWLWIFI.UCODE" "%USB%\EFI\FIRMWARE\IWLWIFI.UC" >nul
    echo Also copied IWLWIFI.UCODE as IWLWIFI.UC ^(8.3 path^)
) else if exist "%USB%\EFI\FIRMWARE\IWLWIFI.UCODE" (
    copy /Y "%USB%\EFI\FIRMWARE\IWLWIFI.UCODE" "%USB%\EFI\FIRMWARE\IWLWIFI.UC" >nul
    echo Also installed IWLWIFI.UC from UCODE on USB
)

echo.
echo Done. On the target PC:
echo   1. Boot and enter SSID / password when prompted
echo   2. Enter firmware boot menu (often F12 / F10 / Esc)
echo   3. Disable Secure Boot if the loader is rejected
echo   4. Boot from this USB / "UEFI: ..." entry
echo.
echo WiFi needs \EFI\FIRMWARE\IWLWIFI.UC (Linux iwlwifi .ucode renamed).
endlocal
