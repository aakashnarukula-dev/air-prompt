import type { IncomingMessage, ServerResponse } from "node:http";
import type { Pool } from "../db.js";

export async function handleHealth(_req: IncomingMessage, res: ServerResponse, pool: Pool) {
  let db = "ok";
  try { await pool.query("SELECT 1"); } catch { db = "down"; }
  res.setHeader("content-type", "application/json");
  res.end(JSON.stringify({ ok: db === "ok", db, uptime: process.uptime() }));
}
