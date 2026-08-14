import Dexie, { type EntityTable } from "dexie";

export type ToneName =
  | "neutral"
  | "green"
  | "teal"
  | "pink"
  | "lime"
  | "orange"
  | "violet"
  | "amber";

export type ProjectRow = {
  slug: string;
  name: string;
  scope: "meta" | "project";
  flatPath: string;
  tone: ToneName;
};

type SessionRow = {
  id: string;
  projectSlug: string;
  startedAt: string;
  summary: string;
};

export type AdrRow = {
  id: string;
  number: string;
  title: string;
  status: string;
  path: string;
  lastModified: string;
};

class ViewerDB extends Dexie {
  projects!: EntityTable<ProjectRow, "slug">;
  sessions!: EntityTable<SessionRow, "id">;
  adrs!: EntityTable<AdrRow, "id">;

  constructor() {
    super("atlas-viewer");
    this.version(1).stores({
      projects: "&slug, scope, name",
      sessions: "&id, projectSlug, startedAt",
      adrs: "&id, projectSlug, number, lastModified",
    });
    this.version(2).stores({
      adrs: "&id, number, lastModified",
    });
  }
}

export const db = new ViewerDB();
