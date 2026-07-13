#!/bin/bash
echo "Stopping servers..."

# Try pkill first, then killall, ignore errors
pkill -f "./server" >/dev/null 2>&1 || killall server >/dev/null 2>&1 || true
pkill -f "./frontend_server" >/dev/null 2>&1 || killall frontend_server >/dev/null 2>&1 || true

echo "Done"
