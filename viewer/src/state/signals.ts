import { signal } from "@preact/signals";
import { ACTIVE_TEAMS, type ActiveTeam } from "@/data/mock-teams";
import type { ProjectRow, AdrRow } from "@/db/dexie";

export type DataLoadState = "idle" | "loading" | "ready" | "error";

export const sidebarSearch = signal<string>("");
export const drawerOpen = signal<boolean>(false);
export const activeTeams = signal<ActiveTeam[]>(ACTIVE_TEAMS);

export const projects = signal<ProjectRow[]>([]);
export const adrs = signal<AdrRow[]>([]);
export const dataLoadState = signal<DataLoadState>("idle");
