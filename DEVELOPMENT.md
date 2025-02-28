# Air Prompt

Cross-device speech-to-text SaaS. Speak on phone → cleaned text auto-pastes on Mac/Windows.

## Install (macOS)

```bash
curl -fsSL https://airprompt.fly.dev/install.sh | bash
```

Or from GitHub raw:
```bash
curl -fsSL https://raw.githubusercontent.com/aakashnarukula-dev/airprompt/main/mobile-pwa/public/install.sh | bash
```

## Release (maintainers)

```bash
VERSION=0.1.0 scripts/release.sh
```

Builds universal `AirPrompt.app`, ad-hoc signs, zips, uploads to GitHub Release `v0.1.0`.


- `mobile-pwa/` — browser PWA (Web Speech API + Firebase Auth)
- `backend/` — WebSocket + Postgres + Gemini cleanup (Fly.io)
- `mac-widget/` — SwiftUI widget (QR pairing, auto-paste)
- `mac-widget-legacy/` — V1 Swift widget (archive-in-place, still used in V2)
- `shared/` — versioned protocol

## Prerequisites

- Node 20, npm
- Postgres 16 (`brew install postgresql@16 && brew services start postgresql@16`)
- Firebase project with Google + Apple + GitHub providers enabled (Apple optional)
- Gemini API key ([aistudio.google.com/apikey](https://aistudio.google.com/apikey))
- Fly.io account (`brew install flyctl`) — for production deploy
- Xcode (for mac-widget)

## Local dev

```bash
# 1. Env files (already created with placeholders; fill in Firebase + Gemini)
#    backend/.env            — server secrets (Firebase admin, Gemini key, DB url)
#    mobile-pwa/.env         — public Firebase web config

# 2. Install deps
cd backend && npm install
cd ../mobile-pwa && npm install

# 3. Create DB + run migrations
createdb airprompt
cd ../backend && npm run migrate

# 4. Run backend
npm run dev                # backend on :8787 with tsx watch

# 5. In another terminal, run PWA
cd ../mobile-pwa && npm run dev   # Vite on :5173

# 6. Mac widget (in third terminal) — optional
cd ../mac-widget && swift run AirPrompt
```

## Production smoke test (local)

```bash
cd backend && npm run build
cd ../mobile-pwa && npm run build
cd ../backend && PWA_DIST="$(pwd)/../mobile-pwa/dist" npm start
curl http://localhost:8787/health   # expect {"ok":true,"db":"ok",...}
open http://localhost:8787/         # PWA login page
```

## Deploy (Fly.io)

```bash
flyctl launch            # one-time, skip if fly.toml exists
flyctl secrets set \
  FIREBASE_PROJECT_ID=... \
  FIREBASE_CLIENT_EMAIL=... \
  FIREBASE_PRIVATE_KEY='...' \
  GEMINI_API_KEY=... \
  DATABASE_URL='postgres://...' \
  ALLOWED_ORIGINS=https://airprompt.fly.dev

# Bake the PWA-side Firebase public config into the image at build time:
flyctl deploy --build-arg \
  VITE_FIREBASE_API_KEY=... \
  --build-arg VITE_FIREBASE_APP_ID=...

# Run migrations remotely
flyctl ssh console -C "node backend/dist/backend/src/migrate.js"
```

## Architecture

- Phone PWA uses Web Speech API (on-device STT) — server never sees audio
- Text → WebSocket → server → Gemini Flash-Lite cleanup (only in "prompt" mode) → Mac widget → auto-paste
- Sessions scoped per authenticated Firebase user; ephemeral (no transcript storage)
- Cost per heavy user (2 hr/day): ~$0.50/month

See `docs/superpowers/specs/2026-04-23-air-prompt-saas-foundation-design.md` for full design.

## Tests

```bash
cd backend && npm test    # 22 tests across config/auth/gemini/sessions/ratelimit/ws
```

## Known follow-ups (V2+)

- Tauri widget rewrite for unified Mac + Windows
- Stripe billing + freemium quota enforcement
- Swift widget SourceKit diagnostics may need manual follow-up (see mac-widget/ — `@Published` on struct error, build with `swift build` to verify)
- Apple SignIn provider (needs Apple Developer account)
- Custom domain migration once revenue-stable
