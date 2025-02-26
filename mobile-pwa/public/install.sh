#!/usr/bin/env bash
# Air Prompt installer — downloads latest release and installs to /Applications.
# Usage:  curl -fsSL https://raw.githubusercontent.com/gyftalala/airprompt/main/install.sh | bash
set -euo pipefail

REPO="${AIRPROMPT_REPO:-gyftalala/airprompt}"
APP_NAME="AirPrompt.app"
INSTALL_DIR="/Applications"
TMP="$(mktemp -d -t airprompt)"
trap 'rm -rf "$TMP"' EXIT

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }
}
require curl
require unzip

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Air Prompt is macOS-only." >&2
  exit 1
fi

echo "==> Finding latest release…"
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | /usr/bin/awk -F'"' '/"browser_download_url":.*AirPrompt-.*\.zip"/ {print $4; exit}')"

if [[ -z "$URL" ]]; then
  echo "Could not find a release asset. Is the repo published?" >&2
  exit 1
fi

echo "==> Downloading $URL"
curl -fL --progress-bar "$URL" -o "$TMP/AirPrompt.zip"

echo "==> Unpacking"
unzip -q "$TMP/AirPrompt.zip" -d "$TMP"
[[ -d "$TMP/$APP_NAME" ]] || { echo "zip missing $APP_NAME" >&2; exit 1; }

echo "==> Removing quarantine"
/usr/bin/xattr -dr com.apple.quarantine "$TMP/$APP_NAME" || true

if [[ -d "$INSTALL_DIR/$APP_NAME" ]]; then
  echo "==> Removing existing $INSTALL_DIR/$APP_NAME"
  rm -rf "$INSTALL_DIR/$APP_NAME"
fi

echo "==> Installing to $INSTALL_DIR"
if ! mv "$TMP/$APP_NAME" "$INSTALL_DIR/"; then
  echo "Permission denied — retrying with sudo"
  sudo mv "$TMP/$APP_NAME" "$INSTALL_DIR/"
fi

echo
echo "Installed: $INSTALL_DIR/$APP_NAME"
echo "Launching…"
open "$INSTALL_DIR/$APP_NAME"
