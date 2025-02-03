import { describe, it, expect } from "vitest";
import { loadConfig } from "./config.js";

describe("loadConfig", () => {
  it("throws if required env missing", () => {
    expect(() => loadConfig({})).toThrow(/FIREBASE_PROJECT_ID/);
  });

  it("returns config with defaults", () => {
    const cfg = loadConfig({
      FIREBASE_PROJECT_ID: "proj",
      FIREBASE_CLIENT_EMAIL: "x@y.z",
      FIREBASE_PRIVATE_KEY: "pk",
      GEMINI_API_KEY: "gk",
      DATABASE_URL: "postgres://x",
    });
    expect(cfg.port).toBe(8787);
    expect(cfg.appBaseUrl).toBe("http://localhost:5173");
    expect(cfg.geminiModel).toBe("gemini-2.5-flash-lite");
  });
});
