@echo off
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set QEMU=C:\Users\khans\scoop\apps\qemu\current\qemu-system-x86_64.exe
set OVMF_CODE=C:\Users\khans\scoop\apps\qemu\current\share\edk2-x86_64-code.fd
set OVMF_VARS_SRC=C:\Users\khans\scoop\apps\qemu\current\share\edk2-i386-vars.fd
set ISO=%ROOT%build\24scope.iso
set VARS=%ROOT%build\ovmf-vars-run.fd
set SERIAL=%ROOT%build\serial.log
set ERRLOG=%ROOT%build\qemu_run_err.txt

if not exist "%QEMU%" (
    echo ERROR: QEMU not found at %QEMU%
    echo Install with: scoop install qemu
    exit /b 1
)

if not exist "%ISO%" (
    echo ERROR: %ISO% not found. Run build_os.bat first.
    exit /b 1
)

if not exist "%OVMF_CODE%" (
    echo ERROR: OVMF firmware missing: %OVMF_CODE%
    exit /b 1
)

REM Kill any leftover QEMU that would lock the ISO / vars file
taskkill /F /IM qemu-system-x86_64.exe >nul 2>&1

REM Fresh writable vars each run (avoids "Permission denied" on locked vars)
copy /Y "%OVMF_VARS_SRC%" "%VARS%" >nul
if errorlevel 1 (
    echo ERROR: Could not create %VARS%
    exit /b 1
)

del "%ERRLOG%" >nul 2>&1
del "%SERIAL%" >nul 2>&1

echo ==============================================================================
echo Booting x86-24scope OS in QEMU
echo ISO:    %ISO%
echo Serial: %SERIAL%
echo Host:   http://127.0.0.1:8091/  (after DHCP / boot completes)
echo Close the QEMU window to stop.
echo ==============================================================================
echo.

REM Prefer GTK on Windows; fall back to SDL, then default.
REM e1000 + user networking: host can open http://127.0.0.1:8091/
"%QEMU%" ^
    -machine q35 ^
    -cpu max ^
    -accel tcg ^
    -m 512 ^
    -drive if=pflash,format=raw,readonly=on,file="%OVMF_CODE%" ^
    -drive if=pflash,format=raw,file="%VARS%" ^
    -cdrom "%ISO%" ^
    -netdev user,id=net0,hostfwd=tcp::8091-:8091 ^
    -device e1000,netdev=net0 ^
    -serial file:"%SERIAL%" ^
    -display gtk ^
    -name "24scope OS" 2>"%ERRLOG%"

if errorlevel 1 (
    echo GTK display failed, trying SDL...
    "%QEMU%" ^
        -machine q35 ^
        -cpu max ^
        -accel tcg ^
        -m 512 ^
        -drive if=pflash,format=raw,readonly=on,file="%OVMF_CODE%" ^
        -drive if=pflash,format=raw,file="%VARS%" ^
        -cdrom "%ISO%" ^
        -netdev user,id=net0,hostfwd=tcp::8091-:8091 ^
        -device e1000,netdev=net0 ^
        -serial file:"%SERIAL%" ^
        -display sdl ^
        -name "24scope OS" 2>"%ERRLOG%"
)

if errorlevel 1 (
    echo.
    echo QEMU failed to start. Error log:
    type "%ERRLOG%"
    echo.
    echo Serial so far:
    if exist "%SERIAL%" type "%SERIAL%"
    exit /b 1
)

echo.
echo QEMU exited normally. Serial log: %SERIAL%
endlocal
