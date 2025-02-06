#!/usr/bin/env bash
# scripts/smoke-test.sh
# Usage: BASE=https://airprompt.fly.dev ./scripts/smoke-test.sh
set -euo pipefail

BASE="${BASE:-http://localhost:8787}"

echo "1) Health check..."
curl -fsS "$BASE/health" | grep -q '"ok":true' && echo "   ok"

echo "2) Static PWA index..."
curl -fsS "$BASE/" | grep -q "Air Prompt" && echo "   ok"

echo "3) Login page served..."
curl -fsSI "$BASE/login.html" | grep -q "200 OK" && echo "   ok"

echo "4) /ws rejects unauthenticated connect (timeout expected)..."
# Placeholder: full WS flow requires a real Firebase ID token.
echo "   skipped (requires ID token)"

echo ""
echo "Smoke: pass"
