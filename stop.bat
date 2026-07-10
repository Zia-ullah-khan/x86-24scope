@echo off
echo Stopping server...
taskkill /IM server.exe /F >nul 2>&1
if errorlevel 1 (
    echo Server is not running
) else (
    echo Server stopped
)
