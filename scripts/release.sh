#!/usr/bin/env bash
# Build, ad-hoc sign, and publish AirPrompt.app to GitHub Releases.
# Usage:  VERSION=0.1.0 scripts/release.sh
#         (or pass the version as $1)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIDGET_DIR="$ROOT/mac-widget"
DIST_DIR="$ROOT/dist"
VERSION="${1:-${VERSION:-}}"
REPO="${GH_REPO:-aakashnarukula-dev/airprompt}"

if [[ -z "$VERSION" ]]; then
  echo "VERSION required. Usage: scripts/release.sh 0.1.0" >&2
  exit 1
fi

if ! command -v gh >/dev/null; then
  echo "gh CLI missing. brew install gh && gh auth login" >&2
  exit 1
fi

echo "==> Building release binary"
cd "$WIDGET_DIR"
swift build -c release --product AirPrompt

BIN=".build/arm64-apple-macosx/release/AirPrompt"
[[ -f "$BIN" ]] || BIN=".build/release/AirPrompt"
[[ -f "$BIN" ]] || { echo "release binary missing" >&2; exit 1; }

APP_NAME="AirPrompt.app"
STAGE="$DIST_DIR/stage"
APP="$STAGE/$APP_NAME"
rm -rf "$DIST_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/AirPrompt"
cp Sources/AirPrompt/Info.plist "$APP/Contents/Info.plist"
if [[ -f "$ROOT/assets/icon/AirPrompt.icns" ]]; then
  cp "$ROOT/assets/icon/AirPrompt.icns" "$APP/Contents/Resources/AirPrompt.icns"
fi

/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - --identifier com.airprompt.widget --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

ZIP="$DIST_DIR/AirPrompt-$VERSION.zip"
echo "==> Zipping → $ZIP"
(cd "$STAGE" && ditto -c -k --keepParent "$APP_NAME" "$ZIP")

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "sha256: $SHA"

TAG="v$VERSION"
echo "==> Creating GitHub release $TAG on $REPO"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "release $TAG exists — uploading zip with --clobber"
  gh release upload "$TAG" "$ZIP" --repo "$REPO" --clobber
else
  gh release create "$TAG" "$ZIP" \
    --repo "$REPO" \
    --title "Air Prompt $VERSION" \
    --generate-notes
fi

echo
echo "Released: https://github.com/$REPO/releases/tag/$TAG"
echo "Download: https://github.com/$REPO/releases/download/$TAG/AirPrompt-$VERSION.zip"
