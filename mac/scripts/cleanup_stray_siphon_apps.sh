#!/bin/bash
# Remove Siphon app copies other than /Applications/Siphon.app, including the retired
# web-version launchers (bundle id com.local.url-downloader: Siphon, Downloader,
# URL Downloader). Re-registers the canonical copy at the end.
#
# Called automatically from build_and_install.sh after each install.

set -euo pipefail

CANONICAL="/Applications/Siphon.app"
BUNDLE_ID="com.machiilabs.siphon"
LAUNCHER_BUNDLE_ID="com.local.url-downloader"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
MAC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"

removed=0

unregister_app() {
  [[ -x "$LSREGISTER" ]] || return 0
  "$LSREGISTER" -u "$1" >/dev/null 2>&1 || true
}

bundle_id_of() {
  defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null || true
}

remove_app() {
  local path="$1"
  [[ -n "$path" && -d "$path" ]] || return 0
  [[ "$path" == "$CANONICAL" || "$path" == "${CANONICAL}/"* ]] && return 0
  # Only ever touch our own bundles; other apps may share the name
  local id
  id="$(bundle_id_of "$path")"
  [[ "$id" == "$BUNDLE_ID" || "$id" == "$LAUNCHER_BUNDLE_ID" ]] || return 0
  unregister_app "$path"
  if rm -rf "$path" 2>/dev/null; then
    echo "Removed stray app: ${path}"
    removed=$((removed + 1))
  else
    echo "Note: could not delete ${path}; remove it manually." >&2
  fi
}

# Build products (the installed copy is the only one that should launch)
for config in Debug Release; do
  remove_app "${MAC_ROOT}/DerivedData/Build/Products/${config}/Siphon.app"
done
for dd_root in "${HOME}/Library/Developer/Xcode/DerivedData"/Siphon-*; do
  [[ -d "$dd_root" ]] || continue
  remove_app "${dd_root}/Build/Products/Debug/Siphon.app"
  remove_app "${dd_root}/Build/Products/Release/Siphon.app"
done

# Former names and places of the web launcher, and other clones of this project
for name in Siphon Downloader "URL Downloader"; do
  for parent in "$REPO_ROOT" /Applications "${HOME}/Applications" "${HOME}/Desktop" "${HOME}/Downloads" \
    /Volumes/*/WebstormProjects/* /Volumes/*/WebStormProjects/*; do
    remove_app "${parent}/${name}.app"
  done
done

# Anything else Spotlight knows by either bundle id (Trash excluded)
while IFS= read -r path; do
  case "$path" in
    "${HOME}/.Trash/"*|*/.Trash/*|*/.Trashes/*) unregister_app "$path" ;;
    *.app) remove_app "$path" ;;
  esac
done < <(mdfind "kMDItemCFBundleIdentifier == '${BUNDLE_ID}' || kMDItemCFBundleIdentifier == '${LAUNCHER_BUNDLE_ID}'" 2>/dev/null || true)

if [[ -d "$CANONICAL" && -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$CANONICAL" >/dev/null 2>&1 || true
  mdimport "$CANONICAL" >/dev/null 2>&1 || true
fi

if [[ $removed -eq 0 ]]; then
  echo "No stray Siphon.app copies found (canonical: ${CANONICAL})."
else
  echo "Cleaned ${removed} stray Siphon.app cop$( [[ $removed -eq 1 ]] && echo y || echo ies )."
fi
