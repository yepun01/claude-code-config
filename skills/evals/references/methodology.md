# Methodology — TP/FP matching, Cohen's κ, Refutable-by grid

This document is the lazy-load reference for the `/evals` skill. SKILL.md links here from the §run prose; the LLM Reads it on demand when running pre-pilot trials, computing verdicts, or answering methodological questions. It is NOT loaded on every dispatch.

Sources are in ADR 0003. Quote them with `[SOURCE: paper]` markers when citing.

## TP/FP matching protocol (3-tier)

Per ADR 0003 §D-1 (`[SOURCE: OWASP Benchmark v1.2; Just et al. 2014 ISSTA — Defects4J]`):

- **Strict TP** — same `type` AND `|finding.line - defect.line_start| ≤ 5`. The 5-line window is `[ENGINEERING]` — wide enough to absorb minor model offset (e.g. agent flagging the call site instead of the literal vulnerable line), narrow enough that a different defect within ±5 lines does not collide.
- **Type-only TP** — same `type` anywhere in the same file. Weight 0.5. Captures cases where the agent identifies the defect class but mis-localizes.
- **No match** — candidate FP, but **manual adjudication required**. Per Natella et al. 2013, agents may surface real residual bugs that the seeded ground-truth missed; the adjudicator marks `bonus_TP` vs `actual_FP`. Adjudicated bonus findings land in `evals/corpus/<id>/bonus_labels.jsonl` (built incrementally — never overwrites).

Severity buckets are derived from the agent's section header (`## Critical` / `## Warnings` / `## Suggestions`); the schema's `medium` and `info` fields stay zero in the pre-pilot pipeline. The `VERDICT:` line is excluded from finding counts — it is a status string, not a finding.

## Cohen's κ — inter-rater reliability

Per ADR 0003 §D-1 final paragraph + `[SOURCE: Landis & Koch 1977]`:

- 20% of findings are **double-labeled** by two independent raters using the same Refutable-by grid.
- Target Cohen's κ ≥ 0.6 — Landis-Koch "moderate-to-substantial" agreement floor.
- κ < 0.6 invalidates the rubric; the next pilot must redesign the grid before producing a CC verdict.

Pre-pilot scope (ADR 0006 D-1) does NOT exercise κ — single-rater output_text is adjudicated post-hoc. κ becomes load-bearing in the CC-5 full pilot (ADR 0003 step 8).

## Refutable-by quality grid (3-criterion, score 0/0.5/1)

Per ADR 0003 §"Open question Q3" (calibration corpus = 20 lines from prior ADRs scoring mean 2.60):

A finding's Refutable-by clause is scored on three independent criteria, each 0/0.5/1 (max 3):

1. **Names a measurable signal** — does the clause specify what observable evidence (a count, a log line, a metric, a file diff) would falsify the claim? Score 1 if yes-and-quantified, 0.5 if directional-but-vague, 0 if absent.
2. **Names a trigger condition** — does the clause specify when/where the falsification check fires (after N runs, on a specific commit, in a particular environment)? 1/0.5/0 as above.
3. **Excludes generic restatement** — does the clause add information beyond restating the claim's negation? "X is true; refutable by: X being false" scores 0. "X improves quality; refutable by: 30 trials show no quality delta on metric M with IC95 excluding d=0.5" scores 1.

Calibration baseline: 20 lines from ADRs 0002-0005 score mean 2.60 / 3.0. The CC-4 pilot suppression rule operates on the **agent-emitted** distribution, not on this calibration baseline (`[SOURCE: HYPOTHESES.md Pre-mortem Scenario C]` — calibration-corpus inflation bias).

## D-8 fallback metric (sub-2 finding count)

Per ADR 0003 §D-5 / `0005-evals-skill-design.md` D-8:

If primary metric `finding_count_total` mean falls below 2 across the run, σ measurement is unreliable (count noise dominates effect). The report falls back to `output_length_chars` and emits a WARNING in the report header. Both metrics are logged; readers can spot divergence.

## Pre-flight gate references

- **Gate A** (HYPOTHESES.md questions RESOLVED) — `[SOURCE: ADR 0003 §D-4]`. Q2 and Q5 are answered BY the pre-pilot itself; Q1, Q3, Q4, Q6 must be resolved upstream.
- **Gate B** (HYPOTHESES.md committed + working tree clean) — `[SOURCE: Nosek et al. 2018 PNAS]`. Pre-registration loses force if amendable post-hoc; the audit anchor is `git log --diff-filter=A evals/HYPOTHESES.md` predating any `evals/runs/*` artifact.

## Further reading

- `~/.claude/decisions/0003-evaluation-protocol.md` — full protocol ADR with peer-reviewed source table
- `~/.claude/decisions/0005-evals-skill-design.md` — skill-design ADR (D-8 fallback rationale, schema)
- `~/.claude/decisions/0006-evals-skill-multifile.md` — this multi-file split (file-mapping table, falsification tests)
- `~/.claude/evals/HYPOTHESES.md` — pre-registered Q1-Q6 + amendments log
