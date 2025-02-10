#!/usr/bin/env bash
# Build Air Prompt into a proper .app bundle so macOS TCC (mic + speech permissions) works.
# Usage:  ./build-app.sh        → builds debug
#         ./build-app.sh release → builds release
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

BIN=".build/arm64-apple-macosx/${CONFIG}/AirPrompt"
if [[ ! -f "$BIN" ]]; then
  BIN=".build/${CONFIG}/AirPrompt"
fi
if [[ ! -f "$BIN" ]]; then
  echo "Binary not found. Run swift build first." >&2
  exit 1
fi

APP="build/AirPrompt.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/AirPrompt"
cp Sources/AirPrompt/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc re-sign so macOS TCC doesn't invalidate permissions every rebuild.
# Use a stable identifier so the bundle looks like the same app across rebuilds.
codesign --force --sign - --identifier com.airprompt.widget --timestamp=none "$APP"

echo "Built: $APP"
echo "Run with:  open \"$APP\""
