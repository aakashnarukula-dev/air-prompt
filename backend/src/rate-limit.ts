export interface TokenBucketOptions {
  capacity: number;
  refillPerSec: number;
}

interface Bucket {
  tokens: number;
  lastRefill: number;
}

export class TokenBucket {
  private buckets = new Map<string, Bucket>();
  constructor(private opts: TokenBucketOptions) {}

  take(key: string, cost = 1): boolean {
    const now = Date.now();
    let b = this.buckets.get(key);
    if (!b) {
      b = { tokens: this.opts.capacity, lastRefill: now };
      this.buckets.set(key, b);
    }
    const elapsedSec = (now - b.lastRefill) / 1000;
    b.tokens = Math.min(this.opts.capacity, b.tokens + elapsedSec * this.opts.refillPerSec);
    b.lastRefill = now;
    if (b.tokens >= cost) {
      b.tokens -= cost;
      return true;
    }
    return false;
  }
}
