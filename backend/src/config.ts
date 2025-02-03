export interface AppConfig {
  port: number;
  appBaseUrl: string;
  firebaseProjectId: string;
  firebaseClientEmail: string;
  firebasePrivateKey: string;
  geminiApiKey: string;
  geminiModel: string;
  databaseUrl: string;
  sessionTtlMs: number;
  allowedOrigins: string[];
}

const REQUIRED = [
  "FIREBASE_PROJECT_ID",
  "FIREBASE_CLIENT_EMAIL",
  "FIREBASE_PRIVATE_KEY",
  "GEMINI_API_KEY",
  "DATABASE_URL",
] as const;

export function loadConfig(env: Record<string, string | undefined> = process.env): AppConfig {
  for (const key of REQUIRED) {
    if (!env[key]) throw new Error(`Missing required env: ${key}`);
  }
  return {
    port: Number(env.PORT ?? 8787),
    appBaseUrl: env.APP_BASE_URL ?? "http://localhost:5173",
    firebaseProjectId: env.FIREBASE_PROJECT_ID!,
    firebaseClientEmail: env.FIREBASE_CLIENT_EMAIL!,
    firebasePrivateKey: env.FIREBASE_PRIVATE_KEY!.replace(/\\n/g, "\n"),
    geminiApiKey: env.GEMINI_API_KEY!,
    geminiModel: env.GEMINI_MODEL ?? "gemini-2.5-flash-lite",
    databaseUrl: env.DATABASE_URL!,
    sessionTtlMs: Number(env.SESSION_TTL_MS ?? 30 * 60 * 1000),
    allowedOrigins: (env.ALLOWED_ORIGINS ?? "http://localhost:5173,http://localhost:8787").split(","),
  };
}
