#!/bin/bash
# Build Siphon, install it to /Applications/Siphon.app, and remove every other copy.
#
# Default: Release build, auto-bumps CURRENT_PROJECT_VERSION in project.yml, runs the tests.
#
# Flags:
#   --debug        Build Debug instead of Release.
#   --no-bump      Skip the build-number bump.
#   --no-tests     Skip the unit tests.
#   --integration  Also run IntegrationTests (real yt-dlp download over the network).
#   --no-install   Build only; don't install or clean up (only when explicitly asked).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}/.."

CONFIG="Release"
BUMP=1
TESTS=1
INTEGRATION=0
INSTALL=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIG="Debug"; shift ;;
    --no-bump) BUMP=0; shift ;;
    --no-tests) TESTS=0; shift ;;
    --integration) INTEGRATION=1; shift ;;
    --no-install) INSTALL=0; shift ;;
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
echo "Built: ${APP_PATH}"

if [[ $INSTALL -eq 1 ]]; then
  DEST="/Applications/Siphon.app"
  EXISTING_ID=""
  [[ -d "$DEST" ]] && EXISTING_ID=$(defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
  # The retired web-version launcher (com.local.url-downloader) is replaced; anything else is left alone
  if [[ -n "$EXISTING_ID" && "$EXISTING_ID" != "com.machiilabs.siphon" && "$EXISTING_ID" != "com.local.url-downloader" ]]; then
    echo "✗ ${DEST} is a different app (${EXISTING_ID}); not replacing it" >&2
    exit 1
  fi

  # In-place rsync keeps the same path (and TCC grants) and works while Siphon is running.
  # When macOS blocks in-place writes (com.apple.macl after a download or Sparkle install),
  # or the old bundle is the launcher, rename it aside and copy a fresh bundle instead.
  install_ok=0
  if [[ "$EXISTING_ID" == "com.machiilabs.siphon" ]] && touch "${DEST}/Contents/.siphon_install_probe" 2>/dev/null; then
    rm -f "${DEST}/Contents/.siphon_install_probe"
    rsync -a --delete "${APP_PATH}/" "${DEST}/" && install_ok=1
  fi
  if [[ $install_ok -eq 0 ]]; then
    if [[ -d "$DEST" ]]; then
      ASIDE="${DEST}.pre-update.$$"
      rm -rf "$ASIDE"
      mv "$DEST" "$ASIDE"
      ditto "$APP_PATH" "$DEST"
      rm -rf "$ASIDE"
    else
      ditto "$APP_PATH" "$DEST"
    fi
  fi
  echo "Installed: ${DEST}"

  bash "${SCRIPT_DIR}/cleanup_stray_siphon_apps.sh"
fi

echo ""
echo "✓ Siphon ${MARKETING} (${NEW_BUILD}) [${CONFIG}]"
