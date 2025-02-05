import type { Pool } from "./db.js";

export interface UsageEvent {
  userId: string;
  mode: "raw" | "prompt";
  inputChars: number;
  outputChars: number;
  tokensIn?: number;
  tokensOut?: number;
  costUsd?: number;
}

const GEMINI_FLASH_LITE_INPUT_PER_M = 0.1;
const GEMINI_FLASH_LITE_OUTPUT_PER_M = 0.4;

export function estimateCost(tokensIn: number, tokensOut: number): number {
  return (tokensIn / 1_000_000) * GEMINI_FLASH_LITE_INPUT_PER_M
    + (tokensOut / 1_000_000) * GEMINI_FLASH_LITE_OUTPUT_PER_M;
}

export async function recordUsage(pool: Pool, evt: UsageEvent): Promise<void> {
  const sql = `
    INSERT INTO usage_events (user_id, mode, input_chars, output_chars, llm_tokens_in, llm_tokens_out, llm_cost_usd)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
  `;
  await pool.query(sql, [
    evt.userId,
    evt.mode,
    evt.inputChars,
    evt.outputChars,
    evt.tokensIn ?? null,
    evt.tokensOut ?? null,
    evt.costUsd ?? null,
  ]);
}
