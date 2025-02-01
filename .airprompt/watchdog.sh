#!/usr/bin/env bash
# Watchdog: keeps backend and ngrok alive. Runs in background.
set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT="/Users/aakashnarukula/Developer/Air Prompt"
RUN_DIR="$ROOT/.run"
BACKEND_DIR="$ROOT/backend"
BACKEND_LOG="$RUN_DIR/backend.log"
NGROK_LOG="$RUN_DIR/ngrok.log"
NGROK_CONFIG_FILE="$RUN_DIR/ngrok-airprompt.yml"
NGROK_API_URL="http://127.0.0.1:4040/api/tunnels"
AIR_PROMPT_NGROK_DOMAIN="${AIR_PROMPT_NGROK_DOMAIN:-renetta-nonvisiting-harder.ngrok-free.dev}"
PUBLIC_URL="https://$AIR_PROMPT_NGROK_DOMAIN"
CHECK_INTERVAL=5

mkdir -p "$RUN_DIR"
echo $$ > "$RUN_DIR/watchdog.pid"

is_backend_up() {
  /usr/bin/curl -sf http://127.0.0.1:8787/health >/dev/null 2>&1
}

is_ngrok_up() {
  /usr/bin/curl -sf "$NGROK_API_URL" >/dev/null 2>&1
}

start_backend() {
  echo "[watchdog] Starting backend..."
  (
    cd "$BACKEND_DIR"
    APP_BASE_URL="$PUBLIC_URL" /opt/homebrew/bin/npm run dev >>"$BACKEND_LOG" 2>&1
  ) &
  local pid=$!
  echo "$pid" > "$RUN_DIR/backend.pid"
  # Wait for it to be healthy
  for _ in {1..15}; do
    if is_backend_up; then
      echo "[watchdog] Backend up (pid $pid)"
      return 0
    fi
    sleep 1
  done
  echo "[watchdog] Backend failed to start"
  return 1
}

start_ngrok() {
  echo "[watchdog] Starting ngrok..."
  /opt/homebrew/bin/ngrok http \
    --config="$NGROK_CONFIG_FILE" \
    --url="$PUBLIC_URL" \
    8787 >>"$NGROK_LOG" 2>&1 &
  local pid=$!
  echo "$pid" > "$RUN_DIR/ngrok.pid"
  for _ in {1..15}; do
    if is_ngrok_up; then
      echo "[watchdog] ngrok up (pid $pid)"
      return 0
    fi
    sleep 1
  done
  echo "[watchdog] ngrok failed to start"
  return 1
}

echo "[watchdog] Started. Monitoring backend + ngrok every ${CHECK_INTERVAL}s."

while true; do
  if ! is_backend_up; then
    echo "[watchdog] Backend down, restarting..."
    # Kill stale process on port
    pids="$(/usr/sbin/lsof -ti tcp:8787 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
      /bin/kill $pids 2>/dev/null || true
      sleep 1
    fi
    start_backend
  fi

  if ! is_ngrok_up; then
    echo "[watchdog] ngrok down, restarting..."
    /usr/bin/pkill -f "ngrok http" 2>/dev/null || true
    sleep 1
    # Backend might have died from the port kill, wait for it
    if ! is_backend_up; then
      sleep 2
      if ! is_backend_up; then
        start_backend
      fi
    fi
    start_ngrok
  fi

  sleep "$CHECK_INTERVAL"
done
