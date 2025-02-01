import type { ClientMessage, Mode, ServerMessage } from "../../shared/src/protocol.js";
import "./styles.css";

const app = document.querySelector<HTMLDivElement>("#app")!;
const params = new URLSearchParams(window.location.search);
const sessionId = params.get("session") || params.get("sid") || "default";
const wsBase = `${window.location.protocol === "https:" ? "wss" : "ws"}://${window.location.host}`;
const storedMode = window.localStorage.getItem("airprompt-mode");

app.innerHTML = `
  <main class="shell">
    <section class="card">
      <div class="topline">
        <span class="brand">Air Prompt</span>
        <span id="status" class="status">Disconnected</span>
      </div>
      <div class="mode-switch" role="tablist" aria-label="Output mode">
        <button id="mode-raw" class="mode-option active" type="button" role="tab" aria-selected="true">Raw Text</button>
        <button id="mode-prompt" class="mode-option" type="button" role="tab" aria-selected="false">Prompt</button>
      </div>
      <div class="visualizer-container">
        <canvas id="visualizer"></canvas>
      </div>
      <button id="mic" class="mic">Start Talking</button>
      <div class="transcript-container">
        <p id="transcript" class="transcript">Tap start to begin streaming, then tap stop when you are done.</p>
        <button id="copy-btn" class="copy-btn" aria-label="Copy text">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
            <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
          </svg>
        </button>
      </div>
      <p id="install-hint" class="install-hint" style="display:none">Add to Home Screen for notifications without Chrome open</p>
    </section>
  </main>
`;

let mode: Mode = storedMode === "prompt" ? "prompt" : "raw";
let socket: WebSocket | null = null;
let recorder: MediaRecorder | null = null;
let isStarting = false;
let seq = 0;
let pingTimer: ReturnType<typeof setInterval> | null = null;
let lastPong = 0;
let macConnected = false;
const outbox: ClientMessage[] = [];

const statusEl = document.querySelector<HTMLSpanElement>("#status")!;
const transcriptEl = document.querySelector<HTMLParagraphElement>("#transcript")!;
const micEl = document.querySelector<HTMLButtonElement>("#mic")!;
const canvasEl = document.querySelector<HTMLCanvasElement>("#visualizer")!;
const rawModeEl = document.querySelector<HTMLButtonElement>("#mode-raw")!;
const promptModeEl = document.querySelector<HTMLButtonElement>("#mode-prompt")!;
const canvasCtx = canvasEl.getContext("2d");

let audioContext: AudioContext | null = null;
let analyser: AnalyserNode | null = null;
let visualizerAnimationId: number | null = null;

const resizeCanvas = () => {
  canvasEl.width = canvasEl.clientWidth * window.devicePixelRatio;
  canvasEl.height = canvasEl.clientHeight * window.devicePixelRatio;
};
window.addEventListener("resize", resizeCanvas);
// Small delay ensures layout bounds are calculated before setting size
setTimeout(resizeCanvas, 0);

const stopVisualizer = () => {
  if (visualizerAnimationId) cancelAnimationFrame(visualizerAnimationId);
  visualizerAnimationId = null;
  if (canvasCtx) {
    canvasCtx.clearRect(0, 0, canvasEl.width, canvasEl.height);
  }
  if (audioContext) {
    audioContext.close().catch(() => {});
    audioContext = null;
  }
};

const startVisualizer = (stream: MediaStream) => {
  stopVisualizer();
  audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();
  analyser = audioContext.createAnalyser();
  analyser.fftSize = 256;
  
  const source = audioContext.createMediaStreamSource(stream);
  source.connect(analyser);
  
  const bufferLength = analyser.frequencyBinCount;
  const dataArray = new Uint8Array(bufferLength);
  
  const draw = () => {
    if (!canvasCtx) return;
    visualizerAnimationId = requestAnimationFrame(draw);
    
    analyser!.getByteTimeDomainData(dataArray);
    
    const { width, height } = canvasEl;
    canvasCtx.clearRect(0, 0, width, height);
    
    canvasCtx.lineWidth = 3 * window.devicePixelRatio;
    canvasCtx.lineCap = "round";
    
    const numStrings = 3;
    const colors = ["rgba(72, 187, 255, 0.9)", "rgba(156, 230, 255, 0.7)", "rgba(255, 255, 255, 0.4)"];
    
    for (let j = 0; j < numStrings; j++) {
      canvasCtx.beginPath();
      const sliceWidth = width / (bufferLength - 1);
      let x = 0;
      
      const phaseOffset = j * 0.5;
      const ampBase = 1 - (j * 0.2);
      
      for (let i = 0; i < bufferLength; i++) {
        const v = dataArray[i] / 128.0;
        const edgeDampen = Math.min(i / 15, (bufferLength - i) / 15, 1); 
        const audioVariance = (v - 1) * height * 0.4;
        
        // Enhance organic feel by mixing the audio variance with a continuous subtle sway
        const sway = Math.sin((i / bufferLength) * Math.PI * 2 + (Date.now() / 400) + phaseOffset) * 12;
        
        const yOffset = (audioVariance * ampBase + sway) * edgeDampen;
        const y = height / 2 + yOffset;
        
        if (i === 0) {
          canvasCtx.moveTo(x, y);
        } else {
          canvasCtx.lineTo(x, y);
        }
        x += sliceWidth;
      }
      
      canvasCtx.strokeStyle = colors[j];
      canvasCtx.stroke();
    }
  };
  draw();
};

const syncMicUi = () => {
  const isLive = !!recorder && recorder.state !== "inactive";
  micEl.classList.toggle("live", isLive);
  micEl.textContent = isLive ? "Stop Talking" : "Start Talking";
  if (!isLive) {
    if (transcriptEl.textContent === "Listening...") {
      updateModeUi();
    }
    stopVisualizer();
  }
};

const send = (payload: ClientMessage) => {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(payload));
    return;
  }
  outbox.push(payload);
};

const setStatus = (text: string) => {
  statusEl.textContent = text;
};

const updateModeUi = () => {
  const isPrompt = mode === "prompt";
  rawModeEl.classList.toggle("active", !isPrompt);
  promptModeEl.classList.toggle("active", isPrompt);
  rawModeEl.setAttribute("aria-selected", String(!isPrompt));
  promptModeEl.setAttribute("aria-selected", String(isPrompt));
  if (!recorder || recorder.state === "inactive") {
    transcriptEl.textContent = isPrompt
      ? "Prompt mode cleans messy speech into professional, structured instructions after recording stops."
      : "Raw Text mode keeps transcript output raw after recording stops.";
  }
};

const setMode = (nextMode: Mode) => {
  if (mode === nextMode) return;
  mode = nextMode;
  window.localStorage.setItem("airprompt-mode", mode);
  updateModeUi();
  send({ type: "mode", mode });
};

rawModeEl.addEventListener("click", () => setMode("raw"));
promptModeEl.addEventListener("click", () => setMode("prompt"));

const copyBtn = document.querySelector<HTMLButtonElement>("#copy-btn")!;
copyBtn.addEventListener("click", () => {
  const text = transcriptEl.textContent;
  if (text) {
    navigator.clipboard.writeText(text);
    const originalIcon = copyBtn.innerHTML;
    copyBtn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#4caf50" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>';
    setTimeout(() => {
      copyBtn.innerHTML = originalIcon;
    }, 2000);
  }
});

const toBase64 = (buffer: ArrayBuffer) => {
  let output = "";
  const bytes = new Uint8Array(buffer);
  for (let index = 0; index < bytes.length; index += 1) output += String.fromCharCode(bytes[index]);
  return btoa(output);
};

const stopHeartbeat = () => {
  if (pingTimer) { clearInterval(pingTimer); pingTimer = null; }
};

const startHeartbeat = () => {
  stopHeartbeat();
  lastPong = Date.now();
  pingTimer = setInterval(() => {
    if (!socket || socket.readyState !== WebSocket.OPEN) { stopHeartbeat(); return; }
    if (Date.now() - lastPong > 15000) {
      console.log("[air-prompt] heartbeat timeout, reconnecting");
      socket.close();
      return;
    }
    send({ type: "ping", ts: Date.now() });
  }, 5000);
};

const connect = () => {
  stopHeartbeat();
  socket = new WebSocket(wsBase);
  socket.addEventListener("open", () => {
    setStatus("Connected");
    lastPong = Date.now();
    send({ type: "pair", sessionId, device: "mobile" });
    while (outbox.length) {
      const message = outbox.shift();
      if (message) socket?.send(JSON.stringify(message));
    }
    startHeartbeat();
  });
  const thisSocket = socket;
  socket.addEventListener("close", () => {
    if (socket !== thisSocket) return;
    stopHeartbeat();
    macConnected = false;
    setStatus("Reconnecting");
    window.setTimeout(connect, 800);
  });
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(String(event.data)) as ServerMessage;
    if (message.type === "pong") { lastPong = Date.now(); return; }
    if (message.type === "paired") {
      macConnected = message.peerConnected;
      if (!message.peerConnected) {
        setStatus("Mac Disconnected");
        transcriptEl.textContent = "Mac app is disconnected. Please re-open it to continue.";
        micEl.disabled = true;
        micEl.style.opacity = "0.4";
        stopCapture();
      } else {
        setStatus("Connected");
        if (transcriptEl.textContent.includes("disconnected") || transcriptEl.textContent.includes("QR code")) {
          updateModeUi();
        }
        micEl.disabled = false;
        micEl.style.opacity = "1";
      }
    }
    if (message.type === "partial" || message.type === "final") transcriptEl.textContent = message.text;
    if (message.type === "state") setStatus(message.value);
    if (message.type === "error") setStatus(message.message);
  });
};

const ensureConnection = (): Promise<boolean> => {
  if (socket?.readyState === WebSocket.OPEN && macConnected) return Promise.resolve(true);
  reconnect();
  return new Promise((resolve) => {
    let attempts = 0;
    const check = setInterval(() => {
      attempts++;
      if (socket?.readyState === WebSocket.OPEN && macConnected) {
        clearInterval(check);
        resolve(true);
      } else if (attempts > 20) {
        clearInterval(check);
        resolve(false);
      }
    }, 200);
  });
};

const startCapture = async () => {
  if (recorder || isStarting) return;
  if (!window.isSecureContext) {
    setStatus("HTTPS required");
    transcriptEl.textContent = "Microphone access needs HTTPS on mobile browsers. Open this app over HTTPS or localhost.";
    return;
  }
  if (!navigator.mediaDevices?.getUserMedia) {
    setStatus("Mic unsupported");
    transcriptEl.textContent = "This browser does not expose microphone capture here.";
    return;
  }
  isStarting = true;
  setStatus("Connecting...");
  const alive = await ensureConnection();
  if (!alive) {
    setStatus("Mac Disconnected");
    transcriptEl.textContent = "Could not connect. Make sure the Mac app is running.";
    isStarting = false;
    syncMicUi();
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    recorder = new MediaRecorder(stream, { mimeType: "audio/webm;codecs=opus" });
    seq = 0;
    send({ type: "start", mode, mimeType: recorder.mimeType });
    recorder.addEventListener("dataavailable", async (event) => {
      if (!event.data.size) return;
      const buffer = await event.data.arrayBuffer();
      send({ type: "audio", seq: seq += 1, chunk: toBase64(buffer) });
    });
    recorder.addEventListener("stop", () => {
      send({ type: "stop" });
      stream.getTracks().forEach((track) => track.stop());
      recorder = null;
      syncMicUi();
    });
    recorder.start(180);
    startVisualizer(stream);
    setStatus("Listening");
    transcriptEl.textContent = "Listening...";
    syncMicUi();
  } catch (error) {
    setStatus("Mic blocked");
    transcriptEl.textContent =
      error instanceof Error ? error.message : "Microphone access failed.";
    syncMicUi();
  } finally {
    isStarting = false;
  }
};

const stopCapture = () => {
  if (recorder && recorder.state !== "inactive") recorder.stop();
};

micEl.addEventListener("contextmenu", (event) => event.preventDefault());
micEl.addEventListener("dragstart", (event) => event.preventDefault());

micEl.addEventListener("click", async () => {
  if (isStarting) return;
  if (recorder && recorder.state !== "inactive") {
    stopCapture();
    return;
  }
  await startCapture();
});

const reconnect = () => {
  stopHeartbeat();
  if (socket) {
    const old = socket;
    socket = null;
    try { old.close(); } catch {}
  }
  connect();
};

connect();
updateModeUi();
syncMicUi();

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") {
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      reconnect();
    } else {
      send({ type: "pair", sessionId, device: "mobile" });
    }
  }
});

if (!window.isSecureContext) {
  setStatus("HTTPS required");
}

const isStandalone = window.matchMedia("(display-mode: standalone)").matches
  || (navigator as any).standalone === true;
if (!isStandalone && window.isSecureContext) {
  const hint = document.querySelector<HTMLParagraphElement>("#install-hint");
  if (hint) hint.style.display = "block";
}

const subscribePush = async () => {
  if (!("serviceWorker" in navigator) || !window.isSecureContext) return;
  try {
    const reg = await navigator.serviceWorker.ready;
    if (Notification.permission === "default") {
      await Notification.requestPermission();
    }
    if (Notification.permission !== "granted") return;
    const vapidRes = await fetch("/push/vapid-key");
    const { key } = await vapidRes.json();
    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: key
    });
    await fetch("/push/subscribe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(sub.toJSON())
    });
  } catch {}
};

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/sw.js").then(() => subscribePush());
}
