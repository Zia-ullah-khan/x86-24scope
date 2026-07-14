#!/bin/bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="$ROOT/build/24scope.iso"
VARS="$ROOT/build/ovmf-vars-run.fd"
SERIAL="$ROOT/build/serial.log"
ERRLOG="$ROOT/build/qemu_run_err.txt"

# 1. Detect QEMU path
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    QEMU="qemu-system-x86_64"
else
    # Check common Homebrew locations on macOS
    if [ -x "/opt/homebrew/bin/qemu-system-x86_64" ]; then
        QEMU="/opt/homebrew/bin/qemu-system-x86_64"
    elif [ -x "/usr/local/bin/qemu-system-x86_64" ]; then
        QEMU="/usr/local/bin/qemu-system-x86_64"
    else
        echo "ERROR: QEMU not found!"
        echo "Please install QEMU. On macOS, run: brew install qemu"
        exit 1
    fi
fi

# 2. Check if ISO exists
if [ ! -f "$ISO" ]; then
    echo "ERROR: ISO not found at $ISO. Run ./build_os.sh first."
    exit 1
fi

# 3. Detect OVMF firmware paths
OVMF_CODE=""
OVMF_VARS_SRC=""

OVMF_CODE_PATHS=(
    "/opt/homebrew/share/qemu/edk2-x86_64-code.fd"
    "/usr/local/share/qemu/edk2-x86_64-code.fd"
    "/usr/share/OVMF/OVMF_CODE.fd"
    "/usr/share/OVMF/OVMF_CODE.ms.fd"
    "/usr/share/ovmf/OVMF_CODE.fd"
    "/usr/share/edk2/ovmf/OVMF_CODE.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
)

OVMF_VARS_PATHS=(
    "/opt/homebrew/share/qemu/edk2-i386-vars.fd"
    "/usr/local/share/qemu/edk2-i386-vars.fd"
    "/usr/share/OVMF/OVMF_VARS.fd"
    "/usr/share/OVMF/OVMF_VARS.ms.fd"
    "/usr/share/ovmf/OVMF_VARS.fd"
    "/usr/share/edk2/ovmf/OVMF_VARS.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_VARS.fd"
)

for path in "${OVMF_CODE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        OVMF_CODE="$path"
        break
    fi
done

for path in "${OVMF_VARS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        OVMF_VARS_SRC="$path"
        break
    fi
done

if [ -z "$OVMF_CODE" ] || [ -z "$OVMF_VARS_SRC" ]; then
    echo "ERROR: OVMF firmware files not found!"
    echo "Please ensure you have OVMF/edk2 firmware installed."
    echo "On macOS, running 'brew install qemu' installs these automatically."
    echo "On Ubuntu/Debian, install with: sudo apt-get install ovmf"
    exit 1
fi

# 4. Kill any leftover QEMU processes that would lock the files
killall qemu-system-x86_64 >/dev/null 2>&1 || true

# 5. Create fresh writable vars file
cp -f "$OVMF_VARS_SRC" "$VARS"
if [ $? -ne 0 ]; then
    echo "ERROR: Could not create $VARS"
    exit 1
fi

rm -f "$ERRLOG" "$SERIAL"

echo "=============================================================================="
echo "Booting x86-24scope OS in QEMU"
echo "ISO:    $ISO"
echo "Serial: $SERIAL"
echo "Host:   http://127.0.0.1:8091/  (after DHCP / boot completes)"
echo "Close the QEMU window or press Ctrl+C in terminal to stop."
echo "=============================================================================="
echo ""

# Try launching QEMU. 
# On macOS, native display (cocoa) is default/preferred.
# On Linux, gtk is preferred.
# We will try default/platform-specific display first, then fall back to SDL, then default (no display option specified).

OS="$(uname -s)"
RUN_SUCCESS=false

# First Attempt: Platform Preferred
if [ "$OS" = "Darwin" ]; then
    # Cocoa display
    "$QEMU" \
        -machine q35 \
        -cpu max \
        -accel tcg \
        -m 512 \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$VARS" \
        -cdrom "$ISO" \
        -netdev user,id=net0,hostfwd=tcp::8091-:8091 \
        -device e1000,netdev=net0 \
        -serial file:"$SERIAL" \
        -display cocoa \
        -name "24scope OS" 2>"$ERRLOG" && RUN_SUCCESS=true
else
    # GTK display
    "$QEMU" \
        -machine q35 \
        -cpu max \
        -accel tcg \
        -m 512 \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$VARS" \
        -cdrom "$ISO" \
        -netdev user,id=net0,hostfwd=tcp::8091-:8091 \
        -device e1000,netdev=net0 \
        -serial file:"$SERIAL" \
        -display gtk \
        -name "24scope OS" 2>"$ERRLOG" && RUN_SUCCESS=true
fi

# Second Attempt Fallback: SDL
if [ "$RUN_SUCCESS" = false ]; then
    echo "Primary display mode failed, trying SDL..."
    "$QEMU" \
        -machine q35 \
        -cpu max \
        -accel tcg \
        -m 512 \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$VARS" \
        -cdrom "$ISO" \
        -netdev user,id=net0,hostfwd=tcp::8091-:8091 \
        -device e1000,netdev=net0 \
        -serial file:"$SERIAL" \
        -display sdl \
        -name "24scope OS" 2>"$ERRLOG" && RUN_SUCCESS=true
fi

# Third Attempt Fallback: Default Display (let QEMU pick)
if [ "$RUN_SUCCESS" = false ]; then
    echo "SDL display mode failed, trying default QEMU display..."
    "$QEMU" \
        -machine q35 \
        -cpu max \
        -accel tcg \
        -m 512 \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$VARS" \
        -cdrom "$ISO" \
        -netdev user,id=net0,hostfwd=tcp::8091-:8091 \
        -device e1000,netdev=net0 \
        -serial file:"$SERIAL" \
        -name "24scope OS" 2>"$ERRLOG" && RUN_SUCCESS=true
fi

if [ "$RUN_SUCCESS" = false ]; then
    echo ""
    echo "QEMU failed to start. Error log:"
    cat "$ERRLOG"
    echo ""
    echo "Serial so far:"
    if [ -f "$SERIAL" ]; then
        cat "$SERIAL"
    fi
    exit 1
fi

echo ""
echo "QEMU exited normally. Serial log: $SERIAL"
