import { describe, it, expect } from "vitest";
import { TokenBucket } from "./rate-limit.js";

describe("TokenBucket", () => {
  it("allows up to capacity", () => {
    const b = new TokenBucket({ capacity: 3, refillPerSec: 0 });
    expect(b.take("u")).toBe(true);
    expect(b.take("u")).toBe(true);
    expect(b.take("u")).toBe(true);
    expect(b.take("u")).toBe(false);
  });

  it("refills over time", async () => {
    const b = new TokenBucket({ capacity: 2, refillPerSec: 10 });
    b.take("u"); b.take("u");
    expect(b.take("u")).toBe(false);
    await new Promise((r) => setTimeout(r, 150));
    expect(b.take("u")).toBe(true);
  });

  it("isolates per key", () => {
    const b = new TokenBucket({ capacity: 1, refillPerSec: 0 });
    expect(b.take("a")).toBe(true);
    expect(b.take("b")).toBe(true);
    expect(b.take("a")).toBe(false);
  });
});
