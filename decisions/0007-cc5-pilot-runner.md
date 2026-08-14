# ADR 0007 — A/B pilot runner: `/evals run --pilot` for CC-5 corpus pilot

## Status

Proposed (2026-04-30). Implements step 8 of `~/.claude/decisions/0003-evaluation-protocol.md` (CC-5 corpus pilot, 13 cases × 2 trials × 2 conditions). Does **not** supersede any prior ADR — additive design that extends the `/evals` skill alongside the existing `--pre-pilot` subcommand. Inherits the multi-file structure of ADR 0006, the spawn-via-CLI-subprocess contract of ADR 0005 §B-2, and the pre-registration discipline of ADR 0003 §D-4. `[OBSERVED: .claude/decisions/0003-evaluation-protocol.md:200-211, 0005-evals-skill-design.md, 0006-evals-skill-multifile.md]` Implementation reconciled by 0018: runner shipped + pilot executed (evals/reports/); pilot verdict UNDETERMINED, paused sunset 2026-09-04 (0016 §A8/§D-4).

## Context

ADR 0003 §"Implementation order" step 7 (pre-pilot) shipped at commit `e5a1051` (15/15 trials DONE — `evals/runs/20260430T111218Z/`). Pre-pilot resolved Q2 (no N escalation, ratio_max = 0.142) and Q5 (σ_noise = 1.03 finding-units, d=0.8 detection-recoverable at N=2). All 6 methodological questions are now `RESOLVED` in `evals/HYPOTHESES.md`. CC-5 hypotheses (H0/H1, primary metric = red-flag count, suppression rule from §D-2) are pre-registered. `[OBSERVED: evals/HYPOTHESES.md:94-119, 164-180]`

Step 8 is the next gate: the **CC-5 corpus pilot** itself. It needs an A/B runner that does not yet exist. The current `/evals run --pre-pilot` is single-condition (control-only, `code-reviewer-control` × 15) and cannot fulfill the pilot's 52-trial × 2-condition cardinality.

The A/B *toggle* infrastructure is already in place (commit `ba7cce1`): CC-START/CC-END markers in 8 CC-bearing agents, `gen-control-agents.sh` autogen, pre-commit regen hook, pollution allowlist for `*-control.md`. What is missing is the **runner that consumes the toggle**.

### Missing-piece map (against task brief points 1-6)

| # | Gap | Resolved by sub-decision |
|---|---|---|
| 1 | `--pilot` subcommand absent | D-1 |
| 2 | Spawn both `code-reviewer` (treatment) AND `code-reviewer-control` (control) per (case, trial) | D-2 |
| 3 | Cardinality 13×2×2 = 52 vs pre-pilot 15 | D-3 |
| 4 | Paired effect-size analysis (Cohen's d, IC95, verdict) absent | D-5 |
| 5 | Manifest schema lacks `condition` + `paired_trial_index` | D-4 |
| 6 | Pre-flight gates need corpus-size + autogen-drift checks | D-6, D-8 |

### Sources used (verified at write time, no new WebFetch — vetted in ADR 0003/0005/0006 or canonical references)

| # | Source | Used for | Marker |
|---|---|---|---|
| 1 | Cohen 1992 *Psychol Bull* 112(1):155-159 — "A Power Primer" | d ≥ 0.8 effect target + suppression rule sign convention | `[SOURCE peer-reviewed]` (vetted ADR 0003) |
| 2 | Lakens 2013 *Front Psychol* 4:863 — "Calculating and reporting effect sizes" §2.2 | Paired Cohen's d formula d_z = mean(diff) / σ(diff) for within-subjects design | `[SOURCE peer-reviewed]` |
| 3 | Efron & Tibshirani 1993 — "An Introduction to the Bootstrap" Chapman & Hall | Percentile-bootstrap IC95 of d on small N (n=13 case-pairs, parametric IC fails normality at this size) | `[SOURCE peer-reviewed]` (vetted ADR 0005 D-4) |
| 4 | Nosek, Ebersole, DeHaven & Mellor 2018 *PNAS* 115(11):2600-2606 | Pre-registration gate inheritance from `--pre-pilot` | `[SOURCE peer-reviewed]` (vetted ADR 0003 §D-4) |
| 5 | ADR 0003 §D-2 lines 76-79 (suppression rule) + line 161 (d>1.5 leakage warning) | D-5 verdict thresholds + leakage detection | `[OBSERVED]` |
| 6 | ADR 0005 §B-2 *Refutable by:* clause + commit `250c533` | CLI subprocess (`claude -p --agent X`) is the canonical spawn — `Agent(subagent_type=...)` empirically deadlocks | `[OBSERVED]` |
| 7 | ADR 0006 D-1 line budget + D-2 path resolution + D-4 justifiability | New scripts live in `~/.claude/skills/evals/scripts/`, derived `TPL_DIR` via `$(dirname "$0")`, every new file has ≥1 caller in the diff | `[OBSERVED]` |
| 8 | `~/.claude/scripts/gen-control-agents.sh` `--check` mode (lines 22-23, 96-99) | Drift gate (Gate D) closes the rebase/`--no-verify` bypass loop | `[OBSERVED]` |
| 9 | ADR 0003 §"Open question Q4" + HYPOTHESES.md Q4 RESOLVED 50/50 | Corpus stratification is a *separate* missing piece (corpus expansion task), not in scope here | `[OBSERVED]` |

## Patterns evaluated

| Pattern | Domain | Decision | Justification |
|---|---|---|---|
| Sequential pair-spawn (1 trial = 2 sub-CLIs, treatment→control) | A/B runner orchestration | ✅ SELECTED | Identical prompt re-use guarantees `prompt_sha256` parity; simple recovery semantics; bounded tmux usage. `[ENGINEERING + OBSERVED ADR 0005 D-2]` |
| Parallel pair-spawn (2 sub-CLIs concurrent per trial) | A/B runner orchestration | ❌ REJECTED | Doubles tmux pane usage (>12 cap); `--max-budget-usd` per-trial guardrail erodes; no measurement gain since trials are intra-pair-paired, not time-pressed. `[OBSERVED CLAUDE.md skill 17 rule + ADR 0005 D-2]` |
| Single-spawn with `--cc-toggle` flag forwarded to agent | A/B mechanism | ❌ REJECTED | Confound + Hawthorne — agent sees CC text in prompt + meta-instruction to ignore. Same flaw ADR 0003 §D-3 already rejected for `EVAL_NO_CC=1`. `[OBSERVED ADR 0003 §D-3 line 97]` |
| Paired Cohen's d (within-subjects on (case, trial)) | Statistical method | ✅ SELECTED | Higher power than independent samples for within-corpus comparison; matches Lakens 2013 d_z formula; aligns with ADR 0003 §D-2 d ≥ 0.8 threshold. `[SOURCE: Lakens 2013]` |
| Independent t-test / unpaired Cohen's d | Statistical method | ❌ REJECTED | Wastes the structural pairing (same case-trial seen by both arms with identical prompt_sha256). Lower power → underpowered at n=13. `[SOURCE: Lakens 2013]` |
| Hedges-Olkin parametric IC95 of d | IC95 estimation | ❌ REJECTED at n=13 | Parametric IC95 assumes normality of differences; ADR 0005 D-4 already rejected this for n=15 trials. Bootstrap is consistent across the skill. `[SOURCE: Efron-Tibshirani 1993]` |
| Percentile bootstrap on the paired differences | IC95 estimation | ✅ SELECTED | Distribution-free; consistent with `eval-stats.sh` existing pattern; 1000 resamples × 13 differences ~5 ms. `[SOURCE: Efron-Tibshirani 1993, OBSERVED scripts/eval-stats.sh:156-171]` |
| Extract `scripts/lib/pre-flight.sh` (DRY across pre-pilot + pilot) | Pre-flight gate factoring | ❌ REJECTED THIS ITER | Rule-of-three: only 2 callers exist. ADR 0006 Pre-mortem Scenario C explicitly defers this to the 3rd caller (e.g. CC-4 pilot). Premature now. `[OBSERVED ADR 0006 Pre-mortem-C, CLAUDE.md no-premature-abstraction]` |
| New `report-pilot.sh` invokes `eval-stats-paired.sh` (new helper) | Stats helper organization | ✅ SELECTED | Paired-d math operates on differences (per `paired_trial_index` join), output schema differs from per-case σ; cleaner than overloading `eval-stats.sh` with a `--paired` mode. Each new script has 1 caller in the diff (justifiability). `[OBSERVED ADR 0006 D-4]` |
| Extend `eval-stats.sh` with `--paired` mode | Stats helper organization | ❌ REJECTED | Doubles its branch logic; couples per-case σ math (used by pre-pilot) to paired-d math (used by pilot). Surgery would touch existing code (CLAUDE.md surgical-changes). `[OBSERVED CLAUDE.md surgical-changes]` |

## Proposed architecture

### Overview

```
/evals run --pilot
   │
   ▼
~/.claude/skills/evals/SKILL.md  (§run --pilot dispatch, ≤25 lines added)
   │ bash ~/.claude/skills/evals/scripts/run-pilot.sh [--n-cases N] [--n-trials N] [--dry-run]
   ▼
run-pilot.sh
  ├── Gate A:  HYPOTHESES.md Q1-Q6 ALL RESOLVED (no Q2/Q5 pre-pilot exemption)
  ├── Gate B:  HYPOTHESES.md committed + working tree matches HEAD
  ├── Gate C:  corpus dir count ≥ N_CASES
  ├── Gate D:  gen-control-agents.sh --check returns 0 (no autogen drift)
  ├── ts=...  RUN_DIR=evals/runs/<ts>-pilot/   mkdir
  ├── for case_id in (sorted corpus dirs, take first N_CASES):
  │     for trial_n in 1..N_TRIALS:
  │        compute PROMPT_TEXT once  →  prompt_sha
  │        for condition in (treatment, control):
  │           AGENT_NAME = code-reviewer | code-reviewer-control
  │           claude -p --agent $AGENT  --dangerously-skip-permissions --max-budget-usd 1.00 ...
  │           write case-$id-trial-$n-$condition.json (incl. condition, paired_trial_index)
  │           append manifest.jsonl line
  └── echo RUN_DIR + suggested next: /evals report --pilot <ts>-pilot

/evals report --pilot [<ts>-pilot]
   │
   ▼
report-pilot.sh
   ├── locate RUN_DIR (arg or latest *-pilot)
   ├── n_actual == n_expected check (= N_CASES × N_TRIALS × 2)
   ├── invoke ~/.claude/scripts/eval-stats-paired.sh "$RUN_DIR" --metric red_flag_count
   │     ├── join treatment+control on paired_trial_index → differences[]
   │     ├── paired Cohen's d_z = mean(diff) / σ(diff)
   │     ├── 1000-resample bootstrap IC95 of d_z
   │     └── emit JSON: {d_z, ci95_low, ci95_high, n_pairs, mean_treatment, mean_control, ...}
   ├── apply ADR 0003 §D-2 verdict rule (sign-aware: H1 expects treatment < control)
   ├── if |d_z| > 1.5 → emit LEAKAGE-INVESTIGATE warning (overrides PASS verdict)
   └── write evals/reports/pilot-<ts>.md
```

### Main components

| Component | Responsibility | Technology |
|---|---|---|
| SKILL.md §run --pilot | LLM dispatch prose; passes args to script; summarizes return | Markdown prose + Bash invocation |
| SKILL.md §report --pilot | LLM dispatch prose; passes optional ts arg; summarizes report | Markdown prose + Bash invocation |
| `scripts/run-pilot.sh` | Gates A-D + 13×2×2 sequential pair-spawn loop + per-trial JSON write + manifest | Bash + jq + `claude -p` CLI subprocess |
| `scripts/report-pilot.sh` | Manifest validation + invoke paired-stats helper + verdict + leakage detection + Markdown report write | Bash + jq |
| `~/.claude/scripts/eval-stats-paired.sh` | Paired-d math: join by `paired_trial_index`, compute d_z + bootstrap IC95 | awk (per ADR 0005 D-4 awk-not-Python rule) |
| `~/.claude/scripts/gen-control-agents.sh --check` | Drift gate (Gate D) — already exists, additive caller | Bash (existing) |

### Data flows

1. **Run-time** (per (case, trial, condition) tuple):
   - PROMPT_TEXT computed ONCE per (case, trial); identical text fed to treatment then control → identical `prompt_sha256` (audit anchor for prompt parity invariant).
   - Per-trial JSON written immediately after each spawn returns (crash-recovery semantics inherited from ADR 0005 D-2).
   - Manifest line appended per trial (treatment line + control line for the same `paired_trial_index`).

2. **Report-time** (post-run):
   - `eval-stats-paired.sh` reads `RUN_DIR/case-*.json`, groups by `paired_trial_index`, computes `red_flag_count[treatment] − red_flag_count[control]` per pair, applies paired d_z + bootstrap IC95.
   - Verdict: maps (d_z, IC95) onto ADR 0003 §D-2 thresholds (sign-aware — H1 expects treatment < control, so we test d_z ≤ −0.8).
   - Leakage detection: if |d_z| > 1.5, emit LEAKAGE-INVESTIGATE warning + override verdict to "AUDIT-CORPUS" (do not auto-PASS).
   - Markdown report written to `evals/reports/pilot-<ts>.md`.

### Technical stack

| Technology | Role | Justification |
|---|---|---|
| Bash + jq | Orchestration + JSON read/write | Inherits from `--pre-pilot` (ADR 0005 D-4); zero new dependencies. `[OBSERVED]` |
| awk (n=1000 resamples × n=13 pairs) | Paired bootstrap | Math proven to run in <50ms in `eval-stats.sh` (ADR 0005 D-4); same pattern. `[OBSERVED scripts/eval-stats.sh:156-171]` |
| `claude -p --agent X --dangerously-skip-permissions --max-budget-usd 1.00` | Spawn mechanism | ADR 0005 §B-2 *Refutable by:* clause: `Agent()` deadlocks on this Claude version, CLI subprocess is canonical. `[OBSERVED]` |
| Markdown report under `evals/reports/pilot-<ts>.md` | Output | Symmetric with pre-pilot's `pre-pilot-<ts>.md`; readable by humans + greppable. `[OBSERVED ADR 0005 D-4 + scripts/report-pre-pilot.sh:45]` |

## Key technical decisions

### D-1 · Subcommand structure — additive `--pilot`, no shared `lib/`

`/evals run --pilot` is a NEW subcommand, parallel to `/evals run --pre-pilot`. Both coexist. New scripts:
- `~/.claude/skills/evals/scripts/run-pilot.sh`
- `~/.claude/skills/evals/scripts/report-pilot.sh`

Pre-flight Gates A and B (HYPOTHESES resolution, git commit) are **duplicated** between `run-pre-pilot.sh` and `run-pilot.sh` for now (only 2 callers — rule of three not yet triggered). ADR 0006 Pre-mortem Scenario C explicitly mandates this delay; CC-4 pilot (3rd caller) will trigger extraction to `scripts/lib/pre-flight.sh`. `[OBSERVED ADR 0006 Pre-mortem-C, CLAUDE.md no-premature-abstraction]`

**Rejected alternative**: a single `run.sh --condition treatment|control|both` entry point. This would force `--pre-pilot` (control-only) and `--pilot` (both) to share argument plumbing while having different cardinality contracts (15 vs 52) and different Q-gate exemption rules (Q2/Q5 deferred-OK in pre-pilot, all-RESOLVED in pilot). The merge cost > the duplication cost at n=2 callers. `[ENGINEERING]`

`*Refutable by:* if a 3rd `run` mode (e.g. `--cc-4` pilot) lands without extraction to `scripts/lib/pre-flight.sh`, ADR 0006 Pre-mortem-C's "rule of three" mitigation has failed and the duplication has compounded into a maintenance hazard — at that point a superseding ADR introduces the lib extraction. Concrete check: `diff scripts/run-pre-pilot.sh scripts/run-pilot.sh | grep -A 20 "Gate A"` shows >50 duplicated lines AND a 3rd caller exists.`

### D-2 · Spawn pairing — sequential 1 trial = 2 sub-CLIs, identical prompt re-used

Per (case, trial), the runner computes `PROMPT_TEXT` exactly once (identical to the pre-pilot's prompt-build step at `run-pre-pilot.sh:67-75`), then spawns:

```
claude -p --agent code-reviewer         ... "$PROMPT_TEXT"  →  treatment.json
claude -p --agent code-reviewer-control ... "$PROMPT_TEXT"  →  control.json
```

**Prompt-parity invariant**: the SAME `$PROMPT_TEXT` variable is fed to both spawns; `prompt_sha256` is computed once and written to both jsonl entries. The script asserts `prompt_sha256[treatment] == prompt_sha256[control]` at write time (cheap defensive check; failure = abort run with non-zero exit + clear message). This is what makes the comparison *paired* — without identical prompts, the differences[] array has confounded signal. `[ENGINEERING]`

**Sequential, not parallel**: same rationale as ADR 0005 D-2 — tmux pane budget + `--max-budget-usd` per-trial guardrail. Wall-time projection: 60-104s/spawn × 52 = **52-90 min** total at default 13×2×2; documented in SKILL.md prose so the user knows to launch and walk away.

**Spawn ordering**: treatment first, then control, within a (case, trial). This ordering is logged via `paired_trial_index` (incremented per case-trial, NOT per spawn — both members of a pair share the same index). The order itself is statistically inert for paired d_z (the diff is direction-aware via sign of the mean), but consistent ordering simplifies recovery and human inspection of the manifest. `[ENGINEERING]`

**Rejected**: spawn ordering treatment-first vs control-first per random seed. Adds noise without measurement benefit — pre-pilot Q5 already established σ_noise on the *same* control agent across 5 trials; intra-pair ordering is below that floor. `[OBSERVED evals/HYPOTHESES.md:172]`

`*Refutable by:* if T6 (prompt parity test below) shows `prompt_sha256` differs between treatment and control entries of any paired_trial_index in any test fixture, the in-memory variable re-use was not actually preserved (e.g. shell quoting bug, env-var interpolation between spawns) — the entire paired analysis is invalid and the runner must re-emit the prompt to a tmpfile and read it back for both spawns to guarantee parity.`

### D-3 · Cardinality + parameterization — defaults from CC-5 hypotheses, refuse on insufficient corpus

Defaults match the pre-registered CC-5 hypotheses (HYPOTHESES.md line 106): **N_CASES=13, N_TRIALS=2**. Both overridable:

```
bash run-pilot.sh                                    # defaults: 13 cases × 2 trials × 2 = 52
bash run-pilot.sh --n-cases 13 --n-trials 2          # explicit
bash run-pilot.sh --n-cases 3                        # smoke test against current 3-stub corpus
bash run-pilot.sh --dry-run                          # prints intended (case, trial, condition) tuples, spawns 0
```

**Corpus-size enforcement** (Gate C): script counts `evals/corpus/*/` dirs alphabetically. If `count < N_CASES`, **REFUSE** with non-zero exit + message:

```
ERROR: corpus has 3 cases, --n-cases 13 requested.
Either expand evals/corpus/ to ≥13 cases (per ADR 0003 §D-1 hybrid composition: 8-10 synthetic + 3-5 OWASP + 2 real diffs)
OR explicitly override with --n-cases 3 (smoke test only — NOT a valid CC-5 pilot per HYPOTHESES.md).
```

This refuses the **silent truncation** failure mode where a user runs the full pilot expecting 13 cases and gets a 3-case underpowered run that contaminates the audit anchor. The override exists for smoke testing (T3 below). `[ENGINEERING]`

**Case selection when count > N_CASES**: alphabetical sort, take first N_CASES. Deterministic and auditable. Future variants (random seed-based, stratification-aware) deferred to a superseding ADR if/when the corpus exceeds the pilot size. `[ENGINEERING]`

**`--dry-run` mode**: walks the loop, prints `RUN <case_id> trial=<n> condition=<treatment|control>`, but `claude -p` is replaced by `echo "DRY-RUN <case> <trial> <condition>"`. Manifest + per-trial JSONs are NOT written. Exit 0 if all gates pass. T2 (below) is the falsification of this. `[ENGINEERING]`

`*Refutable by:* if the user runs `bash run-pilot.sh` (no flags) on a 3-stub corpus and the script proceeds (instead of exiting non-zero with the corpus-size message), Gate C is broken; the 13-case default contract is dead. T7 below is the gate.`

### D-4 · Manifest schema additions — `condition` + `paired_trial_index`

The per-trial JSON schema inherits all 16 fields of ADR 0005 D-3 (timestamp, case_id, trial_number, agent_name, agent_sha256, prompt_sha256, prompt_text, output_text, output_length_chars, output_length_tokens, finding_count_by_severity, finding_count_total, exit_status, latency_ms, claude_md_sha256, skill_version_sha256). Adds:

| Field | Type | Justification |
|---|---|---|
| `condition` | string | One of `"treatment"`, `"control"`. Distinguishes the arm. `[ENGINEERING]` |
| `paired_trial_index` | int (1..N_CASES × N_TRIALS) | Both members of a (case, trial) pair share the same index. Join key for paired-d math. `[ENGINEERING]` |
| `red_flag_count` | int | Primary CC-5 metric: count of red-flag phrases (the 9 patterns from `agents/code-reviewer.md` table) in `output_text`, computed via grep on output. PRIMARY metric per HYPOTHESES.md line 100. `[OBSERVED evals/HYPOTHESES.md:100]` |

`agent_sha256` stays a single field per trial (each trial = one agent invocation, the agent for that trial is determined by `condition`). NOT keyed-object per-condition — keeping the schema flat preserves forward-compat with `eval-stats.sh` (per ADR 0005 D-3 T4 contract). `[OBSERVED ADR 0005 D-3]`

**File naming**: `case-<case_id>-trial-<n>-<condition>.json`. The `-<condition>` suffix is the only delta from pre-pilot's `case-<case_id>-trial-<n>.json` — preserves grep-ability while disambiguating arms. `[ENGINEERING]`

**Manifest line additions**: `{trial_index, case_id, trial_n, condition, paired_trial_index, status, timestamp}`. Pre-pilot manifest stays unchanged (it has no `condition`/`paired_trial_index` — schema forward-compat per ADR 0005 D-3 T4 ensures `eval-stats.sh` reading older manifests still works via missing-field defaults). `[OBSERVED ADR 0005 D-3]`

`*Refutable by:* if a future stats consumer (CC-4 pilot) reads a `--pilot` jsonl file and crashes because it expected a condition-keyed `agent_sha256` object, the flat-schema choice was wrong; mitigation = forward-compat shim in the consumer, NOT retro-edit of the schema (which would break the `--pilot` audit anchor).`

### D-5 · Statistical method — paired Cohen's d_z + percentile bootstrap IC95 + sign-aware verdict

**Formula** (Lakens 2013 §2.2):

```
For each paired_trial_index i: diff_i = red_flag_count[treatment]_i − red_flag_count[control]_i
mean_diff = mean(diff)
sd_diff   = sample stddev (n-1) of diff
d_z       = mean_diff / sd_diff
```

**IC95 of d_z**: 1000-resample percentile bootstrap on the differences array (resample with replacement, recompute d_z for each resample, take 2.5%/97.5% percentiles of the bootstrap distribution). Same pattern as `eval-stats.sh` lines 156-171, srand(42) for reproducibility.

**Sign convention**: H1 (HYPOTHESES.md line 98) states "red-flag count under CC-5 toggle-ON is reduced by ≥30% (median) vs toggle-OFF". `code-reviewer` = toggle-ON = treatment; `code-reviewer-control` = toggle-OFF = control. So under H1, `mean(treatment) < mean(control)` ⇒ `mean_diff < 0` ⇒ `d_z < 0`. PASS / GARDE = "treatment significantly reduces red-flags".

**Verdict mapping** (per ADR 0003 §D-2 lines 76-79, sign-adjusted):

| Outcome | d_z | IC95 of d_z | Verdict |
|---|---|---|---|
| Treatment reduces red-flags substantially | ≤ −0.8 | excludes 0 (i.e. IC95 entirely <0) | **PASS / GARDE** — advance to CC-4 |
| Effect too small to be meaningful | \|d_z\| < 0.5 | excludes 0.5 in absolute value (\|IC95\| entirely <0.5) | **SUPPRESS / SUPPRIME** — remove CC-5 within 30 days per ADR 0003 §D-4 |
| Indeterminate | otherwise (IC95 includes 0.5 in absolute value) | — | **UNDETERMINED / NULL** — escalate budget if stake warrants; do not auto-suppress |

**Leakage detection** (ADR 0003 line 161 verbatim): if `|d_z| > 1.5`, emit LEAKAGE-INVESTIGATE warning AND override the verdict to `AUDIT-CORPUS` (NOT auto-PASS). The corpus authoring may have inadvertently encoded CC-5's exact phrasing patterns as ground-truth defects, inflating the effect. The user must audit corpus generation prompts before accepting the verdict. `[OBSERVED ADR 0003 line 161]`

**Why a NEW helper `eval-stats-paired.sh`, not extension of `eval-stats.sh`**: `eval-stats.sh` operates on per-case (case_id, value) pairs and emits per-case σ + bootstrap IC95 of *means*. Paired-d operates on differences (joined by `paired_trial_index` across two condition slices) and emits one global d_z + IC95 of d_z. Different join shape, different output schema. Inlining as `--paired` mode would couple the two and force `eval-stats.sh` to know about `condition` + `paired_trial_index` (which pre-pilot doesn't have). Each new script has 1 caller in the diff (justifiability). `[OBSERVED ADR 0006 D-4, CLAUDE.md surgical-changes]`

`*Refutable by:* if T5 (synthetic fixture with known d=−1.0) below shows `eval-stats-paired.sh` returns d_z outside [−1.01, −0.99] (±0.01 budget), the math is implemented incorrectly OR the bootstrap seed produces too-wide CI on n=3 pairs. Sub-falsifications: (a) wrong formula (using sd of differences vs sd of means); (b) wrong join (mismatching paired_trial_index); (c) sign inverted (treatment − control vs control − treatment). T5 catches all three.`

### D-6 · Pre-flight gates — A/B/C/D, all-RESOLVED + corpus-size + autogen-drift

| Gate | Check | Inherited from |
|---|---|---|
| A | `evals/HYPOTHESES.md` Q1-Q6 ALL `RESOLVED` (no Q2/Q5 pre-pilot exemption) | Adapted from `run-pre-pilot.sh:11-33` |
| B | `git log --diff-filter=A evals/HYPOTHESES.md` non-empty AND `git diff --quiet HEAD -- evals/HYPOTHESES.md` clean | Verbatim from `run-pre-pilot.sh:36-48` |
| C | `count(evals/corpus/*/dirs) ≥ N_CASES`, else REFUSE | NEW (D-3 above) |
| D | `~/.claude/scripts/gen-control-agents.sh --check` returns 0 | NEW (D-8 below) |

**Difference from pre-pilot Gate A**: pre-pilot allows `[ ] OPEN` on Q2 and Q5 (they are answered BY the pre-pilot). For `--pilot`, Q2 and Q5 MUST already be RESOLVED in HYPOTHESES.md (the pre-pilot output amendment-log entry of 2026-04-30 11:25:45Z fulfilled this). The awk check in `run-pilot.sh` is identical to pre-pilot's awk EXCEPT it removes the `current_q != "Q2" && current_q != "Q5"` exemption — the new check is "any [ ] OPEN line fails". `[ENGINEERING]`

**Why these 4 gates, not 3 or 5**: A and B are inherited and load-bearing for pre-registration (Nosek 2018). C is the silent-truncation defense (D-3). D is the rebase-bypass defense (per `gen-control-agents.sh:21-23` documented gap). 5th gate "token budget envelope" (e.g. abort if cumulative session cost > $1500 per ADR 0003 §D-5) is rejected — out-of-band tracking via `token-tracker.sh` already exists, in-band check is duplicate plumbing. `[OBSERVED ADR 0003 §"Status of dependencies"]`

`*Refutable by:* if T7 (corpus-size gate test) OR T4 (autogen-drift gate test) below show the runner proceeds despite the gate violation, the gate logic has a bash-quoting or exit-code bug; the runner must be patched to fail-loud on the offending gate before any spawn.`

### D-7 · Output paths + report — `<ts>-pilot/` suffix, `pilot-<ts>.md` report

**Run dir**: `evals/runs/<ts>-pilot/` where `ts = $(date -u +%Y%m%dT%H%M%SZ)`. The `-pilot` suffix distinguishes from pre-pilot's `evals/runs/<ts>/`. This makes `ls evals/runs/` self-describing (`20260430T111218Z/` vs `20260501T093000Z-pilot/`) and lets `report --pre-pilot` and `report --pilot` use distinct latest-dir auto-selection rules. `[ENGINEERING]`

**Per-trial files**: `case-<case_id>-trial-<n>-<condition>.json` (D-4 above).

**Manifest**: `evals/runs/<ts>-pilot/manifest.jsonl`, one line per trial (52 lines at default cardinality, paired by `paired_trial_index`).

**Report**: `evals/reports/pilot-<ts>.md`. Contents:
- Header: run dir, n_actual / n_expected, n_pairs, condition spawn breakdown.
- Stats payload (paired): JSON output from `eval-stats-paired.sh`, including d_z, IC95, mean_treatment, mean_control, n_pairs.
- Per-case red-flag means table (treatment vs control vs diff) — for human eyeball + leakage scan (a single case driving the effect = warning sign).
- **Verdict**: PASS / SUPPRESS / UNDETERMINED / AUDIT-CORPUS (the leakage override).
- HYPOTHESES.md update prompt: instructions for amending the amendments-log with the verdict + run/report references (per ADR 0003 §D-4 audit-anchor discipline).

`*Refutable by:* if a `--pilot` report file lands at `evals/reports/pre-pilot-<ts>.md` (the wrong prefix) or overwrites an existing `pre-pilot-*.md` file, the output-path scoping is broken and the audit anchor is contaminated. T1 (pre-pilot regression) catches this by verifying pre-pilot artifacts unchanged after pilot work.`

### D-8 · Integration with existing infra — `gen-control-agents.sh --check` as Gate D, `eval-stats.sh` untouched

**Gate D** (autogen drift): the runner invokes `~/.claude/scripts/gen-control-agents.sh --check` as the LAST pre-flight check (after A/B/C). If exit ≠ 0, the runner aborts:

```
ERROR: gen-control-agents.sh --check reports drift in *-control.md.
Run: ~/.claude/scripts/gen-control-agents.sh    (regenerate without --check)
Then commit the regenerated files.
The pilot cannot run with stale controls — the A/B comparison would not isolate
the CC blocks (per ADR 0003 §D-3 *Refutable by:* clause line 109).
```

**Why explicit `--check` here despite the pre-commit hook**: per `gen-control-agents.sh:21-23`: "`git commit --no-verify`, `git rebase` (default), and cross-repo merges BYPASS the hook." The explicit check at gate-time closes that loop. `[OBSERVED scripts/gen-control-agents.sh:21-23]`

**`eval-stats.sh` is NOT touched**: the per-case σ math used by `report --pre-pilot` continues to live in `eval-stats.sh`, untouched. Paired-d math lives in the new `eval-stats-paired.sh`. ADR 0005 D-4 contract preserved — surgical changes per CLAUDE.md. `[OBSERVED CLAUDE.md surgical-changes]`

**`gen-control-agents.sh` is NOT touched**: only invoked. The `--check` mode already exists (lines 96-99). `[OBSERVED]`

`*Refutable by:* if the runner sees a DRIFT line on stderr from `gen-control-agents.sh --check` but proceeds (because the bash invocation captured stdout but ignored stderr or the exit code), Gate D is theater. Concrete check: artificially induce drift (`echo "X" >> ~/.claude/agents/code-reviewer-control.md`), run `bash run-pilot.sh`, expect exit ≠ 0 (T4).`

## Identified risks

| Risk | Likelihood | Mitigation | Residual |
|---|---|---|---|
| Prompt drift between treatment + control of same paired_trial_index | LOW (in-mem var re-use) | Compute prompt once per (case, trial); assert sha256 parity at write time; T6 below | Bash-level quoting bug on `$PROMPT_TEXT` could still mutate it between `claude -p` invocations — caught by T6 |
| Long wall-time (52-90 min) → user kills mid-run | MED | Per-trial JSON write IMMEDIATELY after spawn (crash-recovery); manifest line append per trial; `report --pilot` validates n_actual == n_expected before stats — partial runs refuse verdict | User manually edits manifest to match n_actual (out-of-scope foot-gun, accepted per ADR 0005 Pre-mortem-C residual) |
| `agent_sha256` drifts mid-run (user edits `agents/code-reviewer.md` between trial 5 and trial 26) | LOW (long run, but user shouldn't edit during) | Capture `AGENT_SHA_TREATMENT` and `AGENT_SHA_CONTROL` ONCE at run start (line ~57 of run-pilot.sh) → reused across all 52 trials; per-trial JSON records the captured hash, NOT a re-shasum mid-loop | Discipline-only — the captured-once value won't reflect the actual file content if the user edits mid-run; report grep `jq -r '.agent_sha256' | sort -u | wc -l` should always = 1 per condition slice |
| User runs `--pilot` after partial corpus expansion (e.g. 8 of 13 cases authored) | LOW (Gate C catches) | Gate C refuses with explicit message + recommendation to use `--n-cases 8` for partial smoke | User overrides with `--n-cases 13` while corpus has 8 — Gate C re-fires |
| `red_flag_count` regex misses real red-flags (false negatives) → understates effect | MED | The 9 patterns in `agents/code-reviewer.md` are the load-bearing ground-truth; metric is "count of literal pattern matches in output_text", machine-checkable per HYPOTHESES.md line 100 | Phrasing variants of the 9 patterns escape grep — accepted as primary metric definition; future ADR may extend if false-neg rate is observed via spot-checks |
| Report's verdict overrides the LEAKAGE-INVESTIGATE warning | LOW (D-5 specifies override) | If `|d_z| > 1.5`, verdict string is set to `AUDIT-CORPUS` BEFORE the PASS / SUPPRESS / UNDETERMINED branch is reached | Report prose still cites the d_z value (transparency); user reading only the d_z line and not the verdict line could mis-conclude — accepted, mitigated by report ordering (verdict line FIRST) |

## Explicit perimeter

- **A/B is for CC-5 only this iter.** CC-4 and CC-2 pilots will reuse the runner infrastructure (treatment/control spawn loop, manifest schema, paired-d stats), but their primary metrics differ (Refutable-by quality grid for CC-4; gold-standard pre-mortem comparison for CC-2). Their hypotheses are deferred per HYPOTHESES.md lines 121-127.
- **Corpus expansion is NOT in scope.** Currently 3 stubs; HYPOTHESES.md Q4 specifies 50/50 author/LLM-blind partition (ADR 0003 §D-1: 8-10 synthetic + 3-5 OWASP + 2 real). The corpus expansion is a **separate** missing piece for step 8 — this ADR specifies the runner; the operator (or a sibling pipeline) must expand the corpus before invoking `--pilot` without `--n-cases 3` override.
- **κ inter-rater protocol is NOT consumed by `--pilot`.** Q6's Sonnet-4.6 orthogonal-prompt protocol applies to the Refutable-by rubric (CC-4), not red-flag count (CC-5). Red-flag count is machine-checkable, no rater needed.
- **Resume-from-partial is NOT supported.** Per ADR 0005 D-2 (inherited): user Ctrl-C → manifest is partial → `report --pilot` refuses. User deletes `evals/runs/<ts>-pilot/` and reruns from scratch. Resume is a future-iter feature.
- **Random case sampling NOT supported.** Alphabetical sort + take first N_CASES is the deterministic selection rule. If/when corpus exceeds 13 cases AND the operator wants random sampling, a superseding ADR introduces a `--seed` flag.
- **No automatic suppression action.** If verdict = SUPPRESS, the report PROMPTS the user to write `ADR-NNNN-supersede-cc-5.md` within 30 days (per ADR 0003 §D-4) — the runner does NOT auto-edit any agent file. Discipline-only enforcement (per ADR 0003 §"Pre-mortem scenario 3").

## Suggested implementation plan

The developer implements in this order (each step a single commit; each commit testable in isolation):

1. **`eval-stats-paired.sh`**: implement `~/.claude/scripts/eval-stats-paired.sh` per D-5. Awk + percentile bootstrap on paired differences. Inputs: `<runs-dir> [--metric red_flag_count]`. Outputs: JSON to stdout `{d_z, ci95_low, ci95_high, n_pairs, mean_treatment, mean_control, sd_diff, mean_diff, leakage_warning: bool}`. Fixture: hand-craft 3-pair jsonl with known mean(diff) = −1.0 and σ(diff) = 1.0 → assert d_z ∈ [−1.01, −0.99]. Smoke test: T5.

2. **`run-pilot.sh` skeleton + Gates A-D**: the 4 pre-flight gates only, no spawn loop yet. After this commit, `bash run-pilot.sh --dry-run` exits 0 if all gates pass on a properly-staged repo, exit ≠ 0 with clear message otherwise. Smoke test: T2 + T4 + T7.

3. **`run-pilot.sh` spawn loop**: add the (case × trial × condition) loop, prompt-once-reuse-twice pattern, per-trial JSON write, manifest append. T6 prompt-parity assertion at write time. Smoke test: T3 (1×1×2 = 2 entries with paired_trial_index = 1 and identical prompt_sha256).

4. **`report-pilot.sh`**: locate run dir, validate n_actual == n_expected, invoke `eval-stats-paired.sh`, apply verdict rule, emit `evals/reports/pilot-<ts>.md`. Smoke test: T5 end-to-end.

5. **SKILL.md additions** (≤25 lines added per ADR 0006 budget): §run --pilot dispatch + §report --pilot dispatch + Strict Rule additions ("never spawn parallel `--pilot` arms", "never compute paired-d on partial data"). Verify `wc -l SKILL.md` ≤ 200 after the addition (133 + ~25 + ~5 padding ≤ 200, still under the ADR 0006 D-1 ceiling of 300).

6. **HYPOTHESES.md amendments-log entry** (per ADR 0003 §D-4 + ADR 0006 D-3 procedure-amendment-log convention): append a `### YYYY-MM-DD HH:MM:SSZ — /evals run --pilot subcommand introduced (ADR <new-number>)` block, behaviour preserved (T1), no hypothesis change.

7. **End-to-end smoke** (deferred to tester): full pipeline `/evals run --pilot --n-cases 3 --n-trials 1` (= 6 trials, ~6 min) on the current 3-stub corpus + committed HYPOTHESES.md → verify `evals/runs/<ts>-pilot/` populated with 6 jsonl + 6-line manifest, `evals/reports/pilot-<ts>.md` lands with verdict (likely UNDETERMINED at n=3 — sub-power, expected, NOT a falsification).

8. **(Deferred to next pipeline)** corpus expansion to 13 cases per ADR 0003 §D-1 hybrid composition; only after that does the *real* CC-5 pilot run.

Each commit message follows the conventional format with `Scope-risk: LOW` for steps 1-5 (additive only), `Scope-risk: LOW` for step 6 (HYPOTHESES amendment-log is an append-only zone). The whole sequence is shippable in one /team pipeline (developer + reviewer + tester).

## Tests that would invalidate this design

Per CC-4 of `~/.claude/docs/agent-synergy.md` and the `~/.claude/hooks/validate-arch.sh` contract (≥3 list bullets in this section).

- **T1 — Pre-pilot regression (no behaviour change to existing infra)**: in a fresh `/tmp/evals-pilot-test-<ts>/` working tree with all 4 gates green, run `/evals run --pre-pilot` (the existing subcommand) AFTER the pilot scripts ship. Capture `find evals/runs -type f -name 'case-*.json' | head | xargs -I{} jq -S keys {} | sort -u`. Component: `scripts/run-pre-pilot.sh` + `scripts/report-pre-pilot.sh`. Trigger: invocation of pre-pilot post-pilot-impl. Expected signal: byte-identical schema (no `condition` / `paired_trial_index` fields appearing in pre-pilot jsonl) and the same exit/output behaviour as commit `e5a1051`. If pre-pilot jsonl gains the new fields or pre-pilot's run dir naming changes, the additive-only claim is false; the pilot work has regressed shared infra and must be unwound before merge.

- **T2 — Dry-run mode produces 0 trials, logs intended tuples**: run `bash ~/.claude/skills/evals/scripts/run-pilot.sh --dry-run --n-cases 3 --n-trials 2` on a properly-staged repo. Component: `run-pilot.sh` --dry-run branch. Trigger: `--dry-run` flag + green gates. Expected signal: stdout contains exactly `3 × 2 × 2 = 12` lines matching `^DRY-RUN <case_id> <trial_n> <condition>$`, NO `evals/runs/*-pilot/` directory created (`ls evals/runs/ | grep pilot$` empty), exit 0. If even 1 trial JSON is written, dry-run is broken.

- **T3 — Mock 1×1×2 produces 2 paired entries**: hand-stage a corpus with exactly 1 case (`evals/corpus/test-stub/`), run `bash run-pilot.sh --n-cases 1 --n-trials 1` (gates green). Component: D-2 spawn pairing + D-4 schema. Trigger: minimal cardinality. Expected signal: `evals/runs/<ts>-pilot/` contains exactly 2 jsonl files (`case-test-stub-trial-1-treatment.json` + `case-test-stub-trial-1-control.json`), both with `paired_trial_index == 1`, both with **identical** `prompt_sha256`, `condition` field correctly set ("treatment" vs "control"), manifest.jsonl 2 lines. If `prompt_sha256` differs OR `paired_trial_index` differs OR a 3rd file exists, the pairing logic is broken.

- **T4 — Autogen drift gate (Gate D) refuses the run**: with the repo otherwise clean, induce drift via `printf '\nORPHAN_CC_TEXT\n' >> ~/.claude/agents/code-reviewer-control.md`. Run `bash run-pilot.sh --n-cases 3`. Component: Gate D. Trigger: stale `*-control.md` content. Expected signal: exit ≠ 0 within 5 seconds (before any spawn), stderr contains `gen-control-agents.sh --check` AND `DRIFT`, and zero `evals/runs/*-pilot/` artifacts created. After the test, restore via `git checkout HEAD -- ~/.claude/agents/code-reviewer-control.md`. If the runner proceeds and writes any jsonl, Gate D is non-functional and the rebase-bypass loop is open per `gen-control-agents.sh:21-23`.

- **T5 — Paired-d math on synthetic fixture**: hand-craft 3 paired jsonl entries (3 cases × 1 trial × 2 conditions = 6 files) with `red_flag_count` values such that differences are `[−2, −1, 0]` → mean(diff) = −1.0, σ(diff) = 1.0, d_z = −1.0 exactly. Run `~/.claude/scripts/eval-stats-paired.sh fixture/ --metric red_flag_count`. Component: paired-d formula + bootstrap. Trigger: known-answer fixture. Expected signal: output JSON has `d_z ∈ [−1.01, −0.99]` (±0.01 budget for numerical precision), `n_pairs == 3`, `leakage_warning == false`. If d_z is outside the band OR n_pairs ≠ 3 OR sign is +1.0 (sign-inverted), the math is broken (formula, join, OR sign convention).

- **T6 — Prompt parity invariant**: in any successful `--pilot` run (T3 or full smoke), enumerate `for idx in $(jq -r '.paired_trial_index' evals/runs/<ts>-pilot/case-*.json | sort -u); do count=$(jq -r --arg i "$idx" 'select(.paired_trial_index | tostring == $i) | .prompt_sha256' evals/runs/<ts>-pilot/case-*.json | sort -u | wc -l); [ "$count" -eq 1 ] || echo "MISMATCH at idx=$idx"; done`. Component: D-2 prompt re-use invariant. Trigger: successful run with ≥1 pair. Expected signal: zero MISMATCH lines (every paired_trial_index has exactly 1 unique prompt_sha256 across its 2 entries). If any MISMATCH, the prompt-once-reuse-twice contract was violated by some bash quoting/env interpolation between spawns; the runner must serialize the prompt to a tmpfile and re-read for both spawns.

- **T7 — Corpus-size gate (Gate C) refuses the run when count < N_CASES**: on the current 3-stub corpus, run `bash run-pilot.sh` (defaults N_CASES=13). Component: Gate C. Trigger: insufficient corpus. Expected signal: exit ≠ 0, stderr contains `corpus has 3 cases, --n-cases 13 requested`, zero `evals/runs/*-pilot/` artifacts. If the runner proceeds and writes any jsonl, Gate C is broken; the silent-truncation defense fails per D-3 contract.

## Pre-mortem (CC-2 self-application)

Three disaster scenarios, each (component, trigger condition, measurable signal):

### Scenario A — Prompt-parity invariant silently violated by a shell-quoting bug

- **Component**: `run-pilot.sh` lines that pass `$PROMPT_TEXT` to `claude -p` for treatment then control.
- **Trigger**: `$PROMPT_TEXT` contains a sequence the bash parser interprets between the two invocations (e.g. an unquoted backtick or `$(...)` if the prompt template is upgraded carelessly in a future iter), OR the prompt is regenerated (re-read from disk) between the two spawns and the disk file mutates (concurrent edit; tmpfile race).
- **Measurable signal**: T6 above fails — `paired_trial_index` X has 2 entries with different `prompt_sha256` values. The paired-d join produces silently wrong differences (the comparison is no longer apples-to-apples), the verdict is contaminated.
- **Mitigation in design (D-2)**: compute `PROMPT_TEXT` ONCE per (case, trial), keep in shell variable, re-feed to both spawns; assert `prompt_sha256[treatment] == prompt_sha256[control]` at jsonl write time → fail-loud abort on mismatch with explicit error message naming `paired_trial_index`. T6 enforces post-hoc.
- **Residual risk**: a bash bug between assert and write (vanishingly small, but possible). Mitigated by post-run T6 grep — caught in the report stage even if missed at run stage.

### Scenario B — `|d_z| > 1.5` leakage warning ignored by the user, AUDIT-CORPUS verdict misread as PASS

- **Component**: `report-pilot.sh` verdict-emission logic + the human reading the report.
- **Trigger**: corpus authoring leaks CC-5's exact 9 phrases as ground-truth. Treatment agent stops emitting them (because it has CC-5 active and avoids them); control agent emits them frequently. d_z = −2.3 (huge effect), IC95 = [−2.6, −1.9] (excludes 0 by a wide margin). The runner emits `|d_z| > 1.5 → AUDIT-CORPUS` but the user (or a future-me 6 months later) reads only the d_z line, sees a beautiful effect, and locks HYPOTHESES.md Q5 with "GARDE — CC-5 effect huge". Suppression follow-through (ADR 0003 §D-4) NEVER fires because verdict was wrongly read as PASS.
- **Measurable signal**: 60 days post-pilot, `git log -- evals/HYPOTHESES.md agents/` shows GARDE language in HYPOTHESES.md amendments-log AND the corpus authoring prompts (`evals/corpus/<id>/prompt.md` or generation transcript) have NOT been audited (no commit touching corpus generation between report date and 60-day mark).
- **Mitigation in design (D-5 + D-7)**: report verdict line is FIRST in the Markdown output (`## Verdict\n\n**AUDIT-CORPUS** — d_z = -2.3 exceeds the |1.5| leakage threshold...`); the ADR 0003 line 161 quote ("If d>1.5 observed, pause and audit corpus generation prompts for leakage") appears verbatim under the verdict line. The verdict string `AUDIT-CORPUS` is intentionally NOT a synonym of any ADR 0003 verdict — the user MUST stop and audit before reaching for GARDE/SUPPRIME.
- **Residual risk**: human discipline. Accepted: mitigated by the explicit 4-state vocabulary (PASS / SUPPRESS / UNDETERMINED / AUDIT-CORPUS) — `AUDIT-CORPUS` does not appear elsewhere in the eval lexicon, so a downstream consumer that string-matches verdict patterns will fail loudly rather than silently mis-classify.

### Scenario C — Pilot run interrupted mid-way (45 min in), partial manifest pollutes verdict

- **Component**: D-2 spawn loop (sequential, 52-90 min) + D-7 manifest validation in `report-pilot.sh`.
- **Trigger**: user starts `/evals run --pilot` Friday evening, machine sleeps Saturday, comes back Monday and the skill is hung at trial 35/52 (network blip, tmux pane crash, `claude` update). User Ctrl-C, `evals/runs/<ts>-pilot/` has 35 jsonl files. User runs `report --pilot` thinking "it's mostly done".
- **Measurable signal**: `wc -l evals/runs/<ts>-pilot/manifest.jsonl` = 35, `n_expected` = 52 (computed from N_CASES=13 × N_TRIALS=2 × 2). 35 ≠ 52.
- **Mitigation in design (D-7)**: `report-pilot.sh` first checks `n_actual == n_expected` (inherits from `report-pre-pilot.sh:19-26` pattern). On mismatch, exit ≠ 0 with `incomplete run; resume not supported in iter-1; delete <ts>-pilot/ and rerun`. The 35 partial files are NOT consumed.
- **Residual risk**: user manually edits manifest.jsonl to match n_actual = 35 (foot-gun, accepted out-of-scope per ADR 0005 Pre-mortem-C). The audit anchor would still notice — paired_trial_index gaps in the manifest betray a hand-edit; verifying the report's `n_pairs` field against `count(distinct paired_trial_index where condition='treatment')` would catch it on inspection. Not enforced in iter-1.

These scenarios are not hypothetical — Scenario A is a direct extension of the prompt-template pain that motivated `prompt_sha256` logging in ADR 0005 D-3; Scenario B is the materialized form of ADR 0003 §"Pre-mortem scenario 3" with d>1.5 substituted for d=0.3; Scenario C is the literal re-run of ADR 0005 §Pre-mortem-C against the larger pilot cardinality.

STATUS: DONE — design proposal complete, 8 sub-decisions locked, ≥3 falsification tests + pre-mortem + identified-risks sections in place per validate-arch.sh and CC-2/CC-4 contracts.
