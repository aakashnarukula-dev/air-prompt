#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT="/Users/aakashnarukula/Developer/Air Prompt"
WIDGET_DIR="$ROOT/mac-widget"
APP_DIR="$ROOT/Air Prompt.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SWIFT_BIN="/usr/bin/swift"
ICON_FILE="$ROOT/assets/icon/AirPrompt.icns"

cd "$WIDGET_DIR"
"$SWIFT_BIN" build --product AirPromptLauncher >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$WIDGET_DIR/.build/debug/AirPromptLauncher" "$MACOS_DIR/AirPromptLauncher"
chmod +x "$MACOS_DIR/AirPromptLauncher"
cp "$ICON_FILE" "$RESOURCES_DIR/AirPrompt.icns"
cp "$ROOT/assets/icon/MenuBarTemplateIcon.png" "$RESOURCES_DIR/MenuBarTemplateIcon.png"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>AirPromptLauncher</string>
  <key>CFBundleIdentifier</key>
  <string>com.airprompt.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AirPrompt.icns</string>
  <key>CFBundleName</key>
  <string>Air Prompt</string>
  <key>CFBundleDisplayName</key>
  <string>Air Prompt</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
