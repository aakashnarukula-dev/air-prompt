import { describe, it, expect, vi } from "vitest";
import { createVerifier, type VerifiedUser } from "./auth.js";

describe("createVerifier", () => {
  it("verifies a valid token", async () => {
    const fakeAdmin = {
      verifyIdToken: vi.fn().mockResolvedValue({
        uid: "abc",
        email: "a@b.c",
        firebase: { sign_in_provider: "google.com" },
      }),
    } as any;
    const verify = createVerifier(fakeAdmin);
    const user = await verify("token123");
    expect(user).toEqual<VerifiedUser>({
      uid: "abc",
      email: "a@b.c",
      provider: "google",
    });
  });

  it("throws on invalid token", async () => {
    const fakeAdmin = {
      verifyIdToken: vi.fn().mockRejectedValue(new Error("bad token")),
    } as any;
    const verify = createVerifier(fakeAdmin);
    await expect(verify("bad")).rejects.toThrow();
  });

  it("maps provider correctly", async () => {
    const fakeAdmin = {
      verifyIdToken: vi.fn().mockResolvedValue({
        uid: "u2",
        email: "e@f.g",
        firebase: { sign_in_provider: "apple.com" },
      }),
    } as any;
    const verify = createVerifier(fakeAdmin);
    const user = await verify("t");
    expect(user.provider).toBe("apple");
  });
});
