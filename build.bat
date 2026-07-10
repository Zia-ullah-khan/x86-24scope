@echo off
setlocal enabledelayedexpansion

echo Building project...
"C:\Program Files\NASM\nasm.exe" -f win64 frontend\server.asm -o server.obj
if errorlevel 1 (
    echo Failed to compile server.asm
    exit /b 1
)

"C:\Program Files\NASM\nasm.exe" -f win64 frontend\pages\index.asm -o index.obj
if errorlevel 1 (
    echo Failed to compile index.asm
    exit /b 1
)

"C:\Users\khans\Desktop\GoLink.exe" /entry _start server.obj index.obj ws2_32.dll kernel32.dll user32.dll /fo server.exe
if errorlevel 1 (
    echo Failed to link executable
    exit /b 1
)

echo Build completed successfully!
