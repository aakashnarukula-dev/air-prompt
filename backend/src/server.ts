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
import { AuthCache } from "./auth-cache.js";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { existsSync } from "node:fs";
const __dirname = dirname(fileURLToPath(import.meta.url));
function findPwaDist(): string {
  if (process.env.PWA_DIST) return process.env.PWA_DIST;
  let dir = __dirname;
  for (let i = 0; i < 8; i++) {
    const candidate = join(dir, "mobile-pwa", "dist");
    if (existsSync(candidate)) return candidate;
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return join(__dirname, "..", "..", "mobile-pwa", "dist");
}
const PWA_DIST = findPwaDist();

async function main() {
  const config = loadConfig();
  const pool = getPool(config);
  const adminAuth = initFirebase(config);
  const verify = createVerifier(adminAuth);
  const cleaner = createCleaner({ apiKey: config.geminiApiKey, model: config.geminiModel });
  const sessions = new SessionStore({ ttlMs: config.sessionTtlMs });
  const rateLimit = new TokenBucket({ capacity: 60, refillPerSec: 1 });
  const authCache = new AuthCache();

  const httpServer = createServer(async (req, res) => {
    const origin = req.headers.origin;
    if (origin && config.allowedOrigins.includes(origin)) {
      res.setHeader("access-control-allow-origin", origin);
      res.setHeader("access-control-allow-credentials", "true");
    }
    res.setHeader("access-control-allow-methods", "GET, POST, OPTIONS");
    res.setHeader("access-control-allow-headers", "content-type");
    if (req.method === "OPTIONS") { res.end(); return; }

    const path = (req.url ?? "/").split("?")[0];
    if (path === "/auth/deposit" && req.method === "POST") {
      let body = "";
      req.on("data", (c) => { body += c; });
      req.on("end", () => {
        try {
          const { state, idToken } = JSON.parse(body);
          if (typeof state !== "string" || typeof idToken !== "string" || !state || !idToken) {
            res.statusCode = 400; res.end("bad"); return;
          }
          authCache.deposit(state, idToken);
          res.setHeader("content-type", "application/json");
          res.end(JSON.stringify({ ok: true }));
        } catch {
          res.statusCode = 400; res.end("bad");
        }
      });
      return;
    }
    if (path === "/auth/poll" && req.method === "GET") {
      const url = new URL(req.url ?? "/", "http://x");
      const state = url.searchParams.get("state") ?? "";
      const token = authCache.take(state);
      res.setHeader("content-type", "application/json");
      res.end(JSON.stringify({ idToken: token }));
      return;
    }
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
