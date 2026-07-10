@echo off
setlocal enabledelayedexpansion

echo Building project...
echo Building frontend...
"C:\Program Files\NASM\nasm.exe" -f win64 frontend\server.asm -o frontend.obj
if errorlevel 1 (
    echo Failed to compile frontend\server.asm
    exit /b 1
)

"C:\Program Files\NASM\nasm.exe" -f win64 frontend\pages\index.asm -o index.obj
if errorlevel 1 (
    echo Failed to compile frontend\pages\index.asm
    exit /b 1
)

"C:\Users\khans\Desktop\GoLink.exe" /entry _start frontend.obj index.obj ws2_32.dll kernel32.dll user32.dll /fo frontend.exe
if errorlevel 1 (
    echo Failed to link frontend executable
    exit /b 1
)

echo Building backend...
"C:\Program Files\NASM\nasm.exe" -f win64 backend\server.asm -o backend.obj
if errorlevel 1 (
    echo Failed to compile backend\server.asm
    exit /b 1
)

"C:\Users\khans\Desktop\GoLink.exe" /entry _start backend.obj ws2_32.dll wininet.dll kernel32.dll user32.dll /fo server.exe
if errorlevel 1 (
    echo Failed to link executable
    exit /b 1
)

echo Build completed successfully!
