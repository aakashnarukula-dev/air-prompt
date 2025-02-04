import pg from "pg";
import type { AppConfig } from "./config.js";

const { Pool } = pg;
export type Pool = InstanceType<typeof Pool>;

let pool: Pool | null = null;

export function getPool(config: AppConfig): Pool {
  if (pool) return pool;
  pool = new Pool({
    connectionString: config.databaseUrl,
    max: 10,
    idleTimeoutMillis: 30_000,
  });
  return pool;
}

export async function upsertUser(
  pool: Pool,
  firebaseUid: string,
  email: string,
  provider: string,
): Promise<{ id: string; plan_tier: string }> {
  const sql = `
    INSERT INTO users (firebase_uid, email, provider, last_seen_at)
    VALUES ($1, $2, $3, now())
    ON CONFLICT (firebase_uid)
    DO UPDATE SET email = EXCLUDED.email, last_seen_at = now()
    RETURNING id, plan_tier
  `;
  const res = await pool.query(sql, [firebaseUid, email, provider]);
  return res.rows[0];
}
