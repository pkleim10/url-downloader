#!/bin/bash
# Build the native Siphon app and (optionally) install it to /Applications.
#
# Default: Release build, auto-bumps CURRENT_PROJECT_VERSION in project.yml, runs the tests.
#
# Flags:
#   --debug                 Build Debug instead of Release.
#   --no-bump               Skip the build-number bump.
#   --no-tests              Skip the unit tests.
#   --integration           Also run IntegrationTests (real yt-dlp download over the network).
#   --install               Copy the build to /Applications/Siphon.app.
#   --replace-web-launcher  Allow --install to replace the web version's launcher
#                           (bundle id com.local.url-downloader) at that path.

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="Release"
BUMP=1
TESTS=1
INTEGRATION=0
INSTALL=0
REPLACE_LAUNCHER=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIG="Debug"; shift ;;
    --no-bump) BUMP=0; shift ;;
    --no-tests) TESTS=0; shift ;;
    --integration) INTEGRATION=1; shift ;;
    --install) INSTALL=1; shift ;;
    --replace-web-launcher) REPLACE_LAUNCHER=1; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

PROJECT_YML="project.yml"

if [[ $BUMP -eq 1 ]]; then
  CURRENT_BUILD=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$PROJECT_YML")
  NEW_BUILD=$((CURRENT_BUILD + 1))
  sed -i '' -E "s/(CURRENT_PROJECT_VERSION: \")[0-9]+(\")/\1${NEW_BUILD}\2/" "$PROJECT_YML"
  echo "Bumped build: ${CURRENT_BUILD} -> ${NEW_BUILD}"
else
  NEW_BUILD=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$PROJECT_YML")
fi
MARKETING=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$PROJECT_YML")
echo "Version: ${MARKETING} (${NEW_BUILD}) [${CONFIG}]"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found on PATH (brew install xcodegen)" >&2
  exit 1
fi
xcodegen generate >/dev/null

DERIVED="DerivedData"
BUILD_LOG=$(mktemp -t siphon-build.XXXXXX)
trap 'rm -f "$BUILD_LOG"' EXIT

run_xcodebuild() {
  local action="$1"
  shift
  set +e
  xcodebuild -project Siphon.xcodeproj -scheme Siphon -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" "$action" "$@" >"$BUILD_LOG" 2>&1
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    echo "${action} FAILED (exit ${status}). Last 40 lines:" >&2
    grep -E "error:|failed|✘" "$BUILD_LOG" | tail -40 >&2 || tail -40 "$BUILD_LOG" >&2
    exit $status
  fi
}

echo "Building (${CONFIG})..."
run_xcodebuild build

if [[ $TESTS -eq 1 ]]; then
  echo "Testing..."
  if [[ $INTEGRATION -eq 1 ]]; then
    run_xcodebuild test
  else
    run_xcodebuild test -skip-testing:SiphonTests/IntegrationTests
  fi
  grep -E "Test run with|tests? passed|Executed" "$BUILD_LOG" | tail -3 || true
fi

APP_PATH="${DERIVED}/Build/Products/${CONFIG}/Siphon.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi
echo "Built: $(cd "$(dirname "$APP_PATH")" && pwd)/Siphon.app"

if [[ $INSTALL -eq 1 ]]; then
  DEST="/Applications/Siphon.app"
  if [[ -d "$DEST" ]]; then
    EXISTING_ID=$(defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
    if [[ "$EXISTING_ID" == "com.local.url-downloader" && $REPLACE_LAUNCHER -eq 0 ]]; then
      echo "✗ ${DEST} is the web version's launcher; rerun with --replace-web-launcher to replace it" >&2
      exit 1
    fi
    if [[ -n "$EXISTING_ID" && "$EXISTING_ID" != "com.machiilabs.siphon" && "$EXISTING_ID" != "com.local.url-downloader" ]]; then
      echo "✗ ${DEST} is a different app (${EXISTING_ID}); not replacing it" >&2
      exit 1
    fi
    rm -rf "$DEST"
  fi
  ditto "$APP_PATH" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
  echo "Installed: ${DEST}"
fi

echo ""
echo "✓ Siphon ${MARKETING} (${NEW_BUILD}) [${CONFIG}]"
