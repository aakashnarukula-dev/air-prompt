#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT="/Users/aakashnarukula/Developer/Air Prompt"
RUN_DIR="$ROOT/.run"
BACKEND_DIR="$ROOT/backend"
WIDGET_DIR="$ROOT/mac-widget"
WIDGET_APP_PATH="$ROOT/.airprompt/Air Prompt Widget.app"
BACKEND_LOG="$RUN_DIR/backend.log"
NGROK_LOG="$RUN_DIR/ngrok.log"
WIDGET_LOG="$RUN_DIR/widget.log"
PUBLIC_URL_FILE="$RUN_DIR/public_url"
DEMO_CONFIG_FILE="$RUN_DIR/demo-config.json"
AIR_PROMPT_NGROK_DOMAIN="${AIR_PROMPT_NGROK_DOMAIN:-renetta-nonvisiting-harder.ngrok-free.dev}"
AIR_PROMPT_NGROK_AUTHTOKEN="${AIR_PROMPT_NGROK_AUTHTOKEN:-3BvxZqKCOIwEVO7GDa9fR1VrhYy_862ZZCdkDVHj6x5faSRp6}"
NGROK_CONFIG_FILE="$RUN_DIR/ngrok-airprompt.yml"
NGROK_API_URL="http://127.0.0.1:4040/api/tunnels"
APP_BUNDLE="$WIDGET_APP_PATH"
BUILT_WIDGET_BINARY="$WIDGET_DIR/.build/debug/AirPrompt"
NPM_BIN="/opt/homebrew/bin/npm"
NGROK_BIN="/opt/homebrew/bin/ngrok"
CURL_BIN="/usr/bin/curl"
LSOF_BIN="/usr/sbin/lsof"
KILL_BIN="/bin/kill"
PKILL_BIN="/usr/bin/pkill"
OPEN_BIN="/usr/bin/open"

mkdir -p "$RUN_DIR"

cleanup_port() {
  local port="$1"
  local pids
  pids="$("$LSOF_BIN" -ti tcp:"$port" 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    "$KILL_BIN" $pids 2>/dev/null || true
  fi
}

cleanup_name() {
  local pattern="$1"
  "$PKILL_BIN" -f "$pattern" 2>/dev/null || true
}

current_public_url() {
  ("$CURL_BIN" -sf "$NGROK_API_URL" 2>/dev/null || true) \
    | tr ',' '\n' \
    | awk '
        /"public_url":"https:/ { gsub(/.*"public_url":"|"$/, "", $0); public_url=$0 }
        /"addr":"http:\/\/localhost:8787"/ { if (public_url != "") { print public_url; exit } }
      '
}

write_ngrok_config() {
  cat > "$NGROK_CONFIG_FILE" <<EOF
version: "3"
agent:
  authtoken: $AIR_PROMPT_NGROK_AUTHTOKEN
  web_addr: 127.0.0.1:4040
EOF
}

ensure_ngrok() {
  local url=""
  url="$(current_public_url)"
  if [[ -n "$url" ]]; then
    printf '%s' "$url"
    return 0
  fi

  write_ngrok_config
  "$NGROK_BIN" http --config="$NGROK_CONFIG_FILE" --url="https://$AIR_PROMPT_NGROK_DOMAIN" 8787 >"$NGROK_LOG" 2>&1 &
  NGROK_PID=$!
  echo "$NGROK_PID" > "$RUN_DIR/ngrok.pid"

  for _ in {1..30}; do
    url="$(current_public_url)"
    if [[ -n "$url" ]]; then
      printf '%s' "$url"
      return 0
    fi
    sleep 1
  done

  return 1
}

needs_widget_rebuild() {
  [[ ! -x "$APP_BUNDLE/Contents/MacOS/AirPrompt" ]] && return 0
  [[ ! -x "$BUILT_WIDGET_BINARY" ]] && return 0
  [[ "$BUILT_WIDGET_BINARY" -nt "$APP_BUNDLE/Contents/MacOS/AirPrompt" ]] && return 0

  if find "$WIDGET_DIR/Sources" "$WIDGET_DIR/Package.swift" "$ROOT/assets/icon/AirPrompt.icns" "$ROOT/assets/icon/MenuBarTemplateIcon.png" -newer "$APP_BUNDLE/Contents/MacOS/AirPrompt" -print -quit | grep -q .; then
    return 0
  fi

  return 1
}

echo "Starting Air Prompt demo..."

cleanup_port 8787
cleanup_name "swift run AirPrompt"
cleanup_name "$APP_BUNDLE/Contents/MacOS/AirPrompt"

start_backend() {
  local public_url="${1:-}"
  (
    cd "$BACKEND_DIR"
    if [[ -n "$public_url" ]]; then
      APP_BASE_URL="$public_url" "$NPM_BIN" run dev >"$BACKEND_LOG" 2>&1
    else
      "$NPM_BIN" run dev >"$BACKEND_LOG" 2>&1
    fi
  ) &
  BACKEND_PID=$!
  echo "$BACKEND_PID" > "$RUN_DIR/backend.pid"
}

echo "1/3 Starting backend..."
start_backend

for _ in {1..30}; do
  if "$CURL_BIN" -sf http://127.0.0.1:8787/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! "$CURL_BIN" -sf http://127.0.0.1:8787/health >/dev/null 2>&1; then
  echo "Backend failed to start. See $BACKEND_LOG"
  exit 1
fi

echo "2/3 Ensuring secure tunnel..."
PUBLIC_URL="$(ensure_ngrok)"

if [[ -z "$PUBLIC_URL" ]]; then
  echo "ngrok failed to start. See $NGROK_LOG"
  if [[ -f "$NGROK_LOG" ]]; then
    echo
    echo "ngrok log:"
    sed -n '1,120p' "$NGROK_LOG"
  fi
  exit 1
fi
echo "$PUBLIC_URL" > "$PUBLIC_URL_FILE"

echo "Tunnel ready: $PUBLIC_URL"
echo "3/3 Launching widget..."

kill "$BACKEND_PID" 2>/dev/null || true
wait "$BACKEND_PID" 2>/dev/null || true
cleanup_port 8787
start_backend "$PUBLIC_URL"

for _ in {1..30}; do
  if "$CURL_BIN" -sf http://127.0.0.1:8787/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

cat > "$DEMO_CONFIG_FILE" <<JSON
{"mobileURL":"$PUBLIC_URL","backendURL":"http://localhost:8787"}
JSON

if needs_widget_rebuild; then
  APP_PATH="$("$ROOT/.airprompt/build-widget-app.sh")"
else
  APP_PATH="$APP_BUNDLE"
fi
"$OPEN_BIN" "$APP_PATH"
echo "$APP_PATH" > "$RUN_DIR/widget.path"

echo
echo "Air Prompt demo is running."
echo "Public URL: $PUBLIC_URL"
echo "Share this with friends: $PUBLIC_URL"
echo

# Kill any old watchdog
if [[ -f "$RUN_DIR/watchdog.pid" ]]; then
  "$KILL_BIN" "$(cat "$RUN_DIR/watchdog.pid")" 2>/dev/null || true
fi

# Start watchdog to auto-restart backend + ngrok if either dies
"$ROOT/.airprompt/watchdog.sh" >>"$RUN_DIR/watchdog.log" 2>&1 &
echo "$!" > "$RUN_DIR/watchdog.pid"
echo "Watchdog running (auto-restarts backend + ngrok)."

echo
echo "Logs:"
echo "  backend:  $BACKEND_LOG"
echo "  ngrok:    $NGROK_LOG"
echo "  watchdog: $RUN_DIR/watchdog.log"
echo "  app:      $APP_PATH"
