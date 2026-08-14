import type { ProjectRow, AdrRow, ToneName } from "@/db/dexie";

// Injected at build time (VITE_META_FLAT_PATH, e.g. "-Users-alice--claude"). Unset,
// the meta-project simply gets no special tone rather than mis-tagging someone else's.
const META_FLAT_PATH = import.meta.env.VITE_META_FLAT_PATH ?? "";

type ProjectEntry = {
  kind: "project";
  slug: string;
  name: string;
  tone: ToneName;
  flat_path: string;
};

type AdrEntry = {
  kind: "adr";
  id: string;
  number: string;
  title: string;
  status: string;
  path: string;
  last_modified: string;
};

type IndexEntry = ProjectEntry | AdrEntry;

function toProjectRow(e: ProjectEntry): ProjectRow {
  return {
    slug: e.slug,
    name: e.name,
    scope: e.flat_path === META_FLAT_PATH ? "meta" : "project",
    flatPath: e.flat_path,
    tone: e.tone,
  };
}

function toAdrRow(e: AdrEntry): AdrRow {
  return {
    id: e.id,
    number: e.number,
    title: e.title,
    status: e.status,
    path: e.path,
    lastModified: e.last_modified,
  };
}

export async function loadIndex(): Promise<{
  projects: ProjectRow[];
  adrs: AdrRow[];
}> {
  const res = await fetch("/index.jsonl");
  if (!res.ok) {
    throw new Error(`loadIndex: HTTP ${res.status} ${res.statusText}`);
  }
  const text = await res.text();
  const projects: ProjectRow[] = [];
  const adrs: AdrRow[] = [];
  for (const line of text.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    const entry = JSON.parse(trimmed) as IndexEntry;
    if (entry.kind === "project") projects.push(toProjectRow(entry));
    else if (entry.kind === "adr") adrs.push(toAdrRow(entry));
  }
  return { projects, adrs };
}
