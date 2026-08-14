import { Composer } from "@/components/Composer";
import type { ProjectRow } from "@/db/dexie";

export function History({ project }: { project: ProjectRow }) {
  return (
    <div class="page">
      <section class="page__section">
        <h2 class="page__section-title">Saga Thread</h2>
        <div class="placeholder">
          <p class="placeholder__lede">
            Saga Thread filtré au scope projet — bientôt.
          </p>
          <p class="placeholder__meta">3 sessions ce mois</p>
        </div>
      </section>

      <Composer
        scopeLabel={`${project.name} LLM`}
        contextLabel="JOURNAL scoped to this project"
      />
    </div>
  );
}
