# ADR 0019 — Graphify as per-project orientation graph (opt-in, custom integration)

## Status
Accepted (2026-06-10). D-1 threshold amended by 0020 §D-1 (300 → 200 code files).

Date: 2026-06-10
Supersedes: —
Superseded by: —

## Context

`/team` pays the codebase-orientation cost **× N agents**: every teammate cold-starts in its own session and re-discovers the project (architect reads, developer re-reads, reviewer re-reads). On a 500+ file codebase this is the dominant token expense of a run. A pre-computed graph is a shared orientation artifact — one build, N consumers — matching the existing "bulky artifacts → file path in briefs" pattern (ADR 0001).

[Graphify](https://github.com/safishamsi/graphify) (PyPI package `graphifyy` 0.8.37, MIT, 64.9k stars, YC S26) builds a queryable knowledge graph from a codebase. Empirical validation 2026-06-10 (smoke test on a viewer copy in `/tmp`):

- `graphify update <path>` = initial build AND incremental update, tree-sitter AST only, **no LLM, no API key** `[OBSERVED: 168 nodes / 265 edges / 9 communities, all API-key env vars unset]`
- `graphify query|explain|affected` work offline and return nodes with `file:line` `[OBSERVED: BFS query on renderMarkdown → 13 nodes with src= loc=]`
- `graphify hook install` writes post-commit/post-checkout AST-only rebuilds; **appends** to existing hooks via a `# graphify-hook-start` marked section, guards against rebase/merge/cherry-pick, bypass via `GRAPHIFY_SKIP_HOOK=1` `[OBSERVED: pre-existing post-commit content preserved]`

The upstream Claude Code integration (`graphify claude install`) writes a section into CLAUDE.md and installs a PreToolUse hook that nudges away from grep before every file-search call. Both conflict with this plugin: CLAUDE.md is curated by hand, and the evidence protocol **mandates** empirical grep (`[OBSERVED]` evidence for justifiability, callers, dead code). A graph answer is at best `[SOURCE]`, never `[OBSERVED]`.

## Decision

### D-1 · Opt-in per project, lifecycle via `/graphify`

The graph is never global and never automatic. The `/graphify` skill (`skills/graphify/SKILL.md`) owns the lifecycle: `init` (preflight `uv tool install graphifyy`, evaluation gate, build, gitignore, freshness hooks), `update`, `status`, `off`. The evaluation at project arrival is a SessionStart suggestion (`hooks/graphify-suggest.sh`): ≥ 300 tracked code files and no graph → suggest `/graphify init`; graph present, stale, and freshness hooks missing → suggest `/graphify update`; silent otherwise. Kill-switch: `GRAPHIFY_SUGGEST_DISABLE=1`.

### D-2 · Custom integration only — upstream installer forbidden

`graphify claude install` (and `graphify install`) MUST NOT be run. No CLAUDE.md takeover, no PreToolUse nudge hook. The plugin's three consumption points are: the agents' common block (D-3), `/team` STEP 0 (D-4), and the `/graphify` skill itself.

### D-3 · Orientation / verification doctrine

The 9 base agents carry an "Orientation graph (Graphify — if present)" section: orient FIRST via `GRAPH_REPORT.md` / `graphify query`, read only the files the graph points to, cite as `[SOURCE: graphify-out/graph.json]`. Verification claims (callers, dead code, justifiability) remain `[OBSERVED]` via grep/read on the working tree. The graph is an index, possibly stale — never proof. Control twins regenerate via the pre-commit hook (ADR 0003 §D-3).

### D-4 · Freshness

Primary: Graphify's own post-commit/post-checkout hooks (AST-only, free), installed at `init`. Backstop: `/team` STEP 0 refreshes a stale graph (`graphify update .`) before injecting the pointer into briefs. `graphify-out/` is gitignored (solo use, derived artifact, folder-cleanliness rule).

### D-5 · Adoption is conditional, measured before generalizing

The integration ships dormant: it activates only on projects passing the ≥ 300 code-file gate. On the first real 500+ file project, measure orientation-token delta on comparable `/team` tasks with/without the graph pointer in briefs (instrument: `token-tracker.sh` per session/agent). The result feeds a follow-up disposition (keep / tune gate / supersede).

## Consequences

- (+) Orientation cost amortized across teammates; agents get `file:line` entry points without full reads.
- (+) Zero footprint on projects below the gate; zero CLAUDE.md / permission-surface changes.
- (−) New per-project dependency (`uv` + `graphifyy`); one more SessionStart hook (cheap: `git ls-files | grep -c`).
- (−) Staleness risk between commits mid-pipeline — bounded by D-3 (orientation-only doctrine) and D-4.
- Risk: D-5 never executed = another built-but-unconsumed instrument (the 2026-06-04 audit anti-pattern). Mitigation: T5 below is the explicit falsification trigger.

## Tests that would invalidate this design

- T1 — `grep -rn "graphify claude install\|graphify install" skills/ hooks/ agents/ | grep -v "MUST NOT\|NEVER\|forbidden"` returns any executable invocation → D-2 violated.
- T2 — `hooks/graphify-suggest.sh` emits output in a repo below the gate (or outside git) → D-1 evaluation broken.
- T3 — `graphify update` on a keyless environment fails to produce `graphify-out/graph.json` → the local-only premise is false, D-1 init flow invalid.
- T4 — an agent cites `[OBSERVED]` evidence sourced from `graph.json` (review finding) → D-3 doctrine failed, tighten or remove the agents' section.
- T5 — first D-5 measurement shows < 10% orientation-token reduction on comparable tasks → the premise "orientation cost dominates and the graph cuts it" is refuted; supersede this ADR.
