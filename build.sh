#!/bin/bash
set -e

# Detect OS
OS="$(uname -s)"
echo "Detected OS: $OS"

if [ "$OS" = "Linux" ]; then
    ASM_FORMAT="elf64"
    ASM_DEFINE="-DLINUX"
    LINKER="gcc"
    LDFLAGS="-no-pie"
    CURL_LIBS="-lcurl"
elif [ "$OS" = "Darwin" ]; then
    ASM_FORMAT="macho64"
    ASM_DEFINE="-DMACOS"
    LINKER="clang"
    LDFLAGS=""
    CURL_LIBS="-lcurl"
else
    echo "Unsupported OS: $OS"
    exit 1
fi

echo "Building frontend..."
nasm -f $ASM_FORMAT $ASM_DEFINE frontend/server.asm -o frontend.o
nasm -f $ASM_FORMAT $ASM_DEFINE frontend/pages/index.asm -o index.o
nasm -f $ASM_FORMAT $ASM_DEFINE frontend/pages/radar.asm -o radar.o

$LINKER $LDFLAGS frontend.o index.o radar.o -o frontend_server
rm -f frontend.o index.o radar.o

echo "Building backend..."
nasm -f $ASM_FORMAT $ASM_DEFINE backend/server.asm -o backend.o

$LINKER $LDFLAGS backend.o -o server $CURL_LIBS
rm -f backend.o

echo "Build completed successfully!"
