@echo off
echo Starting backend on port 8080...
echo Starting frontend on port 8081...
echo Open http://localhost:8080/ for the backend and http://localhost:8081/ for the frontend
echo Press Ctrl+C to stop the server
echo.

start "Backend" .\server.exe
start "Frontend" .\frontend.exe

echo Both servers started

