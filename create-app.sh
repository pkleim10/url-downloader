#!/bin/bash

# Create a macOS app bundle for URL Downloader.
# The app is only a launcher: it runs the server from this project folder,
# so changes to index.html or the server never need a rebuild.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="URL Downloader"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
VERSION=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' package.json | head -1)

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

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
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
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

# Create the launcher. PROJECT_DIR is fixed at build time so the app
# still works if it is copied elsewhere (e.g. /Applications).
{
    echo '#!/bin/bash'
    printf 'PROJECT_DIR=%q\n' "$SCRIPT_DIR"
    cat << 'EOF'

# URL Downloader app launcher

URL="http://127.0.0.1:3000"
LOG_DIR="$HOME/Library/Logs/URL Downloader"
LOG_FILE="$LOG_DIR/server.log"
mkdir -p "$LOG_DIR"

alert() {
    osascript -e "display dialog \"$1\" with title \"URL Downloader\" buttons {\"OK\"} default button \"OK\"" >/dev/null
}

log_tail() {
    tail -15 "$1" 2>/dev/null | sed "s/\"/'/g" | awk '{printf "%s\\n", $0}'
}

is_our_server() {
    curl -s --max-time 2 "$URL/health" 2>/dev/null | grep -q '"app":"url-downloader"'
}

# Fall back to the folder that contains the app if the project moved
if [ ! -f "$PROJECT_DIR/url-download-server.js" ]; then
    APP_PATH="$(cd "$(dirname "$0")/../.." && pwd)"
    PROJECT_DIR="$(dirname "$APP_PATH")"
fi
if [ ! -f "$PROJECT_DIR/url-download-server.js" ]; then
    alert "Can't find the URL Downloader project folder.\n\nRun create-app.sh again from the project folder."
    exit 1
fi
cd "$PROJECT_DIR" || exit 1

# Already running (from Terminal or an earlier launch): just open the page
if is_our_server; then
    open "$URL"
    exit 0
fi

# Apps launched from Finder get a minimal PATH
[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc" 2>/dev/null
[ -f "$HOME/.bash_profile" ] && source "$HOME/.bash_profile" 2>/dev/null
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin"

NODE_PATH=$(command -v node 2>/dev/null)
[ -z "$NODE_PATH" ] && [ -x /opt/homebrew/bin/node ] && NODE_PATH=/opt/homebrew/bin/node
[ -z "$NODE_PATH" ] && [ -x /usr/local/bin/node ] && NODE_PATH=/usr/local/bin/node
if [ -z "$NODE_PATH" ]; then
    alert "Node.js not found. Please install Node.js from https://nodejs.org/"
    exit 1
fi

if ! command -v yt-dlp &>/dev/null; then
    alert "yt-dlp not found. Please install: brew install yt-dlp"
    exit 1
fi

if [ ! -d "node_modules" ]; then
    osascript -e 'display notification "Installing dependencies..." with title "URL Downloader"'
    NPM_PATH=$(command -v npm 2>/dev/null)
    [ -z "$NPM_PATH" ] && NPM_PATH="$(dirname "$NODE_PATH")/npm"
    if ! "$NPM_PATH" install > "$LOG_DIR/npm-install.log" 2>&1; then
        alert "Failed to install dependencies:\n\n$(log_tail "$LOG_DIR/npm-install.log")"
        exit 1
    fi
fi

osascript -e 'display notification "Starting server..." with title "URL Downloader"'
"$NODE_PATH" url-download-server.js > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

# Quitting the app stops the server it started
trap 'kill $SERVER_PID 2>/dev/null' EXIT TERM INT HUP

for _ in $(seq 1 20); do
    if is_our_server; then
        break
    fi
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        break
    fi
    sleep 0.5
done

if ! is_our_server; then
    alert "The server did not start.\n\n$(log_tail "$LOG_FILE")\n\nFull log: $LOG_FILE"
    exit 1
fi

open "$URL"

wait $SERVER_PID
EOF
} > "${MACOS_DIR}/URL Downloader"

chmod +x "${MACOS_DIR}/URL Downloader"

echo "✓ Created ${APP_NAME}.app (${VERSION})"
echo "✓ Runs the server from ${SCRIPT_DIR}"
