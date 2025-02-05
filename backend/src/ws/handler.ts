import { randomUUID } from "node:crypto";
import type { WebSocket } from "ws";
import { PROTOCOL_VERSION, type ServerMessage, type Device } from "../../../shared/src/protocol.js";
import type { SessionStore, Session } from "../sessions.js";
import type { createVerifier, VerifiedUser } from "../auth.js";
import type { createCleaner } from "../gemini.js";
import type { Pool } from "../db.js";
import { upsertUser } from "../db.js";
import { recordUsage, estimateCost } from "../usage.js";
import type { TokenBucket } from "../rate-limit.js";
import { parseClientMessage } from "./messages.js";

interface ConnCtx {
  socket: WebSocket;
  user?: VerifiedUser;
  userDbId?: string;
  device?: Device;
  sessionId?: string;
}

export interface HandlerDeps {
  verify: ReturnType<typeof createVerifier>;
  cleaner: ReturnType<typeof createCleaner>;
  sessions: SessionStore;
  pool: Pool;
  rateLimit: TokenBucket;
  appBaseUrl: string;
}

export function attachHandler(socket: WebSocket, deps: HandlerDeps) {
  const ctx: ConnCtx = { socket };

  socket.on("message", async (raw: Buffer) => {
    const parsed = parseClientMessage(raw);
    if (!parsed.ok) {
      send(socket, { type: "error", protocolVersion: PROTOCOL_VERSION, code: parsed.code, message: parsed.message });
      return;
    }
    const msg = parsed.msg;

    if (msg.type === "hello") {
      try {
        ctx.user = await deps.verify(msg.idToken);
        const row = await upsertUser(deps.pool, ctx.user.uid, ctx.user.email, ctx.user.provider);
        ctx.userDbId = row.id;
        ctx.device = msg.device;
        if (msg.sessionId) {
          const s = msg.device === "mac"
            ? deps.sessions.attachMac(msg.sessionId, row.id, socket)
            : deps.sessions.attachMobile(msg.sessionId, row.id, socket);
          ctx.sessionId = s.id;
          send(socket, { type: "paired", protocolVersion: PROTOCOL_VERSION, sessionId: s.id, peerConnected: bothConnected(s) });
          notifyPeer(s, socket, { type: "paired", protocolVersion: PROTOCOL_VERSION, sessionId: s.id, peerConnected: true });
        }
      } catch (e: any) {
        send(socket, { type: "error", protocolVersion: PROTOCOL_VERSION, code: "unauthenticated", message: e.message });
        socket.close();
      }
      return;
    }

    if (!ctx.user || !ctx.userDbId) {
      send(socket, { type: "error", protocolVersion: PROTOCOL_VERSION, code: "unauthenticated", message: "say hello first" });
      return;
    }

    switch (msg.type) {
      case "create_session": {
        if (ctx.device !== "mac") {
          send(socket, { type: "error", protocolVersion: PROTOCOL_VERSION, code: "forbidden", message: "mac only" });
          return;
        }
        if (deps.sessions.countActive(ctx.userDbId) >= 10) {
          send(socket, { type: "error", protocolVersion: PROTOCOL_VERSION, code: "rate_limit", message: "too many sessions" });
          return;
        }
        const s = deps.sessions.create(ctx.userDbId);
        deps.sessions.attachMac(s.id, ctx.userDbId, socket);
        ctx.sessionId = s.id;
        const joinUrl = `${deps.appBaseUrl}/?session=${s.id}`;
        send(socket, { type: "session_created", protocolVersion: PROTOCOL_VERSION, sessionId: s.id, joinUrl });
        break;
      }
      case "join_session": {
        if (ctx.device !== "mobile") {
          send(socket, { type: "error", protocolVersion: PROTOCOL_VERSION, code: "forbidden", message: "mobile only" });
          return;
        }
        try {
          const s = deps.sessions.attachMobile(msg.sessionId, ctx.userDbId, socket);
          ctx.sessionId = s.id;
          send(socket, { type: "paired", protocolVersion: PROTOCOL_VERSION, sessionId: s.id, peerConnected: Boolean(s.mac) });
          if (s.mac) notifyPeer(s, socket, { type: "paired", protocolVersion: PROTOCOL_VERSION, sessionId: s.id, peerConnected: true });
        } catch (e: any) {
          const code = String(e.message).startsWith("forbidden") ? "forbidden" : "not_found";
          send(socket, { type: "error", protocolVersion: PROTOCOL_VERSION, code, message: e.message });
        }
        break;
      }
      case "transcript": {
        if (!ctx.sessionId) return;
        if (!deps.rateLimit.take(ctx.userDbId)) {
          send(socket, { type: "error", protocolVersion: PROTOCOL_VERSION, code: "rate_limit", message: "too many requests" });
          return;
        }
        const s = deps.sessions.find(ctx.sessionId);
        if (!s) return;
        deps.sessions.touch(s);
        let outText = msg.text;
        let fallback = false;
        let tokensIn = 0, tokensOut = 0;
        if (msg.mode === "prompt") {
          const r = await deps.cleaner(msg.text);
          outText = r.text; fallback = r.fallback;
          tokensIn = r.tokensIn; tokensOut = r.tokensOut;
        }
        const deliveryId = randomUUID();
        const final: ServerMessage = { type: "final", protocolVersion: PROTOCOL_VERSION, text: outText, mode: msg.mode, deliveryId, fallback };
        if (s.mac) send(s.mac, final);
        await recordUsage(deps.pool, {
          userId: ctx.userDbId,
          mode: msg.mode,
          inputChars: msg.text.length,
          outputChars: outText.length,
          tokensIn, tokensOut,
          costUsd: estimateCost(tokensIn, tokensOut),
        });
        break;
      }
      case "mode": {
        if (!ctx.sessionId) return;
        const s = deps.sessions.find(ctx.sessionId);
        if (s) s.mode = msg.mode;
        break;
      }
      case "ack":
        break;
      case "ping":
        send(socket, { type: "pong", protocolVersion: PROTOCOL_VERSION, ts: msg.ts });
        break;
    }
  });

  socket.on("close", () => {
    deps.sessions.detach(socket);
  });
}

function send(socket: WebSocket, msg: ServerMessage) {
  if (socket.readyState !== socket.OPEN) return;
  socket.send(JSON.stringify(msg));
}

function bothConnected(s: Session) {
  return Boolean(s.mac && s.mobile);
}

function notifyPeer(s: Session, sender: WebSocket, msg: ServerMessage) {
  const peer = s.mac === sender ? s.mobile : s.mac;
  if (peer) send(peer, msg);
}
