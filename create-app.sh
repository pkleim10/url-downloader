#!/bin/bash

# Build Siphon.app, install it to /Applications, and move any other
# copies to the Trash. The app is only a launcher: it runs the server from
# this project folder, so changes to index.html or the server never need a rebuild.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Siphon"
# Earlier names of this app; their copies are moved to the Trash too
OLD_NAMES=("Downloader" "URL Downloader")
BUNDLE_ID="com.local.url-downloader"
INSTALL_PATH="/Applications/${APP_NAME}.app"
BUILD_ROOT="$(mktemp -d)"
trap 'rm -rf "$BUILD_ROOT"' EXIT
APP_DIR="${BUILD_ROOT}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
VERSION=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' package.json | head -1)

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
# Regenerate with: swift icon/make-icon.swift
cp icon/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
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

# Siphon app launcher

URL="http://127.0.0.1:3000"
LOG_DIR="$HOME/Library/Logs/Siphon"
LOG_FILE="$LOG_DIR/server.log"
mkdir -p "$LOG_DIR"

alert() {
    osascript -e "display dialog \"$1\" with title \"Siphon\" buttons {\"OK\"} default button \"OK\"" >/dev/null
}

log_tail() {
    tail -15 "$1" 2>/dev/null | sed "s/\"/'/g" | awk '{printf "%s\\n", $0}'
}

is_our_server() {
    curl -s --max-time 2 "$URL/health" 2>/dev/null | grep -q '"app":"url-downloader"'
}

if [ ! -f "$PROJECT_DIR/url-download-server.js" ]; then
    alert "Can't find the Siphon project folder:\n$PROJECT_DIR\n\nRun create-app.sh again from the project folder."
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
    osascript -e 'display notification "Installing dependencies..." with title "Siphon"'
    NPM_PATH=$(command -v npm 2>/dev/null)
    [ -z "$NPM_PATH" ] && NPM_PATH="$(dirname "$NODE_PATH")/npm"
    if ! "$NPM_PATH" install > "$LOG_DIR/npm-install.log" 2>&1; then
        alert "Failed to install dependencies:\n\n$(log_tail "$LOG_DIR/npm-install.log")"
        exit 1
    fi
fi

osascript -e 'display notification "Starting server..." with title "Siphon"'
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
} > "${MACOS_DIR}/${APP_NAME}"

chmod +x "${MACOS_DIR}/${APP_NAME}"

# Install (a running launcher keeps working; macOS holds the old file open)
if [ -d "$INSTALL_PATH" ] && [ "$(defaults read "$INSTALL_PATH/Contents/Info" CFBundleIdentifier 2>/dev/null)" != "$BUNDLE_ID" ]; then
    echo "✗ ${INSTALL_PATH} is a different app; not replacing it" >&2
    exit 1
fi
rm -rf "$INSTALL_PATH"
ditto "$APP_DIR" "$INSTALL_PATH"
echo "✓ Installed ${INSTALL_PATH} (${VERSION})"
echo "✓ Runs the server from ${SCRIPT_DIR}"

# Move every other copy to the Trash: the old in-repo build, other clones,
# and anything Spotlight knows with this bundle id
trash_copy() {
    local copy="$1"
    [ -d "$copy" ] || return 0
    # Only ever touch our own bundle; other apps may share the name
    [ "$(defaults read "$copy/Contents/Info" CFBundleIdentifier 2>/dev/null)" = "$BUNDLE_ID" ] || return 0
    local real
    real="$(cd "$copy" && pwd -P)"
    [ "$real" = "$(cd "$INSTALL_PATH" && pwd -P)" ] && return 0
    local name dest
    name="$(basename "$copy")"
    dest="$HOME/.Trash/${name%.app} $(date +%Y%m%d-%H%M%S)-$RANDOM.app"
    mv "$copy" "$dest"
    echo "✓ Moved old copy to Trash: $copy"
}

{
    for name in "$APP_NAME" "${OLD_NAMES[@]}"; do
        for parent in "$SCRIPT_DIR" /Applications "$HOME/Applications" "$HOME/Desktop" "$HOME/Downloads" /Volumes/*/WebstormProjects/* /Volumes/*/WebStormProjects/*; do
            echo "${parent}/${name}.app"
        done
    done
    mdfind "kMDItemCFBundleIdentifier == '${BUNDLE_ID}'" 2>/dev/null || true
} | while IFS= read -r copy; do
    case "$copy" in
        "$HOME/.Trash/"*|*/.Trash/*|*/.Trashes/*) continue ;;
        *.app) trash_copy "$copy" ;;
    esac
done
