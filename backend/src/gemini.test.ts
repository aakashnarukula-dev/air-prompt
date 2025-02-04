import { describe, it, expect, vi } from "vitest";
import { createCleaner } from "./gemini.js";

describe("createCleaner", () => {
  it("returns cleaned text on success", async () => {
    const fetchFn = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        candidates: [{ content: { parts: [{ text: "cleaned text" }] } }],
        usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5 },
      }),
    });
    const cleaner = createCleaner({
      apiKey: "k",
      model: "m",
      fetch: fetchFn as any,
    });
    const result = await cleaner("raw text");
    expect(result.text).toBe("cleaned text");
    expect(result.fallback).toBe(false);
    expect(result.tokensIn).toBe(10);
    expect(result.tokensOut).toBe(5);
  });

  it("falls back on http error", async () => {
    const fetchFn = vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
      text: async () => "boom",
    });
    const cleaner = createCleaner({
      apiKey: "k",
      model: "m",
      fetch: fetchFn as any,
    });
    const result = await cleaner("raw text");
    expect(result.text).toBe("raw text");
    expect(result.fallback).toBe(true);
  });

  it("falls back on network error", async () => {
    const fetchFn = vi.fn().mockRejectedValue(new Error("net"));
    const cleaner = createCleaner({
      apiKey: "k",
      model: "m",
      fetch: fetchFn as any,
    });
    const result = await cleaner("raw text");
    expect(result.fallback).toBe(true);
  });
});
