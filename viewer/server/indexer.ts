import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import type { IndexEntry, ToneName } from "./types.ts";

const TONES: ToneName[] = [
  "neutral",
  "green",
  "teal",
  "pink",
  "lime",
  "orange",
  "violet",
  "amber",
];

// Claude Code flattens absolute paths into slugs, replacing separators and dots with
// dashes: /Users/alice/.claude -> -Users-alice--claude. Derived from $HOME so the
// viewer works on any machine.
const flattenPath = (p: string): string => p.replace(/[/.]/g, "-");

const META_FLAT_PATH = flattenPath(join(homedir(), ".claude"));
const HOME_FLAT_PATH = flattenPath(homedir());

const TITLE_RE = /^#\s+ADR\s+(\d+)\s+[—-]\s+(.+?)\s*$/m;
const STATUS_HEADING_RE = /^##\s+Status\s*$\n+([^\n]+)/m;
const STATUS_INLINE_RE = /\*\*Status\*\*\s*:\s*([^\n]+)/;

function toneFor(slug: string): ToneName {
  if (slug === META_FLAT_PATH) return "neutral";
  let h = 0;
  for (let i = 0; i < slug.length; i++) {
    h = (h * 31 + slug.charCodeAt(i)) | 0;
  }
  return TONES[Math.abs(h) % TONES.length]!;
}

function gitCommitTime(repoRoot: string, absPath: string): string | null {
  const r = Bun.spawnSync(
    ["git", "log", "-1", "--format=%cI", "--", absPath],
    { cwd: repoRoot, stdout: "pipe", stderr: "pipe" },
  );
  if (r.exitCode !== 0) return null;
  const out = new TextDecoder().decode(r.stdout).trim();
  return out.length > 0 ? out : null;
}

function fsModifiedTime(absPath: string): string {
  return new Date(statSync(absPath).mtimeMs).toISOString();
}

function parseAdr(absPath: string, fileName: string, repoRoot: string): IndexEntry {
  const content = readFileSync(absPath, "utf8");
  const titleMatch = content.match(TITLE_RE);
  const number = titleMatch?.[1] ?? fileName.slice(0, 4);
  const title = titleMatch?.[2] ?? fileName.replace(/\.md$/, "");

  const statusHeading = content.match(STATUS_HEADING_RE)?.[1]?.trim();
  const statusInline = content.match(STATUS_INLINE_RE)?.[1]?.trim();
  const status = statusHeading ?? statusInline ?? "Unknown";

  const last_modified = gitCommitTime(repoRoot, absPath) ?? fsModifiedTime(absPath);

  return {
    kind: "adr",
    id: fileName.replace(/\.md$/, ""),
    number,
    title,
    status,
    path: `decisions/${fileName}`,
    last_modified,
  };
}

function capitalize(s: string): string {
  return s.length > 0 ? s[0]!.toUpperCase() + s.slice(1) : s;
}

function deriveProjectName(flatPath: string): string {
  if (flatPath === META_FLAT_PATH) return "Plugin global";
  if (flatPath === HOME_FLAT_PATH) return "Home";

  const stripped = flatPath.startsWith(`${HOME_FLAT_PATH}-`)
    ? flatPath.slice(HOME_FLAT_PATH.length + 1)
    : flatPath;

  // Dot-prefixed dirs ("/.claude/viewer") flat-encode to a leading dash post-strip.
  if (stripped.startsWith("-claude")) {
    return stripped.replace(/^-claude/, ".claude").replace(/-/g, "/");
  }

  const parts = stripped.split("-").filter((p) => p.length > 0);
  if (parts.length === 0) return flatPath;

  if (parts[0] === "Library") {
    return `${parts[parts.length - 1]} (iCloud)`;
  }
  if (parts[0] === "conductor" && parts[1] === "workspaces") {
    const rest = parts.slice(2);
    return rest.length === 2 ? rest.join(" · ") : rest.join(" ");
  }
  if (parts[0] === "Epitech") {
    return parts.map(capitalize).join(" ");
  }
  if (parts[0] === "MyProjects" && parts.length > 1) {
    return parts.slice(1).join(" ");
  }
  if (parts[0] === "RobloxGames" && parts.length > 1) {
    return parts.slice(1).join(" ");
  }
  if (parts[0] === "TheCoach" && parts[1] === "claude") {
    return `TheCoach .claude/${parts.slice(2).join("/")}`;
  }

  return parts.join(" ");
}

function scanAdrs(decisionsDir: string, repoRoot: string): IndexEntry[] {
  const entries: IndexEntry[] = [];
  for (const name of readdirSync(decisionsDir).sort()) {
    if (!/^\d{4}.+\.md$/.test(name)) continue;
    entries.push(parseAdr(join(decisionsDir, name), name, repoRoot));
  }
  return entries;
}

function scanProjects(projectsDir: string): IndexEntry[] {
  const entries: IndexEntry[] = [];
  for (const name of readdirSync(projectsDir).sort()) {
    const abs = join(projectsDir, name);
    if (!statSync(abs).isDirectory()) continue;
    entries.push({
      kind: "project",
      slug: name,
      name: deriveProjectName(name),
      tone: toneFor(name),
      flat_path: name,
    });
  }
  return entries;
}

export function buildIndex(
  decisionsDir: string,
  projectsDir: string,
  repoRoot: string,
): string {
  const all = [...scanAdrs(decisionsDir, repoRoot), ...scanProjects(projectsDir)];
  return all.map((e) => JSON.stringify(e)).join("\n") + "\n";
}
