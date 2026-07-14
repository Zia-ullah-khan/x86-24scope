#!/bin/bash

echo "Starting backend on port 8080..."
echo "Starting frontend on port 8091..."
echo "Open http://localhost:8080/ for the backend and http://localhost:8091/ for the frontend"
echo "Press ./stop.sh to stop the servers"
echo ""

# Run in background
./server > backend.log 2>&1 &
./frontend_server > frontend.log 2>&1 &

echo "Both servers started"
