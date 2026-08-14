---
description: Empirical evaluation protocol — pre-pilot variance + CC-5 A/B pilot (per ADR 0003)
argument-hint: init | run --pre-pilot | run --pilot | report --pre-pilot | report --pilot
---

<!-- Structural rationale: see ~/.claude/decisions/0006-evals-skill-multifile.md.
     Re-inlining the scripts/, references/, templates/ subdirs into this file
     requires a SUPERSEDING ADR per CLAUDE.md append-only rule. Do not silently
     refactor back to single-file. -->

## Project context
- Name: !`basename $(pwd)`
- Stack: !`cat package.json 2>/dev/null | head -5 || cat requirements.txt 2>/dev/null | head -5 || echo "Stack non detectee"`
- Existing evals: !`ls evals/ 2>/dev/null || echo "Pas de evals/"`
- Latest commits: !`git log --oneline -5 2>/dev/null || echo "Pas de repo git"`

## Goal

Implement steps 5 + 8 of `~/.claude/decisions/0003-evaluation-protocol.md` — the
pre-pilot test-retest baseline (Q5; `--pre-pilot`) and the CC-5 A/B corpus pilot
(`--pilot`). κ inter-rater and adversarial corpus generation are deferred to
subsequent pipelines.

Reference designs: `~/.claude/decisions/0005-evals-skill-design.md` (skill schema),
`~/.claude/decisions/0006-evals-skill-multifile.md` (this multi-file structure),
and `~/.claude/decisions/0007-cc5-pilot-runner.md` (A/B pilot runner).

## Subcommand dispatch

Read `$ARGUMENTS`:
- `init` → §init
- `run --pre-pilot` → §run --pre-pilot
- `run --pilot` → §run --pilot
- `report --pre-pilot` → §report --pre-pilot
- `report --pilot` → §report --pilot
- empty or unknown → display the dispatch reminder and exit

## §init

Create `evals/` scaffolding **idempotently** per D-6 of ADR 0005. Each path is reported
as `CREATED`, `PRESERVED`, or `NO_OP`. Re-running never overwrites a user-edited file.

Templates live as first-class files under `~/.claude/skills/evals/templates/` (per
ADR 0006 D-1) — `init.sh` derives the templates dir from its own location and `cp`s
each one only if the destination does not already exist.

Run via the `Bash` tool:

```bash
bash ~/.claude/skills/evals/scripts/init.sh
```

After bash returns, summarize the log lines (count of `CREATED` / `PRESERVED` / `NO_OP`)
to the user. Remind the user to **commit `evals/HYPOTHESES.md` to git BEFORE running
`/evals run --pre-pilot`** — without an `--diff-filter=A` git entry, the pre-flight
gate will refuse.

## §run --pre-pilot

The runner enforces two pre-flight gates (Gate A: HYPOTHESES.md questions RESOLVED;
Gate B: file committed and working tree clean) BEFORE creating any `evals/runs/<ts>/`
artifact, then spawns 15 sequential CLI subprocess trials (`claude -p` with the
`code-reviewer-control` agent), 3 cases × 5 trials.

For TP/FP matching, Cohen's κ procedure, and the Refutable-by quality grid, see
`~/.claude/skills/evals/references/methodology.md` (the LLM Reads it on demand —
not auto-loaded on dispatch).

Run via the `Bash` tool:

```bash
bash ~/.claude/skills/evals/scripts/run-pre-pilot.sh
```

The script writes per-trial JSON + a manifest line to `evals/runs/<ts>/`, and echoes
`RUN_DIR` plus the suggested next command on stdout. **Estimated wall time**:
60-104s/spawn × 15 = 15-26 min (canari-validated, ADR 0005 §B-2). Single-shot, no
resume — Ctrl-C leaves a partial manifest that `report --pre-pilot` will refuse.

## §report --pre-pilot

Optionally accept a timestamp argument (`/evals report --pre-pilot <ts>`); default to
the most recent dir under `evals/runs/`. The script computes σ on `finding_count_total`
via `~/.claude/scripts/eval-stats.sh`; if the primary mean is below 2 it falls back
to `output_length_chars` per D-8 multi-metric logging, emits a WARNING, and reports
both payloads side-by-side.

When invoking, pass any `<ts>` token from `$ARGUMENTS` as the first positional
parameter. If `$ARGUMENTS` is just `report --pre-pilot` (no timestamp), invoke with
no positional args — the script auto-selects the latest run directory.

Run via the `Bash` tool:

```bash
bash ~/.claude/skills/evals/scripts/report-pre-pilot.sh "$TS_ARG"
# or, with no timestamp:
bash ~/.claude/skills/evals/scripts/report-pre-pilot.sh
```

The report references **both** the verdict metric (with its CI) and the primary metric
(so a reader can spot the divergence per D-8).

## §run --pilot

CC-5 A/B pilot runner per ADR 0007. Spawns 13 cases × 2 trials × 2 conditions = 52
sequential `claude -p` subprocesses (treatment = `code-reviewer`, control =
`code-reviewer-control`). Identical prompt fed to both arms of each (case, trial)
pair (D-2 prompt-parity invariant; `paired_trial_index` is the join key).

Pre-flight gates: A (HYPOTHESES.md Q1-Q6 ALL RESOLVED — no Q2/Q5 exemption),
B (HYPOTHESES.md committed + clean), C (corpus has ≥ N_CASES dirs), D
(`gen-control-agents.sh --check` clean — closes the rebase/`--no-verify` bypass).

Run via the `Bash` tool:

```bash
bash ~/.claude/skills/evals/scripts/run-pilot.sh "$@"
```

Useful flags: `--n-cases <N>` (default 13), `--n-trials <N>` (default 2),
`--case-id <id>` (smoke 1 case), `--dry-run` (gates + intended tuples, 0 spawns).

**Estimated wall time**: 60-104s/spawn × 52 = **52-90 min** at default cardinality.
Single-shot, no resume — Ctrl-C leaves a partial manifest that `report --pilot`
will refuse.

## §report --pilot

Reads the manifest of a `*-pilot/` run dir, validates n_actual == n_expected
(distinct paired_trial_index × 2), invokes `~/.claude/scripts/eval-stats-paired.sh`
for paired Cohen's d_z + 1000-resample percentile-bootstrap IC95, applies the
ADR 0003 §D-2 verdict rule (sign-aware: H1 expects d_z ≤ −0.8). If `|d_z| > 1.5`
the verdict is overridden to **AUDIT-CORPUS** (ADR 0003 line 161 leakage clause).

Optionally accept a timestamp argument (`<ts>` or `<ts>-pilot`); default = latest
`evals/runs/*-pilot/`.

Run via the `Bash` tool:

```bash
bash ~/.claude/skills/evals/scripts/report-pilot.sh "$TS_ARG"
# or, with no timestamp:
bash ~/.claude/skills/evals/scripts/report-pilot.sh
```

Verdict line is FIRST in the report (D-7); the 4-state vocabulary is
`PASS | SUPPRESS | UNDETERMINED | AUDIT-CORPUS` — `AUDIT-CORPUS` is intentionally
NOT a synonym of any ADR 0003 verdict. The user MUST audit corpus generation
prompts before reaching for GARDE/SUPPRIME on a |d_z|>1.5 result.

## Dispatch reminder

If `$ARGUMENTS` is empty, display:

```
/evals init               — scaffold evals/ (idempotent)
/evals run --pre-pilot    — run 3×5 trials with code-reviewer-control
/evals report --pre-pilot — compute sigma + verdict from the latest run
/evals run --pilot        — run 13×2×2 A/B pilot (treatment + control)
/evals report --pilot     — paired d_z + IC95 + verdict from the latest pilot

See: ~/.claude/decisions/0003-evaluation-protocol.md
     ~/.claude/decisions/0006-evals-skill-multifile.md
     ~/.claude/decisions/0007-cc5-pilot-runner.md
```

## Strict rules

1. **Never overwrite** `evals/HYPOTHESES.md`, `evals/RUBRIC.md`, or any file under
   `evals/corpus/` once they exist (D-6).
2. **Never spawn parallel CLI subprocesses** in `run --pre-pilot` — sequential only (D-2). Cost-control rationale: 15 trials × $0.10-$0.50 each = $1.50-$7.50; concurrent spawns would erode the `--max-budget-usd 1.00` per-trial guardrail.
3. **Always pass** `--dangerously-skip-permissions` and `--max-budget-usd 1.00` on every `claude -p` invocation. Per ADR 0005 §B-2 *Refutable by:* clause, `Agent(subagent_type=...)` is empirically unreliable (2/2 deadlock — JOURNAL.md `2026-04-29 16:00` and `2026-04-30 10:35`); the CLI subprocess pivot is the canonical mechanism for `run --pre-pilot`.
4. **Never compute a verdict** on partial data — `n_actual != n_expected` aborts with
   non-zero exit (D-2 crash-recovery).
5. **Pre-registration gate is non-bypassable** — the skill refuses to run if
   `git log --diff-filter=A evals/HYPOTHESES.md` is empty OR if the working tree
   diverges from the committed `HYPOTHESES.md` (ADR 0003 §D-4 / Nosek 2018).
6. **Never re-inline scripts/ or templates/ back into this file** without a superseding
   ADR. The split is governed by ADR 0006; reverting requires a new ADR per CLAUDE.md
   append-only rule.
7. **`run --pilot` Gate D is non-bypassable** — `gen-control-agents.sh --check` failure
   aborts before any spawn. Per `gen-control-agents.sh:21-23`, `git commit --no-verify`,
   `git rebase`, and cross-repo merges BYPASS the pre-commit hook; gate-time check
   closes that loop (ADR 0007 §D-8).
8. **`run --pilot` spawns BOTH `code-reviewer` and `code-reviewer-control`** sequentially
   per (case, trial), with the SAME `$PROMPT_TEXT` re-fed to both — D-2 prompt-parity
   invariant. The `prompt_sha256` field is asserted equal across the pair at write time;
   mismatch aborts the run.
9. **Never compute paired-d on partial data** — `report --pilot` refuses if
   `n_actual != n_expected` (= distinct `paired_trial_index` × 2).

## Further reading

- `~/.claude/skills/evals/references/methodology.md` — TP/FP matching, Cohen's κ, Refutable-by grid
- `~/.claude/decisions/0003-evaluation-protocol.md` — full evaluation protocol
- `~/.claude/decisions/0005-evals-skill-design.md` — skill design (schema, D-8 fallback)
- `~/.claude/decisions/0006-evals-skill-multifile.md` — multi-file structure (file mapping, falsification tests)
- `~/.claude/decisions/0007-cc5-pilot-runner.md` — A/B pilot runner (sub-decisions D-1..D-8, T1-T7)
