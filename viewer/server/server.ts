import { appendFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve, sep } from "node:path";
import { buildIndex } from "./indexer.ts";

const ROOT = resolve(import.meta.dir, "..", "..");
const DIST_DIR = resolve(import.meta.dir, "..", "dist");
const DECISIONS_DIR = join(ROOT, "decisions");
const PROJECTS_DIR = join(ROOT, "projects");
const NOTES_PATH = join(ROOT, "state", "NOTES.jsonl");

const PORT = Number(process.env.VIEWER_PORT ?? 4848);
const MAX_BODY_BYTES = 65536;

const SECURITY_HEADERS: Record<string, string> = {
  "Content-Security-Policy":
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "same-origin",
  "X-Frame-Options": "DENY",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
};

function withSecurity(res: Response): Response {
  for (const [k, v] of Object.entries(SECURITY_HEADERS)) res.headers.set(k, v);
  return res;
}

function notFound(): Response {
  return withSecurity(new Response("Not Found", { status: 404 }));
}

function methodNotAllowed(allow: string): Response {
  return withSecurity(
    new Response(null, { status: 405, headers: { Allow: allow } }),
  );
}

async function serveStatic(absPath: string, contentType: string): Promise<Response> {
  const file = Bun.file(absPath);
  if (!(await file.exists())) return notFound();
  return withSecurity(
    new Response(file, { headers: { "Content-Type": contentType } }),
  );
}

function serveIndexJsonl(): Response {
  const body = buildIndex(DECISIONS_DIR, PROJECTS_DIR, ROOT);
  return withSecurity(
    new Response(body, {
      headers: { "Content-Type": "application/x-ndjson; charset=utf-8" },
    }),
  );
}

async function handleNotesRead(url: URL): Promise<Response> {
  const rel = url.searchParams.get("path");
  if (!rel) return withSecurity(new Response("Missing path", { status: 400 }));
  const full = resolve(ROOT, rel);
  if (full !== DECISIONS_DIR && !full.startsWith(DECISIONS_DIR + sep)) {
    return notFound();
  }
  return serveStatic(full, "text/plain; charset=utf-8");
}

async function handleNotes(req: Request): Promise<Response> {
  const len = Number(req.headers.get("content-length") ?? "0");
  if (len > MAX_BODY_BYTES) {
    return withSecurity(new Response("Payload Too Large", { status: 413 }));
  }
  const body = await req.json();
  if (typeof body !== "object" || body === null) {
    return withSecurity(new Response("Invalid body", { status: 400 }));
  }
  const entry = JSON.stringify({ ts: new Date().toISOString(), ...body }) + "\n";
  mkdirSync(dirname(NOTES_PATH), { recursive: true });
  appendFileSync(NOTES_PATH, entry, { encoding: "utf8" });
  return withSecurity(new Response(null, { status: 200 }));
}

function handleTokenRotate(): Response {
  const token = crypto.randomUUID();
  return withSecurity(
    new Response(JSON.stringify({ token }), {
      headers: { "Content-Type": "application/json" },
    }),
  );
}

const ASSET_TYPES: Record<string, string> = {
  ".js": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".webmanifest": "application/manifest+json",
};

function assetContentType(path: string): string {
  const ext = path.slice(path.lastIndexOf("."));
  return ASSET_TYPES[ext] ?? "application/octet-stream";
}

async function serveAsset(path: string): Promise<Response> {
  const decoded = decodeURIComponent(path);
  const full = resolve(DIST_DIR, "." + decoded);
  if (full !== DIST_DIR && !full.startsWith(DIST_DIR + sep)) return notFound();
  return serveStatic(full, assetContentType(full));
}

async function route(req: Request, url: URL): Promise<Response> {
  const method = req.method === "HEAD" ? "GET" : req.method;
  const path = url.pathname;

  if (path === "/" || path === "/index.html") {
    if (method !== "GET") return methodNotAllowed("GET");
    return serveStatic(join(DIST_DIR, "index.html"), "text/html; charset=utf-8");
  }
  if (path === "/index.jsonl") {
    if (method !== "GET") return methodNotAllowed("GET");
    return serveIndexJsonl();
  }
  if (path === "/notes") {
    if (method === "GET") return handleNotesRead(url);
    if (method === "POST") return handleNotes(req);
    return methodNotAllowed("GET, POST");
  }
  if (path === "/token/rotate") {
    if (method !== "POST") return methodNotAllowed("POST");
    return handleTokenRotate();
  }
  if (path.startsWith("/assets/")) {
    if (method !== "GET") return methodNotAllowed("GET");
    return serveAsset(path);
  }
  if (method === "GET" && req.headers.get("accept")?.includes("text/html")) {
    return serveStatic(join(DIST_DIR, "index.html"), "text/html; charset=utf-8");
  }
  return notFound();
}

Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);
    const start = performance.now();
    let res: Response;
    try {
      res = await route(req, url);
    } catch (err) {
      const status = err instanceof SyntaxError ? 400 : 500;
      res = withSecurity(
        new Response(status === 400 ? "Bad Request" : "Internal Error", { status }),
      );
    }
    const ms = (performance.now() - start).toFixed(1);
    console.log(`${req.method} ${url.pathname} ${res.status} ${ms}ms`);
    return res;
  },
});

console.log(`viewer-server listening on :${PORT}`);
