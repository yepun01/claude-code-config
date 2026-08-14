import { useLocation } from "preact-iso";
import { Composer } from "@/components/Composer";
import { activeTeams, adrs } from "@/state/signals";
import type { ProjectRow, AdrRow } from "@/db/dexie";

function relTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.floor(diff / 60000);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.floor(h / 24)}d ago`;
}

function statusGlyph(status: string): string {
  if (status === "Accepted" || status === "Implemented") return "✓";
  if (status === "Superseded") return "⊝";
  return "●";
}

function topAdrs(rows: AdrRow[], n: number): AdrRow[] {
  return [...rows]
    .sort((a, b) => b.lastModified.localeCompare(a.lastModified))
    .slice(0, n);
}

export function Pulse({ project }: { project: ProjectRow }) {
  const location = useLocation();
  const teams = activeTeams.value;
  const top3 = topAdrs(adrs.value, 3);

  return (
    <div class="page">
      {teams.length > 0 && (
        <section class="page__section">
          <h2 class="page__section-title">Active teams</h2>
          <div class="pulse__teams">
            {teams.map((t, idx) => (
              <article
                key={t.id}
                class={`pulse__team${idx === 0 ? " pulse__team--featured" : ""}`}
              >
                <header class="pulse__team-head">
                  <span class="pulse__team-id">✦ {t.id}</span>
                  <span class="pulse__team-meta">
                    {t.members} members · {t.durationLabel}
                  </span>
                </header>
                <p class="pulse__team-intent">"{t.intent}"</p>
                <dl class="pulse__narration">
                  <div>
                    <dt>▶ Now</dt>
                    <dd>{t.now}</dd>
                  </div>
                  <div>
                    <dt>⏭ Next</dt>
                    <dd>{t.next}</dd>
                  </div>
                  <div>
                    <dt>⏸ Queue</dt>
                    <dd>{t.queue}</dd>
                  </div>
                </dl>
              </article>
            ))}
          </div>
        </section>
      )}

      <section class="page__section">
        <h2 class="page__section-title">Last sessions</h2>
        {project.scope === "meta" ? (
          <ul class="pulse__sessions">
            {top3.map((adr) => (
              <li key={adr.id}>
                <span class="pulse__session-glyph">{statusGlyph(adr.status)}</span>
                <span class="pulse__session-title">
                  ADR {adr.number} {adr.title}
                </span>
                <span class="pulse__session-time">{relTime(adr.lastModified)}</span>
              </li>
            ))}
          </ul>
        ) : (
          <p class="placeholder__lede">Aucune session locale.</p>
        )}
      </section>

      <section class="page__section">
        <h2 class="page__section-title">Active ADRs</h2>
        <div class="pulse__chips">
          {top3.map((adr) => (
            <button
              key={adr.id}
              type="button"
              class="chip chip--clickable"
              onClick={() => location.route(`/meta/decisions?focus=${adr.id}`)}
            >
              📎 ADR {adr.number} {adr.title}
            </button>
          ))}
        </div>
      </section>

      <Composer
        scopeLabel={`${project.name} LLM`}
        contextLabel={`${
          project.scope === "meta"
            ? "8 plugin ADRs · JOURNAL global"
            : "local .claude/decisions · scoped JOURNAL"
        }`}
      />
    </div>
  );
}
