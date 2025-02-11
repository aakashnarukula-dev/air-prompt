#!/usr/bin/env bash
# Build Air Prompt widget + install into .airprompt/Air Prompt Widget.app
# (the bundle the Air Prompt.app launcher spawns).
# Usage:  ./build-app.sh          → debug
#         ./build-app.sh release  → release
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

# Primary install target: the .airprompt bundle used by the launcher.
LAUNCHER_APP="../.airprompt/Air Prompt Widget.app"
if [[ -d "$LAUNCHER_APP" ]]; then
  cp "$BIN" "$LAUNCHER_APP/Contents/MacOS/AirPrompt"
  cp Sources/AirPrompt/Info.plist "$LAUNCHER_APP/Contents/Info.plist" 2>/dev/null || true
  codesign --force --sign - --identifier com.airprompt.widget --timestamp=none "$LAUNCHER_APP"
  echo "Updated: $LAUNCHER_APP"
fi

# Secondary: standalone build/AirPrompt.app for direct testing.
APP="build/AirPrompt.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AirPrompt"
cp Sources/AirPrompt/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.airprompt.widget --timestamp=none "$APP"
echo "Built:   $APP"
