import { useMemo } from "preact/hooks";
import { useLocation } from "preact-iso";
import type { ProjectRow } from "@/db/dexie";
import {
  sidebarSearch,
  drawerOpen,
  projects,
  dataLoadState,
} from "@/state/signals";

function ProjectListRow({
  project,
  active,
  onPick,
}: {
  project: ProjectRow;
  active: boolean;
  onPick: () => void;
}) {
  return (
    <button
      type="button"
      class={`sidebar__row${active ? " sidebar__row--active" : ""}`}
      onClick={onPick}
    >
      <span
        class="sidebar__dot"
        style={{ background: `var(--tone-${project.tone})` }}
        aria-hidden="true"
      />
      <span class="sidebar__row-name">{project.name}</span>
    </button>
  );
}

export function Sidebar({ activeSlug }: { activeSlug: string }) {
  const location = useLocation();
  const search = sidebarSearch.value.trim().toLowerCase();
  const all = projects.value;
  const status = dataLoadState.value;

  const { meta, others } = useMemo(() => {
    const filtered = search
      ? all.filter((p) => p.name.toLowerCase().includes(search))
      : all;
    return {
      meta: filtered.filter((p) => p.scope === "meta"),
      others: filtered.filter((p) => p.scope === "project"),
    };
  }, [search, all]);

  function pick(p: ProjectRow) {
    drawerOpen.value = false;
    const m = location.url.match(
      /^\/(?:meta|p\/[^/]+)\/(pulse|history|decisions)/,
    );
    const tab = m?.[1] ?? "pulse";
    const base = p.scope === "meta" ? "/meta" : `/p/${p.slug}`;
    location.route(`${base}/${tab}`);
  }

  return (
    <aside class="sidebar app-shell__sidebar">
      <div class="sidebar__header">
        <span class="sidebar__title">Atlas viewer</span>
      </div>
      <div class="sidebar__search">
        <input
          type="search"
          placeholder="Search projects…"
          value={sidebarSearch.value}
          onInput={(e) => {
            sidebarSearch.value = (e.currentTarget as HTMLInputElement).value;
          }}
        />
      </div>
      <nav class="sidebar__nav" aria-label="Projects">
        {status === "loading" && all.length === 0 && (
          <p class="sidebar__empty">Loading…</p>
        )}
        {status === "error" && (
          <p class="sidebar__empty">Failed to load index.</p>
        )}
        {meta.length > 0 && (
          <section class="sidebar__section">
            <h2 class="sidebar__section-title">Méta</h2>
            {meta.map((p) => (
              <ProjectListRow
                key={p.slug}
                project={p}
                active={p.slug === activeSlug}
                onPick={() => pick(p)}
              />
            ))}
          </section>
        )}
        {others.length > 0 && (
          <section class="sidebar__section">
            <h2 class="sidebar__section-title">Projets</h2>
            {others.map((p) => (
              <ProjectListRow
                key={p.slug}
                project={p}
                active={p.slug === activeSlug}
                onPick={() => pick(p)}
              />
            ))}
          </section>
        )}
        {status === "ready" && meta.length === 0 && others.length === 0 && (
          <p class="sidebar__empty">No project matches "{search}".</p>
        )}
      </nav>
    </aside>
  );
}
