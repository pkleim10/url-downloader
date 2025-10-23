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

# Create the executable script
cat > "${MACOS_DIR}/URL Downloader" << 'EOF'
#!/bin/bash

# URL Downloader App
# Get the directory where this app is located
APP_DIR="$(dirname "$(dirname "$(dirname "$(dirname "$0")")")")"
PROJECT_DIR="$(dirname "$APP_DIR")"

# Change to the project directory
cd "$PROJECT_DIR"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    osascript -e 'display dialog "Error: Node.js is not installed or not in PATH. Please install Node.js from https://nodejs.org/" buttons {"OK"} default button "OK"'
    exit 1
fi

# Check if yt-dlp is installed
if ! command -v yt-dlp &> /dev/null; then
    osascript -e 'display dialog "Error: yt-dlp is not installed or not in PATH. Please install yt-dlp: brew install yt-dlp" buttons {"OK"} default button "OK"'
    exit 1
fi

# Check if dependencies are installed
if [ ! -d "node_modules" ]; then
    osascript -e 'display dialog "Installing dependencies..." buttons {"OK"} default button "OK"'
    npm install
fi

# Start the server
osascript -e 'display notification "Starting URL Downloader server..." with title "URL Downloader"'
osascript -e 'display notification "Server available at: http://127.0.0.1:3000" with title "URL Downloader"'

node server.js
EOF

# Make the executable script executable
chmod +x "${MACOS_DIR}/URL Downloader"

echo "Created ${APP_NAME}.app"
echo "You can now move this app to your Applications folder or Desktop"
echo "Double-click the app to start the URL Downloader server"