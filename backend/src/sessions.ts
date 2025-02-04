import { randomUUID } from "node:crypto";
import type { WebSocket } from "ws";

export interface Session {
  id: string;
  ownerUserId: string;
  mac?: WebSocket;
  mobile?: WebSocket;
  expiresAt: number;
  mode: "raw" | "prompt";
}

export interface SessionStoreOptions {
  ttlMs: number;
}

export class SessionStore {
  private map = new Map<string, Session>();
  constructor(private opts: SessionStoreOptions) {}

  create(ownerUserId: string): Session {
    const id = randomUUID();
    const session: Session = {
      id,
      ownerUserId,
      expiresAt: Date.now() + this.opts.ttlMs,
      mode: "raw",
    };
    this.map.set(id, session);
    return session;
  }

  find(id: string): Session | undefined {
    return this.map.get(id);
  }

  attachMac(id: string, userId: string, ws: WebSocket): Session {
    const s = this.assertOwner(id, userId);
    s.mac = ws;
    this.touch(s);
    return s;
  }

  attachMobile(id: string, userId: string, ws: WebSocket): Session {
    const s = this.assertOwner(id, userId);
    s.mobile = ws;
    this.touch(s);
    return s;
  }

  touch(s: Session) {
    s.expiresAt = Date.now() + this.opts.ttlMs;
  }

  detach(ws: WebSocket) {
    for (const s of this.map.values()) {
      if (s.mac === ws) s.mac = undefined;
      if (s.mobile === ws) s.mobile = undefined;
    }
  }

  countActive(ownerUserId: string): number {
    let count = 0;
    const now = Date.now();
    for (const s of this.map.values()) {
      if (s.ownerUserId === ownerUserId && s.expiresAt > now) count++;
    }
    return count;
  }

  reap() {
    const now = Date.now();
    for (const [id, s] of this.map.entries()) {
      if (s.expiresAt <= now) this.map.delete(id);
    }
  }

  private assertOwner(id: string, userId: string): Session {
    const s = this.map.get(id);
    if (!s) throw new Error("not_found: session not found");
    if (s.ownerUserId !== userId) throw new Error("forbidden: session owner mismatch");
    return s;
  }
}
