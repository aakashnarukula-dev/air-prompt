#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT="/Users/aakashnarukula/Developer/Air Prompt"
APP_PATH="$ROOT/Air Prompt.app"
DMG_PATH="$ROOT/Air Prompt.dmg"
STAGE_DIR="$ROOT/.run/dmg-staging"
RW_DMG_GLOB="$ROOT"/rw.*.Air\ Prompt.dmg
BACKGROUND_SVG="$ROOT/assets/dmg/background.svg"
BACKGROUND_PNG="$ROOT/assets/dmg/background.png"
LN_BIN="/bin/ln"
CP_BIN="/bin/cp"
RM_BIN="/bin/rm"
MKDIR_BIN="/bin/mkdir"
QLMANAGE_BIN="/usr/bin/qlmanage"
CREATE_DMG_BIN="/opt/homebrew/bin/create-dmg"

"$ROOT/.airprompt/build-launcher-app.sh" >/dev/null

"/usr/bin/hdiutil" detach "/Volumes/Air Prompt" 2>/dev/null || true
"$RM_BIN" -rf "$STAGE_DIR" "$DMG_PATH"
"$RM_BIN" -f $RW_DMG_GLOB 2>/dev/null || true
"$MKDIR_BIN" -p "$STAGE_DIR/.background"
"$QLMANAGE_BIN" -t -s 500 -o "$ROOT/assets/dmg" "$BACKGROUND_SVG" >/dev/null
"$CP_BIN" "$BACKGROUND_SVG.png" "$BACKGROUND_PNG"
"$CP_BIN" -R "$APP_PATH" "$STAGE_DIR/"
"$CP_BIN" "$BACKGROUND_PNG" "$STAGE_DIR/.background/background.png"

"$CREATE_DMG_BIN" \
  --volname "Air Prompt" \
  --background "$BACKGROUND_PNG" \
  --window-pos 200 120 \
  --window-size 500 340 \
  --icon-size 116 \
  --icon "Air Prompt.app" 130 160 \
  --icon "Applications" 370 160 \
  --hide-extension "Air Prompt.app" \
  --app-drop-link 370 160 \
  "$DMG_PATH" \
  "$STAGE_DIR" >/dev/null

"$RM_BIN" -f $RW_DMG_GLOB 2>/dev/null || true

echo "$DMG_PATH"
