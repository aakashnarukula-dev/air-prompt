# Air Prompt

Cross-device speech-to-text system with:

- `mobile-pwa`: browser-based hold-to-talk PWA
- `backend`: low-latency WebSocket relay with Deepgram + optional LLM cleanup
- `mac-widget`: SwiftUI floating widget for receive/copy/paste
- `shared`: minimal protocol shared across clients

## Quick start

1. Create `backend/.env` from `backend/.env.example`.
2. Install dependencies:

```bash
cd /Users/aakashnarukula/Developer/Air\ Prompt/backend && npm install
cd /Users/aakashnarukula/Developer/Air\ Prompt/mobile-pwa && npm install
```

3. Start backend:

```bash
cd /Users/aakashnarukula/Developer/Air\ Prompt/backend && npm run dev
```

4. Start mobile PWA:

```bash
cd /Users/aakashnarukula/Developer/Air\ Prompt/mobile-pwa && npm run dev
```

5. Open `mac-widget` in Xcode or build with SwiftPM.

## One-command demo

If `ngrok` is installed and configured, run:

```bash
cd /Users/aakashnarukula/Developer/Air\ Prompt && ./.airprompt/start-demo.sh
```

This starts:

- backend on `localhost:8787`
- `ngrok` tunnel for secure mobile access
- the macOS widget with the live HTTPS URL in its QR

To stop everything:

```bash
cd /Users/aakashnarukula/Developer/Air\ Prompt && ./.airprompt/stop-demo.sh
```

## Easiest Launch

For non-technical use on macOS, just double-click:

- `Air Prompt.app`

The launcher app starts the backend, secure tunnel, and widget with no Terminal window. Stopping is handled from the widget UI.

## DMG Build

To create a shareable disk image for non-technical Mac users:

```bash
cd /Users/aakashnarukula/Developer/Air\ Prompt && ./.airprompt/build-dmg.sh
```

This generates `Air Prompt.dmg` in the project root.

## Flow

- Mac widget generates a short session ID and QR code.
- Mobile scans QR, opens the PWA, and joins the same session.
- Hold mic to stream audio.
- `raw`: Deepgram final transcript goes straight to macOS.
- `prompt`: final transcript is cleaned once by the LLM, then sent to macOS.
