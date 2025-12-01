#!/bin/bash

# Create a macOS app bundle for URL Downloader
APP_NAME="URL Downloader"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Create app bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy project files into Resources folder to make app self-contained
echo "Bundling project files..."
cp package.json "$RESOURCES_DIR/" 2>/dev/null || echo "Warning: package.json not found"
cp url-download-server.js "$RESOURCES_DIR/" 2>/dev/null || echo "Warning: url-download-server.js not found"
cp index.html "$RESOURCES_DIR/" 2>/dev/null || echo "Warning: index.html not found"

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>URL Downloader</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.url-downloader</string>
    <key>CFBundleName</key>
    <string>URL Downloader</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleDisplayName</key>
    <string>URL Downloader</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.14</string>
</dict>
</plist>
EOF

# Create the executable script - SIMPLE VERSION
cat > "${MACOS_DIR}/URL Downloader" << 'EOF'
#!/bin/bash

# Simple URL Downloader App Launcher

# Get app directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$(dirname "$(dirname "$SCRIPT_DIR")")" && pwd)"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

# Change to Resources directory
cd "$RESOURCES_DIR" || exit 1

# Source shell profiles for PATH
[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc" 2>/dev/null
[ -f "$HOME/.bash_profile" ] && source "$HOME/.bash_profile" 2>/dev/null
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin"

# Find node
NODE_PATH=$(command -v node 2>/dev/null)
[ -z "$NODE_PATH" ] && NODE_PATH="/opt/homebrew/bin/node"
[ -z "$NODE_PATH" ] && NODE_PATH="/usr/local/bin/node"

if [ ! -f "$NODE_PATH" ]; then
    osascript -e 'display dialog "Node.js not found. Please install Node.js from https://nodejs.org/" buttons {"OK"} default button "OK"'
    exit 1
fi

# Check for yt-dlp
if ! command -v yt-dlp &>/dev/null; then
    osascript -e 'display dialog "yt-dlp not found. Please install: brew install yt-dlp" buttons {"OK"} default button "OK"'
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    osascript -e 'display notification "Installing dependencies..." with title "URL Downloader"'
    
    # Find npm
    NPM_PATH=$(command -v npm 2>/dev/null)
    [ -z "$NPM_PATH" ] && NPM_PATH="$(dirname "$NODE_PATH")/npm"
    
    if [ ! -f "$NPM_PATH" ]; then
        osascript -e 'display dialog "npm not found. Node.js installation may be incomplete." buttons {"OK"} default button "OK"'
        exit 1
    fi
    
    # Run npm install and capture output
    "$NPM_PATH" install > npm-install.log 2>&1
    NPM_EXIT=$?
    
    if [ $NPM_EXIT -ne 0 ]; then
        # Read error from log
        if [ -f npm-install.log ] && [ -s npm-install.log ]; then
            ERROR_MSG=$(tail -15 npm-install.log | sed "s/\"/'/g" | awk '{printf "%s\\n", $0}')
            osascript -e "display dialog \"Failed to install dependencies:\\n\\n$ERROR_MSG\" buttons {\"OK\"} default button \"OK\""
        else
            osascript -e "display dialog \"npm install failed with exit code $NPM_EXIT.\\n\\nCheck npm-install.log in:\\n$RESOURCES_DIR\" buttons {\"OK\"} default button \"OK\""
        fi
        exit 1
    fi
    
    # Verify node_modules was created
    if [ ! -d "node_modules" ]; then
        osascript -e 'display dialog "npm install completed but node_modules not found." buttons {"OK"} default button "OK"'
        exit 1
    fi
fi

# Check if port 3000 is in use
if lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    osascript -e 'display dialog "Port 3000 is already in use. Please stop the existing server." buttons {"OK"} default button "OK"'
    exit 1
fi

# Start server
osascript -e 'display notification "Starting server..." with title "URL Downloader"'

# Verify server file exists
if [ ! -f "url-download-server.js" ]; then
    osascript -e "display dialog \"Server file not found in:\\n$(pwd)\" buttons {\"OK\"} default button \"OK\""
    exit 1
fi

# Start server in background, redirect output to log
LOG_FILE="$(pwd)/server.log"
rm -f "$LOG_FILE"
"$NODE_PATH" url-download-server.js > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

# Wait a moment for process to start
sleep 1

# Check if process is still running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    # Process died immediately
    sleep 1
    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        ERROR=$(tail -20 "$LOG_FILE" | sed "s/\"/'/g" | awk '{printf "%s\\n", $0}')
        osascript -e "display dialog \"Server process died immediately:\\n\\n$ERROR\" buttons {\"OK\"} default button \"OK\""
    else
        osascript -e "display dialog \"Server process died immediately.\\n\\nNode: $NODE_PATH\\nDirectory: $(pwd)\\n\\nNo error output captured.\" buttons {\"OK\"} default button \"OK\""
    fi
    exit 1
fi

# Wait for server to start listening
sleep 3

# Check if server is listening
if ! lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    # Wait a bit more
    sleep 2
    if ! lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        # Check if process is still running
        if ! kill -0 $SERVER_PID 2>/dev/null; then
            # Process died
            if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
                ERROR=$(tail -20 "$LOG_FILE" | sed "s/\"/'/g" | awk '{printf "%s\\n", $0}')
                osascript -e "display dialog \"Server process died:\\n\\n$ERROR\" buttons {\"OK\"} default button \"OK\""
            else
                osascript -e 'display dialog "Server process died. No error output." buttons {"OK"} default button "OK"'
            fi
        else
            # Process running but not listening
            if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
                ERROR=$(tail -20 "$LOG_FILE" | sed "s/\"/'/g" | awk '{printf "%s\\n", $0}')
                osascript -e "display dialog \"Server started but not listening on port 3000:\\n\\n$ERROR\" buttons {\"OK\"} default button \"OK\""
            else
                osascript -e 'display dialog "Server started but not listening on port 3000. Check server.log for details." buttons {"OK"} default button "OK"'
            fi
        fi
        kill $SERVER_PID 2>/dev/null
        exit 1
    fi
fi

# Open browser
osascript -e 'display notification "Opening browser..." with title "URL Downloader"'
open "http://127.0.0.1:3000"

# Keep script running (wait for server)
wait $SERVER_PID
EOF

# Make executable
chmod +x "${MACOS_DIR}/URL Downloader"

echo "✓ Created ${APP_NAME}.app"
echo "✓ App is self-contained and ready to use"
