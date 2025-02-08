interface Entry {
  idToken: string;
  createdAt: number;
}

const TTL_MS = 5 * 60 * 1000;
const MAX_ENTRIES = 500;

export class AuthCache {
  private map = new Map<string, Entry>();

  deposit(state: string, idToken: string) {
    this.reap();
    if (this.map.size >= MAX_ENTRIES) return;
    this.map.set(state, { idToken, createdAt: Date.now() });
  }

  take(state: string): string | null {
    const e = this.map.get(state);
    if (!e) return null;
    this.map.delete(state);
    if (Date.now() - e.createdAt > TTL_MS) return null;
    return e.idToken;
  }

  reap() {
    const now = Date.now();
    for (const [k, v] of this.map.entries()) {
      if (now - v.createdAt > TTL_MS) this.map.delete(k);
    }
  }
}
