@echo off
echo Stopping servers...
taskkill /IM server.exe /F >nul 2>&1
taskkill /IM frontend.exe /F >nul 2>&1
echo Done
