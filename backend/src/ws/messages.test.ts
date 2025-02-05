import { describe, it, expect } from "vitest";
import { parseClientMessage } from "./messages.js";

describe("parseClientMessage", () => {
  it("rejects malformed JSON", () => {
    expect(parseClientMessage("{not json")).toMatchObject({ ok: false });
  });

  it("rejects missing protocolVersion", () => {
    const r = parseClientMessage(JSON.stringify({ type: "ping", ts: 1 }));
    expect(r).toMatchObject({ ok: false, code: "bad_request" });
  });

  it("rejects wrong protocolVersion", () => {
    const r = parseClientMessage(JSON.stringify({ type: "ping", protocolVersion: "1", ts: 1 }));
    expect(r).toMatchObject({ ok: false, code: "protocol_version" });
  });

  it("accepts valid v2 message", () => {
    const r = parseClientMessage(JSON.stringify({ type: "ping", protocolVersion: "2", ts: 1 }));
    expect(r).toMatchObject({ ok: true });
  });
});
