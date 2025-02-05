import { onUser, signIn, logOut, getIdToken, type AuthProvider } from "./auth.js";
import { SpeechRecognizer } from "./speech.js";
import { WsClient } from "./ws-client.js";
import { extractSessionId } from "./qr.js";

type Mode = "raw" | "prompt";

const WS_URL = import.meta.env.VITE_BACKEND_WS_URL || `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws`;

const loginView = document.getElementById("login-view") as HTMLElement;
const pairView = document.getElementById("pair-view") as HTMLElement;
const recordView = document.getElementById("record-view") as HTMLElement;
const statusEl = document.getElementById("status") as HTMLElement;
const interimEl = document.getElementById("interim") as HTMLElement;
const modeBtn = document.getElementById("mode-toggle") as HTMLButtonElement;
const talkBtn = document.getElementById("talk-btn") as HTMLButtonElement;
const sessionInput = document.getElementById("session-input") as HTMLInputElement;
const joinBtn = document.getElementById("join-btn") as HTMLButtonElement;
const logoutBtn = document.getElementById("logout-btn") as HTMLButtonElement;

const recognizer = new SpeechRecognizer();
const ws = new WsClient();
let mode: Mode = (localStorage.getItem("airprompt-mode") as Mode) || "raw";
let seq = 0;
let sessionId: string | null = extractSessionId(location.href);

function show(el: HTMLElement) { el.hidden = false; }
function hide(el: HTMLElement) { el.hidden = true; }

loginView.querySelectorAll<HTMLButtonElement>("button[data-provider]").forEach((btn) => {
  btn.addEventListener("click", async () => {
    const p = btn.dataset.provider as AuthProvider;
    try {
      await signIn(p);
    } catch (e) {
      console.error(e);
      alert("Login failed");
    }
  });
});

modeBtn.textContent = `Mode: ${mode}`;
modeBtn.addEventListener("click", () => {
  mode = mode === "raw" ? "prompt" : "raw";
  localStorage.setItem("airprompt-mode", mode);
  modeBtn.textContent = `Mode: ${mode}`;
  ws.sendMode(mode);
});

talkBtn.addEventListener("mousedown", startTalk);
talkBtn.addEventListener("mouseup", stopTalk);
talkBtn.addEventListener("touchstart", (e) => { e.preventDefault(); startTalk(); });
talkBtn.addEventListener("touchend", (e) => { e.preventDefault(); stopTalk(); });

function startTalk() {
  statusEl.textContent = "Listening...";
  interimEl.textContent = "";
  recognizer.start({
    onInterim: (t) => { interimEl.textContent = t; },
    onFinal: (t) => {
      interimEl.textContent = "";
      seq++;
      ws.sendTranscript(t, mode, seq);
      statusEl.textContent = "Sent";
    },
    onError: (e) => { statusEl.textContent = `Error: ${e}`; },
    onEnd: () => { if (statusEl.textContent === "Listening...") statusEl.textContent = "Idle"; },
  });
}

function stopTalk() {
  recognizer.stop();
  statusEl.textContent = "Idle";
}

joinBtn.addEventListener("click", () => {
  const id = sessionInput.value.trim();
  if (!id) return;
  sessionId = id;
  connectWs(id);
});

logoutBtn.addEventListener("click", async () => {
  ws.close();
  await logOut();
});

onUser(async (user) => {
  if (!user) {
    hide(recordView); hide(pairView); show(loginView);
    return;
  }
  hide(loginView);
  if (!sessionId) { show(pairView); hide(recordView); return; }
  hide(pairView); show(recordView);
  const token = await getIdToken();
  if (!token) return;
  await connectWs(sessionId);
});

async function connectWs(sid: string) {
  const token = await getIdToken();
  if (!token) return;
  await ws.connect(WS_URL, token, "mobile", sid, {
    onPaired: (_sid, peerConnected) => {
      statusEl.textContent = peerConnected ? "Paired" : "Waiting for widget";
    },
    onFinal: (_text, _mode, deliveryId) => { ws.ack(deliveryId); },
    onError: (code, message) => {
      statusEl.textContent = `Error: ${code}`;
      if (code === "unauthenticated") logOut();
    },
    onClose: () => { statusEl.textContent = "Disconnected"; },
  });
}
