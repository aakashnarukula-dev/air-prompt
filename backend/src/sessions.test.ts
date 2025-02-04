import { describe, it, expect, beforeEach } from "vitest";
import { SessionStore } from "./sessions.js";

describe("SessionStore", () => {
  let store: SessionStore;
  beforeEach(() => {
    store = new SessionStore({ ttlMs: 60_000 });
  });

  it("creates a session owned by user", () => {
    const s = store.create("user1");
    expect(s.id).toBeTruthy();
    expect(s.ownerUserId).toBe("user1");
  });

  it("find returns created session", () => {
    const s = store.create("user1");
    expect(store.find(s.id)?.ownerUserId).toBe("user1");
  });

  it("attachMac rejects if wrong owner", () => {
    const s = store.create("user1");
    expect(() => store.attachMac(s.id, "user2", {} as any)).toThrow(/forbidden/);
  });

  it("attachMobile rejects if wrong owner", () => {
    const s = store.create("user1");
    expect(() => store.attachMobile(s.id, "user2", {} as any)).toThrow(/forbidden/);
  });

  it("pair succeeds when both same owner", () => {
    const s = store.create("user1");
    store.attachMac(s.id, "user1", { id: "mac" } as any);
    store.attachMobile(s.id, "user1", { id: "mob" } as any);
    expect(store.find(s.id)?.mac).toBeTruthy();
    expect(store.find(s.id)?.mobile).toBeTruthy();
  });

  it("expired sessions removed by reap", () => {
    const short = new SessionStore({ ttlMs: 1 });
    const s = short.create("u");
    (short.find(s.id) as any).expiresAt = Date.now() - 1000;
    short.reap();
    expect(short.find(s.id)).toBeUndefined();
  });

  it("countActive returns only active sessions per owner", () => {
    store.create("user1");
    store.create("user1");
    store.create("user2");
    expect(store.countActive("user1")).toBe(2);
    expect(store.countActive("user2")).toBe(1);
  });
});
