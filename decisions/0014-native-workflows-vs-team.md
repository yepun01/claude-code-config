# ADR 0014 — Native dynamic workflows vs /team orchestration

Status: Proposed — resolved & superseded by ADR 0017 (2026-06-08, Option C hybrid)
Date: 2026-05-31
Supersedes: —
Superseded by: ADR 0017 (2026-06-08)

## Context

Claude Code 2.1.154 ships **dynamic workflows** (`/workflows`): the harness orchestrates tens-to-hundreds of subagents in the background from a deterministic JS script, with native fan-out (`parallel`/`pipeline`), token budgets, structured-output schemas, worktree isolation, and resume-from-journal.

This overlaps heavily with the plugin's `/team` skill, which hand-rolls the same capability via `TeamCreate` + `Agent(mode=bypassPermissions)` in tmux panes, LLM-reactive polling (ADR 0001), and a 19-rule coordination protocol. Observed this session: the tmux path is operationally fragile (path collisions, TeamDelete refusals, zombie panes, subprocess permission failures).

The question — *should `/team` be rebuilt on top of native workflows, kept as-is, or become a thin router that emits a workflow?* — is a core-architecture decision that would reshape or replace the plugin's most-used skill. It must not be answered by a blind implementation pass.

## Decision

**Deferred.** This run (`/team --ceremony` 2026-05-31) explicitly carves this item OUT of the implementation batch. No code touches `/team` until a dedicated evaluation is done.

The evaluation is to run via `/discuss` and conclude in a new ADR (Accepted/Rejected, superseding this Proposed one). Axes to evaluate:

- **Coverage parity**: do native workflows cover ceremony (Interview/ROI/Criteria), challenge-loops, ADR preservation, the verdict/status protocols, evidence markers?
- **Wrap vs replace vs coexist**: `/team` as a router emitting a `Workflow({script})` · full rewrite · keep both for different surfaces.
- **Migration cost**: 19 rules + 6 docs + ADR 0001 comms pattern + agents' common block.
- **Loss surface**: what hand-rolled affordances (tmux observability, SendMessage delivery, per-teammate model) have no native equivalent.

## Consequences

- **Positive**: the most disruptive 2026-06 radar item is parked formally instead of being built blind; `/team` stays intact and usable.
- **Positive**: forces an evidence-based comparison (canary native workflows against a real `/team` task) before committing migration effort.
- **Negative**: the overlap/redundancy persists until the evaluation lands; new CC-vs-plugin drift accrues.
- **Follow-up**: tracked in `state/MONITORING-2026-06.md` (Actionable top-1). Trigger `/discuss native workflows vs /team` to produce the superseding ADR.
