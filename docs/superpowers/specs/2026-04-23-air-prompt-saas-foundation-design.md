# Air Prompt SaaS Foundation — V1 Design

Date: 2026-04-23
Author: Aakash + Claude
Status: Draft, awaiting approval

## Goal

Convert Air Prompt from single-user local demo into a multi-user SaaS private-beta backend with a new PWA client. Ship V1 in 3–5 days full focus.

## Non-goals for V1

- Tauri Mac/Windows widget rewrite (V2)
- Stripe billing and plan gating (V3)
- Transcript history, search, export (out of scope per ephemeral decision)
- Native iOS/Android apps (PWA only, per audience decision)
- Custom domain (free `.fly.dev` subdomain for beta)
- Code signing (tech-audience distribution, unsigned OK)
- Observability stack polish (V4)
- Landing page / marketing site (V4)

## Product scope V1

Tech-audience private beta.

- Users sign in with Google / Apple / GitHub (Firebase Auth)
- Each user opens the PWA on a phone → scans QR from Mac widget → pairs
- Phone PWA transcribes speech on-device via Web Speech API
- Text → backend → Gemini Flash-Lite cleanup → Mac widget → auto-paste into focused app
- Sessions scoped per user; no cross-user leakage
- All endpoints require authentication
- Ephemeral: no transcripts stored server-side
- Free tier only (no billing yet); usage tracked for future quota enforcement

## Architecture

```
┌─────────────────┐       ┌──────────────────┐        ┌──────────────────┐
│  Mobile PWA     │       │    Backend       │        │  Mac Widget      │
│  (browser)      │       │  (Fly.io Node)   │        │  (existing Swift)│
├─────────────────┤       ├──────────────────┤        ├──────────────────┤
│ Web Speech API  │◄─WS──►│  WS relay        │◄─WS───►│ URLSessionWS     │
│ Firebase SDK    │       │  Firebase Admin  │        │ Firebase SDK     │
│ QR scan         │       │  Gemini API      │        │ QR generator     │
│ ID token attach │       │  Postgres (Fly)  │        │ Auto-paste (AX)  │
└─────────────────┘       └──────────────────┘        └──────────────────┘
                                   │
                                   ▼
                          ┌──────────────────┐
                          │  Gemini API      │
                          │  (Flash-Lite)    │
                          └──────────────────┘
```

- **Backend:** Node.js + `ws`, single process on Fly.io Machine. Postgres for users and usage events. No audio streaming. Text-only relay.
- **PWA:** Vanilla TS (keep current stack). Web Speech API replaces server STT. Firebase Auth JS SDK. Service worker kept.
- **Mac widget (unchanged in V1):** Existing Swift app. Add Firebase ID-token Authorization header. No Tauri yet.
- **Gemini:** Server-to-server, API key in Fly Secrets.
- **Firebase:** Auth only. Users stored in both Firebase (identity) and Postgres (app-level user row + usage).

## Auth flow

1. User opens PWA, clicks "Sign in with Google/Apple/GitHub"
2. Firebase Auth handles OAuth dance in popup/redirect
3. Firebase returns ID token (JWT) to PWA
4. PWA attaches `Authorization: Bearer <idToken>` to every backend request and sends it in the first WS message
5. Backend verifies ID token via Firebase Admin SDK on every connect
6. First time a Firebase UID appears → backend upserts `users` row with email
7. Subsequent requests validate same UID owns the session

Mac widget follows same flow. Uses Firebase Auth native SDK for Apple/macOS (or loads a small embedded OAuth webview — decide during implementation).

## Session & pairing model

- Session ID = UUIDv4, generated server-side on Mac widget's `create-session` request
- Session is owned by a user_id (authenticated Firebase UID)
- QR contains `https://airprompt.fly.dev/?session=<uuid>&owner=<userId>`
- Phone scans, PWA signs in (if not already), opens WS
- On WS pair: backend verifies the phone user's Firebase UID matches the session owner — rejects otherwise
- Session TTL 30 min idle; cleaned up by background reaper
- In-memory only (Redis not needed for V1 since single-process deploy)

## Data flow (transcription)

1. User holds "push-to-talk" on phone PWA
2. `SpeechRecognition` instance starts → emits interim + final transcripts (browser vendor does STT)
3. On final recognition result, PWA sends `{type: "transcript", text, mode, seq}` over WS
4. Backend receives text → calls Gemini Flash-Lite with cleanup system prompt → receives cleaned text (~500ms–1.5s)
5. Backend forwards `{type: "final", text, mode, deliveryId}` to paired Mac widget over WS
6. Mac widget receives → auto-paste via AXUIElement → sends `{type: "ack", deliveryId}` back
7. Backend records `usage_events` row: `(user_id, timestamp, raw_char_count, clean_char_count, mode)`

Interim partials (from Web Speech API) can be sent for UI feedback on widget but do not go through Gemini.

## Shared protocol v2

New fields marked `+`. Removes audio chunks entirely.

Client → Server:
- `{type: "hello", idToken, device: "mobile" | "mac", sessionId?}` **+**
- `{type: "create_session"}` (mac only) **+**
- `{type: "join_session", sessionId}` (mobile) **+**
- `{type: "transcript", text, mode: "raw"|"prompt", seq}` **+**
- `{type: "mode", mode}`
- `{type: "ack", deliveryId}`
- `{type: "ping", ts}`

Server → Client:
- `{type: "session_created", sessionId, joinUrl}` **+**
- `{type: "paired", sessionId, peerConnected}`
- `{type: "final", text, mode, deliveryId}`
- `{type: "error", code, message}`
- `{type: "pong", ts}`

All messages include `protocolVersion: "2"` — reject older clients with clear upgrade prompt.

Audio chunk messages (`audio`, `start`, `stop`, `partial`) removed.

## Data model (Postgres)

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid TEXT UNIQUE NOT NULL,
  email TEXT NOT NULL,
  provider TEXT NOT NULL, -- 'google' | 'apple' | 'github'
  plan_tier TEXT NOT NULL DEFAULT 'free',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ
);

CREATE INDEX idx_users_firebase_uid ON users(firebase_uid);

CREATE TABLE usage_events (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  mode TEXT NOT NULL, -- 'raw' | 'prompt'
  input_chars INT NOT NULL,
  output_chars INT NOT NULL,
  llm_tokens_in INT,
  llm_tokens_out INT,
  llm_cost_usd NUMERIC(10,6)
);

CREATE INDEX idx_usage_user_date ON usage_events(user_id, created_at);
```

No transcript content stored. Only lengths + metadata.

## Backend file layout

Refactor current monolithic `backend/src/server.ts` into modules:

```
backend/src/
  server.ts           // http + ws entry
  config.ts           // env loading
  auth.ts             // Firebase Admin verification
  sessions.ts         // in-memory session store + pairing
  protocol.ts         // shared message types (imports from /shared)
  gemini.ts           // Gemini Flash-Lite cleanup call
  db.ts               // Postgres pool
  usage.ts            // record usage_events
  routes/
    health.ts
    session.ts
  ws/
    handler.ts        // per-connection state machine
    messages.ts       // message dispatch
```

Each module < 200 lines. Replace singleton globals with injected dependencies where reasonable.

## Deployment

- **Fly.io app:** `airprompt` (pick on deploy)
- **Region:** `bom` (Mumbai) — closest to user; add regions later
- **VM:** shared-cpu-1x, 512MB RAM (start small)
- **Postgres:** Fly Managed Postgres tiny instance OR self-managed on a second small Machine to save cost
- **Secrets:** `fly secrets set FIREBASE_*=... GEMINI_API_KEY=...`
- **Deploy:** Dockerfile (Node 20-alpine), `fly deploy` on push
- **Static PWA:** built at image build time, served by backend (same origin, keeps WS simple)
- **CI:** simple GitHub Action runs `fly deploy` on `main`

## Distribution (V1)

- **PWA:** `https://airprompt.fly.dev/` — users bookmark, add to home screen
- **Mac widget:** existing Swift app — distributed as direct `.dmg` download. Tech-audience accepts unsigned.
- **Windows:** not in V1.
- **Homebrew cask / Scoop / winget:** V2.

## Error handling

- Gemini call fails → return raw text with `fallback: true` flag, log error. User sees unpolished text but no hard failure.
- Firebase token invalid/expired → WS closes with `{code: "unauthenticated"}`, PWA forces re-login
- Session TTL expired → close WS, client regenerates session
- Mac widget disconnected mid-session → buffer last N final messages, replay on reconnect (existing logic)
- Deepgram removed; no audio pipeline failure modes

## Testing

- Unit: `gemini.ts` cleanup prompt building, `auth.ts` token verification, `sessions.ts` pairing logic
- Integration: spin up backend + fake Firebase admin, assert auth required on all endpoints
- Manual smoke test per build: PWA login → QR pair to Mac widget → speak → see pasted text
- No automated E2E yet (V4)

## Observability (minimal V1)

- Structured JSON logs to stdout → Fly logs (good enough for beta)
- `/health` endpoint returns `{ok, db, uptime}`
- No Prometheus yet
- Sentry free tier for error tracking (one env var away)

## Security (V1 minimum)

- All WS and HTTP endpoints require Firebase ID token
- WS handshake validates `Origin` header against allowlist (`airprompt.fly.dev` + localhost dev)
- CORS locked to same origin + localhost
- Secrets only in Fly Secrets, never committed
- No hardcoded VAPID/ngrok keys in repo (push notifications removed from V1 scope — revisit later)
- Rate limit per user (token bucket, in-memory): max 60 Gemini cleanup calls/min per user
- Max 10 paired WebSocket sessions active per user concurrently

## Cost model V1

At private beta 100 users × 2 hr/day:

- Fly.io VM + Postgres: ~$13/mo
- Gemini Flash-Lite cleanup: ~$39/mo
- Firebase Auth: free tier
- Sentry: free tier
- **Total: ~$52/mo**

## Rollout

- Day 1: backend refactor + Firebase Auth integration + DB schema
- Day 2: Gemini cleanup + new protocol + session pairing per-user
- Day 3: PWA rewrite (Web Speech API, auth, new protocol)
- Day 4: Mac widget patch (attach ID token, new protocol), deploy to Fly.io
- Day 5: bug bash with self + 2-3 trusted users

Days are optimistic best-case; real slippage likely. Private beta opens once Day-5 smoke tests pass reliably. Collect feedback, iterate before V2.

## Open questions

- Mac widget auth: V1 uses a thin embedded WKWebView for OAuth. Webview loads the same PWA `/login` page, completes Firebase OAuth in the webview, page posts the ID token back to the native app via `window.webkit.messageHandlers`. Avoids bundling native Firebase SDK. Decision locked.
- Do we keep the PWA audio visualizer? It was nice UX with MediaRecorder but Web Speech API gives us transcript events, not audio frames. Option to drop it or keep a fake one synced to speech events.
- Rate-limit values (60 calls/min, 10 sessions) — first-pass guesses; tune after beta.

## Archived

Current `mac-widget/` Swift code stays in place for V1 (reused with small patches). Will move to `mac-widget-legacy/` when V2 Tauri rewrite starts.

All Deepgram code paths deleted in V1 backend refactor. No dual-mode retained.

Push notification code (VAPID, web-push) removed from V1 scope — was useful when server originated session events but with user-scoped auth it's not needed in the core flow. Can reintroduce later.
