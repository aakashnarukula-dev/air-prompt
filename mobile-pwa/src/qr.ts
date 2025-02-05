export function extractSessionId(input: string): string | null {
  try {
    const u = new URL(input);
    return u.searchParams.get("session");
  } catch {
    return null;
  }
}
