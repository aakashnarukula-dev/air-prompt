#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT="/Users/aakashnarukula/Developer/Air Prompt"
RUN_DIR="$ROOT/.run"
KILL_BIN="/bin/kill"
PKILL_BIN="/usr/bin/pkill"
OSASCRIPT_BIN="/usr/bin/osascript"

for file in "$RUN_DIR"/*.pid; do
  [[ -f "$file" ]] || continue
  pid="$(cat "$file")"
  "$KILL_BIN" "$pid" 2>/dev/null || true
done

"$PKILL_BIN" -f "watchdog.sh" 2>/dev/null || true
"$PKILL_BIN" -f "ngrok http 8787" 2>/dev/null || true
"$PKILL_BIN" -f "ngrok http.*8787" 2>/dev/null || true
"$PKILL_BIN" -f "swift run AirPrompt" 2>/dev/null || true
"$PKILL_BIN" -f "/.airprompt/Air Prompt Widget.app/Contents/MacOS/AirPrompt" 2>/dev/null || true
"$OSASCRIPT_BIN" -e 'tell application id "com.airprompt.widget" to quit' >/dev/null 2>&1 || true

rm -f "$RUN_DIR"/*.pid "$RUN_DIR/public_url" "$RUN_DIR"/widget.path "$RUN_DIR"/demo-config.json 2>/dev/null || true

echo "Air Prompt demo stopped."
