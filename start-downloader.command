#!/bin/bash

# URL Downloader Start Script
# Double-click this file to start the downloader server

# Find the project directory (where server.js is located)
PROJECT_DIR=""

# Common project locations to check
POSSIBLE_DIRS=(
    "/Users/pkleim/WebstormProjects/dl-url"
    "/Users/pkleim/Desktop/dl-url"
    "/Users/pkleim/Documents/dl-url"
    "$(dirname "${BASH_SOURCE[0]}")"
)

# Check each possible directory
for dir in "${POSSIBLE_DIRS[@]}"; do
    if [ -f "$dir/server.js" ]; then
        PROJECT_DIR="$dir"
        break
    fi
done

# If still not found, search upward from Desktop
if [ -z "$PROJECT_DIR" ]; then
    CURRENT_DIR="$(dirname "${BASH_SOURCE[0]}")"
    while [ "$CURRENT_DIR" != "/" ]; do
        if [ -f "$CURRENT_DIR/server.js" ]; then
            PROJECT_DIR="$CURRENT_DIR"
            break
        fi
        CURRENT_DIR="$(dirname "$CURRENT_DIR")"
    done
fi

if [ -z "$PROJECT_DIR" ]; then
    echo "Error: Could not find server.js file"
    echo "Searched in:"
    for dir in "${POSSIBLE_DIRS[@]}"; do
        echo "  - $dir"
    done
    echo "Please make sure your URL Downloader project exists"
    read -p "Press Enter to exit..."
    exit 1
fi

# Change to the project directory
cd "$PROJECT_DIR"
echo "Found project directory: $PROJECT_DIR"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed or not in PATH"
    echo "Please install Node.js from https://nodejs.org/"
    read -p "Press Enter to exit..."
    exit 1
fi

# Check if yt-dlp is installed
if ! command -v yt-dlp &> /dev/null; then
    echo "Error: yt-dlp is not installed or not in PATH"
    echo "Please install yt-dlp: brew install yt-dlp"
    read -p "Press Enter to exit..."
    exit 1
fi

# Check if dependencies are installed
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
fi

# Start the server
echo "Starting URL Downloader server..."
echo "Server will be available at: http://127.0.0.1:3000"
echo "Press Ctrl+C to stop the server"
echo ""

node server.js

# Keep terminal open if there was an error
if [ $? -ne 0 ]; then
    echo ""
    echo "Server stopped with an error"
    read -p "Press Enter to exit..."
fi