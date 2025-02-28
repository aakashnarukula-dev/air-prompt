<p align="center">
  <img src="assets/icon/air-prompt-icon.svg" width="120" alt="Air Prompt">
</p>

<h1 align="center">Air Prompt</h1>

<p align="center">
  <b>Speak on your phone. Cleaned text pastes on your Mac.</b><br>
  On-device speech recognition · AI cleanup · QR pairing · auto-paste.
</p>

<p align="center">
  <img src="assets/walkthrough/00-hero.png" alt="Air Prompt hero">
</p>

---

## What it is

Air Prompt is a cross-device dictation tool. You hold a button on your phone, speak, and the cleaned transcription appears in whichever Mac app has focus — email, Slack, code editor, wherever.

Audio never leaves the phone. Transcription happens on-device via the Web Speech API; only the resulting text is sent over an authenticated WebSocket to a relay that forwards it to your paired Mac widget.

## Features

| | |
|---|---|
| **On-device STT** | Web Speech API runs locally on the phone — no audio uploaded |
| **AI cleanup** | Optional Gemini Flash-Lite pass fixes grammar, punctuation, filler words |
| **QR pairing** | Scan the Mac widget's QR from your phone — no manual session IDs |
| **Auto-paste** | Dictated text lands in the focused Mac app via Accessibility Services |
| **Dual modes** | `raw` (verbatim) or `prompt` (AI-cleaned) — toggle per session |
| **Ephemeral** | No transcripts stored server-side — only anonymized usage metrics |
| **Multi-provider auth** | Google, Apple, GitHub — via Firebase |
| **One-line install** | `curl \| bash` on Mac; PWA on any modern phone browser |

## Install

**Mac** (universal binary, macOS 12+):

```bash
curl -fsSL https://airprompt.fly.dev/install.sh | bash
```

**Phone**: open `https://airprompt.fly.dev/` in any modern browser. Add to home screen for a full-screen PWA experience.

See [docs/install.md](docs/install.md) for fallback and manual install.

## How it works

1. Launch the widget on Mac and sign in (Google / Apple / GitHub via Firebase).
2. Click the QR icon — widget expands to show a pairing QR.
3. Open `airprompt.fly.dev` on your phone, sign in to the same account, scan the QR.
4. Press and hold **Hold to talk**. Speak. Release.
5. Text auto-pastes on your Mac.

<p align="center">
  <img src="assets/walkthrough/07-prompt-vs-raw.png" alt="Raw vs Prompt mode">
</p>

See the full [walkthrough](docs/walkthrough.md) for screen-by-screen visuals.

## Architecture

```
phone PWA              mac widget
(Web Speech API)      (SwiftUI, AX paste)
     │                      │
     └────── WebSocket ─────┘
                 │
        ┌────────┴────────┐
        │ Fly.io backend  │
        │ Node · ws · pg  │
        └───────┬─────────┘
                │
           Gemini API
        (Flash-Lite cleanup,
         prompt mode only)
```

- **No audio on the wire.** Transcription is browser-native on the phone.
- **No transcripts stored.** Backend keeps only usage counters (chars, tokens).
- **Per-user sessions.** Firebase ID token verified on every WS message.

Full detail in [docs/architecture.md](docs/architecture.md).

## Status

| | |
|---|---|
| **Mac widget** | SwiftUI, universal binary, menu-bar pill widget |
| **Phone** | PWA (Chrome / Safari / Edge) |
| **Backend** | Node.js + TypeScript on Fly.io, single region, Postgres |
| **Auth** | Firebase — Google, Apple, GitHub providers |
| **LLM** | Gemini 2.0 Flash-Lite (cleanup only) |
| **Windows** | PWA only — no native widget yet |

## Privacy

- Audio stays on-device (Web Speech API runs in-browser)
- Only the final text string is relayed; no audio bytes hit the server
- No transcript persistence — only metric rows: `(user_id, timestamp, input_chars, output_chars, mode)`
- Sessions are in-memory with a 30-minute idle TTL
- Every WebSocket message carries a Firebase ID token that the server re-verifies

## Development

### Install (macOS)

```bash
curl -fsSL https://airprompt.fly.dev/install.sh | bash
```

Or from GitHub raw:
```bash
curl -fsSL https://raw.githubusercontent.com/aakashnarukula-dev/air-prompt/main/mobile-pwa/public/install.sh | bash
```

### Release (maintainers)

```bash
VERSION=0.1.0 scripts/release.sh
```

Builds universal `AirPrompt.app`, ad-hoc signs, zips, uploads to GitHub Release `v0.1.0`.

### Repo layout

- `mobile-pwa/` — browser PWA (Web Speech API + Firebase Auth)
- `backend/` — WebSocket + Postgres + Gemini cleanup (Fly.io)
- `mac-widget/` — SwiftUI widget (QR pairing, auto-paste)
- `mac-widget-legacy/` — V1 Swift widget (archive-in-place, still used in V2)
- `shared/` — versioned protocol

### Prerequisites

- Node 20, npm
- Postgres 16 (`brew install postgresql@16 && brew services start postgresql@16`)
- Firebase project with Google + Apple + GitHub providers enabled (Apple optional)
- Gemini API key ([aistudio.google.com/apikey](https://aistudio.google.com/apikey))
- Fly.io account (`brew install flyctl`) — for production deploy
- Xcode (for mac-widget)

### Local dev

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

### Production smoke test (local)

```bash
cd backend && npm run build
cd ../mobile-pwa && npm run build
cd ../backend && PWA_DIST="$(pwd)/../mobile-pwa/dist" npm start
curl http://localhost:8787/health   # expect {"ok":true,"db":"ok",...}
open http://localhost:8787/         # PWA login page
```

### Deploy (Fly.io)

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

### Tests

```bash
cd backend && npm test    # 22 tests across config/auth/gemini/sessions/ratelimit/ws
```

### Known follow-ups (V2+)

- Tauri widget rewrite for unified Mac + Windows
- Stripe billing + freemium quota enforcement
- Swift widget SourceKit diagnostics may need manual follow-up (see mac-widget/ — `@Published` on struct error, build with `swift build` to verify)
- Apple SignIn provider (needs Apple Developer account)
- Custom domain migration once revenue-stable

## License

MIT.
