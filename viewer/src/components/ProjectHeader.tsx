import { useLocation } from "preact-iso";
import type { ProjectRow } from "@/db/dexie";

type Tab = "pulse" | "history" | "decisions";

const TABS: { key: Tab; label: string }[] = [
  { key: "pulse", label: "Pulse" },
  { key: "history", label: "History" },
  { key: "decisions", label: "Decisions" },
];

type TrustLevel = "Strict" | "Normal" | "Trusted" | "Full auto";

const TRUST_TINT: Record<TrustLevel, string> = {
  Strict: "var(--tone-amber)",
  Normal: "var(--text-muted)",
  Trusted: "var(--tone-green)",
  "Full auto": "var(--accent)",
};

export function ProjectHeader({
  project,
  tab,
}: {
  project: ProjectRow;
  tab: Tab;
}) {
  const location = useLocation();
  const trust: TrustLevel = "Normal";
  const base =
    project.scope === "meta" ? "/meta" : `/p/${project.slug}`;

  function go(next: Tab) {
    if (next !== tab) location.route(`${base}/${next}`);
  }

  return (
    <header class="project-header">
      <div class="project-header__top">
        <span class="project-header__glyph" aria-hidden="true">
          📁
        </span>
        <h1 class="project-header__name">{project.name}</h1>
        <span
          class="project-header__chip"
          style={{ color: TRUST_TINT[trust] }}
        >
          Trust: {trust} ▾
        </span>
        <span class="project-header__activity">Last activity 2h ago</span>
      </div>
      <nav class="project-header__tabs" aria-label="Sub-pages">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            class={`project-header__tab${
              t.key === tab ? " project-header__tab--active" : ""
            }`}
            onClick={() => go(t.key)}
          >
            {t.label}
          </button>
        ))}
      </nav>
    </header>
  );
}
