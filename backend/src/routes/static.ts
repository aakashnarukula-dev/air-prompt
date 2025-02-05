import { readFile, stat } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import type { IncomingMessage, ServerResponse } from "node:http";

const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript",
  ".css": "text/css",
  ".svg": "image/svg+xml",
  ".json": "application/json",
  ".webmanifest": "application/manifest+json",
  ".ico": "image/x-icon",
  ".png": "image/png",
  ".jpg": "image/jpeg",
};

export async function serveStatic(req: IncomingMessage, res: ServerResponse, rootDir: string) {
  const url = req.url ?? "/";
  const rel = url.split("?")[0] === "/" ? "/index.html" : url.split("?")[0];
  const full = resolve(join(rootDir, rel));
  if (!full.startsWith(resolve(rootDir))) {
    res.statusCode = 403; res.end("forbidden"); return;
  }
  try {
    const s = await stat(full);
    const path = s.isDirectory() ? join(full, "index.html") : full;
    const data = await readFile(path);
    res.setHeader("content-type", MIME[extname(path)] ?? "application/octet-stream");
    res.setHeader("cache-control", "public, max-age=300");
    res.end(data);
  } catch {
    try {
      const data = await readFile(join(rootDir, "index.html"));
      res.setHeader("content-type", "text/html; charset=utf-8");
      res.end(data);
    } catch {
      res.statusCode = 404; res.end("not found");
    }
  }
}
