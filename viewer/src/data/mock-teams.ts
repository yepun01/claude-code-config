export type ActiveTeam = {
  id: string;
  members: number;
  durationLabel: string;
  intent: string;
  now: string;
  next: string;
  queue: string;
};

export const ACTIVE_TEAMS: ActiveTeam[] = [
  {
    id: "atlas-redesign-1777546871",
    members: 3,
    durationLabel: "38min",
    intent: "Repenser visuellement le viewer claude-atlas",
    now: "designer reading components/Sidebar.tsx",
    next: "scan tone-color collisions across 22 entries",
    queue: "2 decisions pending",
  },
  {
    id: "atp-exec-section1",
    members: 2,
    durationLabel: "2h12",
    intent: "Audit forensique manuel Section 1 ATP",
    now: "deep-analyzer cross-referencing evidence markers",
    next: "draft section-1 verdict summary",
    queue: "4 decisions pending (1 risky)",
  },
  {
    id: "auto-skill-split-20260430",
    members: 2,
    durationLabel: "1h47",
    intent: "Step 8 prerequisite: split SKILL.md",
    now: "developer extracting team-pipelines.md",
    next: "validate-arch.sh dry-run on extracted file",
    queue: "1 decision pending",
  },
];
