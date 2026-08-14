# ADR 0020 — Graphify suggestion gate recalibrated: 300 → 200 code files

## Status
Accepted (2026-06-10)

Date: 2026-06-10
Supersedes: ADR 0019 §D-1 (threshold value only — everything else unchanged)
Superseded by: —

## Context

Field test 2026-06-10 on TheTeacher (`~/MyProjects/TheTeacher`, Next.js + Cloudflare Workers): **222 tracked code files** — below the ADR 0019 §D-1 gate of 300, so `graphify-suggest.sh` would never have offered it. Yet:

- the user designates it as a reference "gros projet";
- the build took 6.4 s → 3238 nodes / 4957 edges / 198 communities `[OBSERVED]`;
- Graphify's own corpus check concluded "corpus is large enough that graph structure adds value" `[OBSERVED: graphify-out/GRAPH_REPORT.md]`;
- a filtered query (`--context call --context import`) returned the complete block-architecture map with `file:line` in ~500 tokens `[OBSERVED]`.

Observed anchors for the gate: 28 code files (viewer) → no orientation value; 70 (`~/.claude`) → silence by design; 222 (TheTeacher) → real value. The boundary lies between 70 and 222.

A floor remains necessary (rejected: 10–50): below ~70 files the graph is a net-negative indirection (reading the files IS optimal orientation), the per-commit rebuild costs seconds for nothing, and an always-firing suggestion is alert-fatigue spam that kills the legitimate signal.

## Decision

### D-1 · Gate = 200 code files

`hooks/graphify-suggest.sh` and the `/graphify init` low-ROI warning use **≥ 200** (was 300). 200 is the conservative bound on the evidence side: it admits TheTeacher-class projects while keeping every observed no-value size silent.

## Consequences

- TheTeacher-class projects now get the unprompted suggestion; small repos stay silent.
- Re-calibrate only on a new observed anchor: a ≥ 200 project where the graph proves useless, or a < 200 project where it proves valuable — either triggers a follow-up ADR, not an in-place tweak.

## Tests that would invalidate this design

- T1 — suggest hook silent on a 222-code-file repo, or emitting on a 70-code-file repo → gate wiring wrong.
- T2 — a future D-5 measurement (ADR 0019) on a 200–300 file project shows the graph adds no orientation value → 200 was too low, supersede.
