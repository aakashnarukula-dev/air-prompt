import "dotenv/config";
import { createServer } from "node:http";
import { WebSocketServer } from "ws";
import { loadConfig } from "./config.js";
import { getPool } from "./db.js";
import { initFirebase, createVerifier } from "./auth.js";
import { createCleaner } from "./gemini.js";
import { SessionStore } from "./sessions.js";
import { TokenBucket } from "./rate-limit.js";
import { attachHandler } from "./ws/handler.js";
import { handleHealth } from "./routes/health.js";
import { serveStatic } from "./routes/static.js";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PWA_DIST = join(__dirname, "..", "..", "mobile-pwa", "dist");

async function main() {
  const config = loadConfig();
  const pool = getPool(config);
  const adminAuth = initFirebase(config);
  const verify = createVerifier(adminAuth);
  const cleaner = createCleaner({ apiKey: config.geminiApiKey, model: config.geminiModel });
  const sessions = new SessionStore({ ttlMs: config.sessionTtlMs });
  const rateLimit = new TokenBucket({ capacity: 60, refillPerSec: 1 });

  const httpServer = createServer(async (req, res) => {
    const origin = req.headers.origin;
    if (origin && config.allowedOrigins.includes(origin)) {
      res.setHeader("access-control-allow-origin", origin);
      res.setHeader("access-control-allow-credentials", "true");
    }
    if (req.method === "OPTIONS") { res.end(); return; }

    const path = (req.url ?? "/").split("?")[0];
    if (path === "/health") return handleHealth(req, res, pool);
    return serveStatic(req, res, PWA_DIST);
  });

  const wss = new WebSocketServer({ noServer: true });

  httpServer.on("upgrade", (req, sock, head) => {
    if ((req.url ?? "").split("?")[0] !== "/ws") { sock.destroy(); return; }
    const origin = req.headers.origin;
    if (origin && !config.allowedOrigins.includes(origin)) {
      sock.write("HTTP/1.1 403 Forbidden\r\n\r\n"); sock.destroy(); return;
    }
    wss.handleUpgrade(req, sock, head, (ws) => {
      attachHandler(ws as any, { verify, cleaner, sessions, pool, rateLimit, appBaseUrl: config.appBaseUrl });
    });
  });

  setInterval(() => sessions.reap(), 30_000).unref();

  httpServer.listen(config.port, () => {
    console.log(JSON.stringify({ level: "info", msg: "backend listening", port: config.port }));
  });
}

main().catch((err) => {
  console.error(JSON.stringify({ level: "fatal", err: String(err) }));
  process.exit(1);
});
