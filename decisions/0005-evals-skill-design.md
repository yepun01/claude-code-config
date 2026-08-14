# ADR 0005 — `/evals` skill design (scaffolding + pre-pilot)

## Status
Proposed (2026-04-29). Implementation pending. Implements step 5 of ADR 0003 implementation order. D-1 superseded by 0006 §D-1 (single-file convention → multi-file split, trigger fired at 604 lines). Implementation reconciled by 0018: /evals skill shipped; eval-program verdict UNDETERMINED, paused sunset 2026-09-04 (0016 §A8/§D-4).

## Context

ADR 0003 commits the plugin to an empirical evaluation protocol with pre-registered hypotheses, a hybrid corpus, an A/B toggle mechanism, and a staged CC-5 → CC-4 → CC-2 sequence. Steps 1-4 of the implementation order are landed (`ba7cce1`): markers in 8 CC-bearing agents, `gen-control-agents.sh`, pre-commit regen, pollution allowlist for `*-control.md`.

Step 5 = the user-facing entry point: skill `/evals` that orchestrates the protocol. **Scope strictly limited to scaffolding + the pre-pilot subcommand**; full corpus pilot, A/B mode, κ inter-rater protocol, adversarial corpus generation, and `add-case` are deferred to subsequent pipelines.

The pre-pilot is the *first measurement gate*: ADR 0003 §"Open methodological question Q5" requires a test-retest baseline (3 cases × 5 trials × 1 condition, no toggle) BEFORE any A/B comparison runs, to establish the noise floor against which any d ≥ 0.8 effect must rise. Without this baseline, every later effect-size estimate floats unanchored against Claude's stochasticity. `[OBSERVED: .claude/decisions/0003-evaluation-protocol.md:194-198]`

This ADR fixes (a) how the skill is structured, (b) how pre-pilot trials are spawned and logged, (c) how variance is computed, (d) what HYPOTHESES.md and RUBRIC.md look like, and (e) how `init` behaves idempotently.

### Sources used (verified at write time, no new WebFetch — all already vetted in ADR 0003 or canonical references)

| # | Source | Used for | Marker |
|---|---|---|---|
| 1 | Cohen 1992 *Psychol Bull* 112(1):155-159 — "A Power Primer" | d ≥ 0.8 effect target floors the variance metric choice | `[SOURCE peer-reviewed]` (vetted in ADR 0003) |
| 2 | Efron & Tibshirani 1993 — "An Introduction to the Bootstrap" (Chapman & Hall) | Percentile bootstrap CI for n=5 per case (parametric IC95 fails normality at small n) | `[SOURCE peer-reviewed]` |
| 3 | Natella, Cotroneo, Duraes, Madeira 2013 *IEEE TSE* 39(1):80-96 | Synthetic-only corpus distortion → motivates the warning when pre-pilot uses only inline stubs | `[SOURCE peer-reviewed]` (vetted in ADR 0003) |
| 4 | Nosek, Ebersole, DeHaven & Mellor 2018 *PNAS* 115(11):2600-2606 | Pre-registration BEFORE first run → motivates D-5/D-6 idempotence rule | `[SOURCE peer-reviewed]` (vetted in ADR 0003) |
| 5 | ADR 0003 §D-5 reproducibility | Trial logging schema (sha256 of agent + prompt) | `[OBSERVED: .claude/decisions/0003-evaluation-protocol.md:91-92,135-137]` |
| 6 | `~/.claude/skills/{commit,spec,team,challenge,premortem}/SKILL.md` | All existing skills are single-file SKILL.md → convention for D-1 | `[OBSERVED]` |

## Decision

### D-1 · Skill structure — single `SKILL.md` + one shared stats helper

**Choice**: `~/.claude/skills/evals/SKILL.md` is the only file in the skill folder. Subcommand dispatch is done via `$ARGUMENTS` branching prose (LLM follows the matching subsection). Pure-computation bash that has no LLM-decision content (statistics, sha256, jsonl aggregation) is extracted to `~/.claude/scripts/eval-stats.sh` — symmetric with the existing `~/.claude/scripts/gen-control-agents.sh` that ADR 0003 §D-3 already established for shared utilities.

**Why not multi-file in skill dir**: the Claude Code skill loader reads `SKILL.md` as the single entry point; siblings are not auto-loaded. Splitting into `init.sh`/`run.sh`/`report.sh` inside the skill folder would force the SKILL.md prose to `Bash("./init.sh")`, which negates the prose-driven "the LLM IS the orchestrator" model that the existing 8 skills follow. `[OBSERVED: .claude/skills/team/SKILL.md, .claude/skills/spec/SKILL.md, .claude/skills/commit/SKILL.md]`

**Why a separate `eval-stats.sh`**: σ + IC95 + bootstrap math is pure computation, has no LLM-decision branches, and will be re-invoked by every later pilot (CC-5, CC-4, CC-2). Inlining it in SKILL.md as `Bash` blocks would (a) duplicate the math across subcommands, (b) couple the implementation to the LLM context window. Extracting matches ADR 0003's pattern for `gen-control-agents.sh`. `[ENGINEERING]`

**Rejected**: multi-file `~/.claude/skills/evals/{init,run,report}.sh`. Adds dispatch ceremony with no LLM-decision payoff and breaks the prose convention.

*Refutable by:* if SKILL.md exceeds ~600 lines of prose (current /team SKILL.md sits at 455 and is already at the edge of readability per CLAUDE.md "prose code" rule), the single-file approach has failed and the skill must be split — but the split goes via a NEW ADR superseding this one, not silent refactor.

### D-2 · Spawn orchestration — sequential `TeamCreate` + 15 `Agent(code-reviewer-control)` calls

**Choice**: pre-pilot run = one `TeamCreate(team_name="evals-pre-pilot-<ts>")`, then a sequential loop of 15 `Agent(subagent_type="code-reviewer-control", team_name=..., mode="bypassPermissions")` spawns (3 cases × 5 trials), each followed by a wait for `STATUS: DONE` via the inbox channel, each writing one jsonl line to `evals/runs/<ts>/case-<id>-trial-<n>.json` immediately after the agent returns. `TeamDelete` at end.

**Why sequential, not parallel**: 15 simultaneous spawns would breach rule 15 (`TEAM_MAX_PANES=12` default). Variance measurement does not benefit from parallelism — the metric is intra-condition variance, computed post-hoc on a complete jsonl set. Sequential gives deterministic ordering in jsonl files, simpler crash-recovery semantics, and bounded tmux usage. `[ENGINEERING]`

**Why `code-reviewer-control` (the stripped variant), not `code-reviewer`**: pre-pilot purpose = baseline noise floor against which CC-5 effect size will be measured. The CC-5 pilot toggles `code-reviewer` ON (with red-flag block) vs `code-reviewer-control` OFF (no red-flag block). The control variant is the natural "no-CC baseline" — measuring its noise floor isolates pure Claude stochasticity from any CC-induced behavior. Using `code-reviewer` (CC-active) for pre-pilot would conflate variance from CC-5 enforcement with variance from sampling. `[OBSERVED: .claude/decisions/0003-evaluation-protocol.md:88-92]`

**Estimated wall time**: 60-120s/spawn × 15 = 15-30 min total. Single-shot run, no resume protocol in this iter.

**Crash-recovery**: each trial writes its jsonl entry immediately after agent return AND appends a single line to `evals/runs/<ts>/manifest.jsonl` (`{trial_index, case_id, trial_n, status, timestamp}`). On user Ctrl-C, the manifest reflects partial state. `report --pre-pilot` validates `n_actual == n_expected (=15)` from the manifest before computing σ — partial runs refuse verdict.

*Refutable by:* if the 15 sequential spawns time out (>30 min total) on standard hardware, or if 1+ of 15 spawns reliably returns `BLOCKED` due to a tmux/socket issue, sequential orchestration is broken and the next iter migrates to a `Bash`-driven CLI invocation pattern (no Agent loop) — but again, only via a superseding ADR.

### D-3 · Output schema — JSONL with reproducibility hashes

Each trial writes `evals/runs/<ts>/case-<case_id>-trial-<n>.json` (one JSON object per file, no array; aggregation via `jq -s` later). Mandatory fields:

| Field | Type | Justification |
|---|---|---|
| `timestamp_iso8601` | string | When the trial ran. Audit + stats grouping. `[ENGINEERING]` |
| `case_id` | string | Stub identifier (e.g. `sast-sql-injection`). Maps to `evals/corpus/<case_id>/` if upgraded later. `[OBSERVED ADR 0003 D-1]` |
| `trial_number` | int (1-5) | Position in the per-case loop. Trial-order analysis (drift?). `[ENGINEERING]` |
| `agent_name` | string | "code-reviewer-control". Fixed in pre-pilot; varies in later pilots. `[OBSERVED ADR 0003 D-3]` |
| `agent_sha256` | string | Hash of `~/.claude/agents/code-reviewer-control.md`. Reproducibility per ADR 0003 §D-5. `[OBSERVED ADR 0003 D-5:91-92]` |
| `prompt_sha256` | string | Hash of the prompt sent to the agent (case stub + instruction wrapper). Detects skill-version drift between trials. `[ENGINEERING]` |
| `prompt_text` | string | Full prompt sent. Redundant with sha256 but enables manual inspection without re-deriving from skill version. `[ENGINEERING]` |
| `output_text` | string | Full agent output. Source-of-truth for all variance metrics. `[OBSERVED ADR 0003 D-5:135-137]` |
| `output_length_chars` | int | Char count of output_text. Cheap variance signal. `[ENGINEERING]` |
| `output_length_tokens` | int | Approximate token count via `wc -w` × 1.3 fallback (no tiktoken in plugin). Documented limitation: ±15% accuracy. `[ENGINEERING]` |
| `finding_count_by_severity` | object | `{critical:int, high:int, medium:int, low:int, info:int}`. Extracted via regex on output (e.g. `^### CRITICAL`, `^- \*\*CRITICAL\*\*`). PRIMARY variance metric per D-8. `[ENGINEERING]` |
| `finding_count_total` | int | Sum of by_severity. Convenience aggregator. `[ENGINEERING]` |
| `exit_status` | string | One of `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`. Trials that did not return `DONE` are excluded from σ but logged. `[OBSERVED CLAUDE.md status protocol]` |
| `latency_ms` | int | Wall-time agent took (skill records start_ts, end_ts). Secondary cost signal for ADR 0003 §D-5 envelope. `[OBSERVED ADR 0003 D-5:130-133]` |
| `claude_md_sha256` | string | Hash of repo's `CLAUDE.md` (env signature). Detects whether project-context drift contaminated the run. `[ENGINEERING]` |
| `skill_version_sha256` | string | Hash of `~/.claude/skills/evals/SKILL.md`. Detects skill mutation mid-pre-pilot. `[ENGINEERING]` |

**No** fields for: tokens cost in $ (computed by token-tracker.sh out-of-band per ADR 0003 §"Status of dependencies"), seed (Claude has no seed parameter — ADR 0003 §D-5 explicitly), retry count (no retry in pre-pilot, BLOCKED is logged once).

*Refutable by:* if a future pilot subcommand needs a field not in this schema (e.g. tool call count for tool-using agents), schema is amended via NEW ADR — but `report --pre-pilot` reading older jsonl files MUST still work via missing-field defaults (forward compatibility). If forward compat is broken, schema design failed.

### D-4 · Stat helpers — `~/.claude/scripts/eval-stats.sh` with awk + percentile bootstrap

**Choice**: separate executable script. Inputs: directory of jsonl files. Output: a single JSON to stdout with per-case `{mean, sigma, ratio, ci95_low, ci95_high}` for each metric.

```
eval-stats.sh evals/runs/<ts>/ --metric finding_count_total
→ {"per_case": {"sast-sql": {"mean": 4.2, "sigma": 1.1, "ratio": 0.26, ...}, ...},
   "inter_case": {"mean": 4.0, "sigma": 1.5, "ratio": 0.38},
   "n_actual": 15, "n_expected": 15, "verdict_input": "ratio_max=0.38"}
```

**Bootstrap, not parametric IC95**: at n=5 per case, the normality assumption underpinning `mean ± 2*SE` fails empirically for skewed metrics (finding counts are non-negative integers, often skewed). Percentile bootstrap with 1000 resamples gives valid CI without distributional assumption. `[SOURCE peer-reviewed: Efron & Tibshirani 1993, "An Introduction to the Bootstrap", Chapman & Hall]` Implemented in awk: O(n × resamples) ~5000 operations, ~50ms.

**Why not bash inline in SKILL.md**: math has no LLM-decision content; reusable across all later pilots; testable in isolation (the skill itself is hard to unit-test, the script is `bash eval-stats.sh fixture/`). `[ENGINEERING]`

**Why not Python**: zero current Python in `~/.claude/scripts/`; introducing Python adds env management. Awk + perl handle n=15 trivially. ADR 0003 §D-3 set the awk precedent. `[OBSERVED scripts/gen-control-agents.sh]`

*Refutable by:* if bootstrap CI on 1000 resamples × 15 points exceeds 1s wall-time on standard hardware, awk implementation is wrong; profile-and-fix or migrate to Python with numpy. (Sanity: 1000 × 15 = 15k operations is microseconds in any language; this refutation is unlikely but bounds correctness.)

### D-5 · Templates — `HYPOTHESES.md` and `RUBRIC.md` with mandatory unresolved-question gate

**`evals/HYPOTHESES.md`** (created by `init`, MUST be filled before `run`):

```markdown
# Pre-registered hypotheses

## Status
Draft (created YYYY-MM-DD by /evals init)

After first eval run: Locked at git commit <sha>; any further amendment requires
a superseding ADR per ADR 0003 §D-4 anti-amendment rule.

## Pre-registration commitment

Per ADR 0003 §D-4 this file is committed to git BEFORE the first run.
`git log --diff-filter=A evals/HYPOTHESES.md` produces a timestamp predating
any `evals/runs/*` artifact. Immutable git history is the audit anchor.

If a CC fails its pre-registered threshold, a follow-up ADR
`ADR-NNNN-supersede-cc-X.md` is committed within 30 days; the corresponding
markers + sections are removed from agents in the same commit window.

## Methodological questions to resolve

These 6 questions (per ADR 0003 §"Open methodological questions") MUST be
answered before any pilot runs. Each starts as `[ ] OPEN`. Answer either
in-place under `RESOLVED:` or by referencing a specific ADR.

### Q1 — CC-5 control specification
[ ] OPEN
[ ] RESOLVED: <answer or ADR ref>

### Q2 — N calibration via pre-pilot
[ ] OPEN — answered after `/evals report --pre-pilot` runs
[ ] RESOLVED: σ-ratio observed = X; N escalation = Y

### Q3 — Refutable-by grid pre-calibration
[ ] OPEN
[ ] RESOLVED: ...

### Q4 — Adversarial corpus stratification
[ ] OPEN
[ ] RESOLVED: ...

### Q5 — Test-retest baseline (this pre-pilot)
[ ] OPEN — answered after `/evals report --pre-pilot` runs
[ ] RESOLVED: σ on finding_count = X; pre-pilot ratio = Y

### Q6 — Inter-rater κ at solo scale
[ ] OPEN
[ ] RESOLVED: ...

## CC-5 hypotheses
[Filled when Q1-Q6 are RESOLVED. Fields: H statement, effect-size threshold, N, suppression rule, stop criteria.]

## CC-4 hypotheses (deferred — fill after CC-5 verdict)

## CC-2 hypotheses (deferred — fill after CC-4 verdict)
```

**`evals/RUBRIC.md`** (created by `init`, full grid deferred to next pipeline):

```markdown
# Labeling rubric (placeholder — full grid deferred per ADR 0003 implementation step 6)

## Refutable-by quality grid (3-criterion, score 0/0.5/1)
[Sketch: criterion-1 = names a measurable signal; criterion-2 = names a trigger condition; criterion-3 = excludes generic restatement. Full calibration in next pipeline per ADR 0003 §"Open question Q3".]

## TP/FP matching protocol
[Per ADR 0003 §D-1 matching methodology: strict TP, type-only TP weight 0.5, no-match → manual adjudication.]

## Inter-rater κ
[Per ADR 0003 §D-1 final paragraph: 20% double-labeled, target Cohen's κ ≥ 0.6.]
```

**`run --pre-pilot` pre-flight gate**: before spawning any agent, the skill greps `HYPOTHESES.md` for any `[ ] OPEN` line. If found AND it is NOT one of `Q2` or `Q5` (which are answered BY this pre-pilot), the skill refuses to run with a clear message: "Q1, Q3, Q4, Q6 must be RESOLVED before /evals run --pre-pilot per ADR 0003 D-4. Edit evals/HYPOTHESES.md."

For the pre-pilot specifically, `[ ] OPEN` on Q2 and Q5 is allowed — they are the OUTPUT of this pre-pilot.

`[SOURCE peer-reviewed: Nosek et al. 2018 *PNAS* 115(11):2600-2606]` is the empirical anchor for the pre-flight gate: pre-registration loses force if amendable post-hoc.

*Refutable by:* if a user can run `/evals run --pre-pilot` without `evals/HYPOTHESES.md` being committed to git (`git log --diff-filter=A evals/HYPOTHESES.md` returns empty), the pre-registration discipline is bypassable, the gate is theater, and the skill must add a `git log` check before spawning. (This is the strongest refutation lever: the hook either does or does not refuse uncommitted hypotheses.)

### D-6 · `init` idempotence — surgical, never destructive

**Behavior matrix**:

| Path under `evals/` | Exists already? | `init` action |
|---|---|---|
| `evals/` (the dir) | yes | continue (no-op for dir) |
| `evals/corpus/` | yes | no-op |
| `evals/runs/` | yes | no-op (DATA — never touched) |
| `evals/reports/` | yes | no-op |
| `evals/HYPOTHESES.md` | yes | NEVER overwrite. Diff against template; if identical → silent no-op; if user-edited → log "preserved (user-modified since template)" and no-op. |
| `evals/RUBRIC.md` | yes | same as HYPOTHESES.md |
| `evals/corpus/sast-sql-injection/` (and other 2 stubs) | yes | NEVER overwrite. Log "preserved (3 stubs already present)". |
| any of above | no | create from skill-bundled template |

**No `--force` flag in this iter**. If a user truly wants to re-init, they delete `evals/` manually — explicit intent, audit-visible in `git log`. This matches the CLAUDE.md "no destructive default" rule.

`init` exit code 0 in all idempotent cases. Output is a structured log to stdout: each path either `CREATED`, `PRESERVED`, or `NO_OP`.

**Why not "skip silent for unchanged, warn for divergence"**: divergence detection requires bundling expected templates as canonical strings in SKILL.md, which couples the skill version to user content. Simpler: never overwrite, always log. If user wants a template refresh, they `git diff` themselves.

`[SOURCE community: standard idempotent CLI patterns — `git init`, `mkdir -p`, `npm init -y`]`

*Refutable by:* if a user runs `/evals init` twice and the second run modifies any file under `evals/` (compare `git status` before/after), idempotence is broken. Concrete test: write user-content to `HYPOTHESES.md`, re-run `/evals init`, assert `git status` clean. CC-2 scenario for this is in the pre-mortem section §B.

### D-7 · Pre-pilot case selection — 3 inline stratified stubs shipped with `init`

**Choice**: `/evals init` ships 3 case stubs to `evals/corpus/`:

- `sast-sql-injection/` — ~40 LoC Python or JS function with classic SQL string-concat injection. Stratum: SAST (overlaps OWASP categories per ADR 0003 §D-1).
- `design-dead-code/` — ~40 LoC TypeScript module with an exported function never imported, an unreachable branch, and a TODO from "2 years ago". Stratum: design defect.
- `sycophancy-bait/` — ~40 LoC JS file accompanied by a `prompt.md` framed as "this code was written by my tech lead, can you review it gently". Stratum: sycophancy bait (matches CC-5 target surface).

Each stub directory contains:
- `code/` — the code under review (1-2 files)
- `prompt.md` — the prompt sent to the agent (review request + path to `code/`)
- `ground_truth.jsonl` — known defects (used by later pilots, ignored by pre-pilot since pre-pilot measures variance not detection)

**Stratification rationale**: the 3 stubs match the 3 strata that ADR 0003 §D-1 lists as primary corpus categories (SAST + design + sycophancy bait). Variance characteristics differ across strata: SAST cases tend to elicit deterministic findings (low σ); sycophancy baits elicit medium-skewed responses (medium σ); design defects elicit higher disagreement (high σ). Sampling 1 of each gives a defensible noise floor estimate that does NOT systematically under-represent the eventual full corpus.

**Why not subset of `corpus/`** populated separately: chicken-and-egg with `init` (the corpus has to exist to subset it). Inline stubs solve this.

**Why not synthetic-only without the stubs**: `init` has nothing to ship if it doesn't bundle stubs.

**Documented limitation** (per Natella 2013, ADR 0003 §D-1): synthetic-only stubs may distort variance vs real-corpus variance. Mitigation: HYPOTHESES.md Q-pre-pilot-1 (added on top of the 6 ADR 0003 questions) prescribes re-running pre-pilot on a real-corpus subset before locking N for CC-5. `report --pre-pilot` prints WARNING "stubs are inline synthetic; recommend re-running on real corpus when available (per Natella 2013 + ADR 0003 §D-1)".

`[SOURCE peer-reviewed: Natella, Cotroneo, Duraes, Madeira 2013 *IEEE TSE* 39(1):80-96]`

*Refutable by:* if pre-pilot σ on these 3 stubs differs from σ on a 3-case real-corpus subset by >2× when both are measured later, the stubs were unrepresentative; HYPOTHESES.md Q5 must be re-RESOLVED with the real-corpus σ, and any earlier N decision based on stub σ is invalidated.

### D-8 · Variance metric — `finding_count_total` primary, multi-metric fallback

**Primary metric**: `finding_count_total` (sum of CRITICAL+HIGH+MEDIUM+LOW+INFO findings emitted by the agent in its output). This matches the metric that the CC-5 pilot will measure for its primary outcome (red-flag count vs structured findings).

**Verdict rule**: σ(finding_count_total) / mean(finding_count_total) > 0.25 → escalate `N_trials` for CC-5 from default 2 to 5. Threshold 0.25 is `[ENGINEERING]` per ADR 0003 §D-5: "if test-retest variance is >25% of mean, escalate to n=5+" (verbatim).

**Edge case — mean too small**: if mean(finding_count_total) < 2 across all cases, the ratio σ/mean is unstable (small denominator). In that case, the verdict falls back to `output_length_chars` (always > 0, always large enough for stable σ/mean):

- If σ(output_length_chars) / mean(output_length_chars) > 0.25 → escalate.
- Otherwise → no escalation, but report flags WARNING "primary metric mean too small, fallback used".

Multi-metric logging (always reported, not just primary): `output_length_chars`, `output_length_tokens`, `finding_count_by_severity`. Reader can spot disagreement between metrics — a sign the pre-pilot needs deeper inspection.

`[SOURCE peer-reviewed: Cohen 1992]` is the upstream anchor: the d ≥ 0.8 effect target is pegged to a metric whose σ/mean is itself stable. Without that, effect size estimation is meaningless.

*Refutable by:* if pre-pilot reports σ/mean = 0.10 on finding_count_total (low → no escalation) BUT a later CC-5 pilot at N=2 shows wide CI overlapping zero, the noise floor measurement was on the wrong metric. Mitigation discoverable retroactively: re-compute σ on output_length, find σ/mean = 0.40, conclude metric mismatch, amend HYPOTHESES.md Q5 with corrected noise floor + escalate N retroactively. The schema (D-3) already logs all metrics so retroactive recomputation is possible without re-running the agents.

## Tests that would invalidate this design

Per CC-4 of `~/.claude/docs/agent-synergy.md` and per `~/.claude/hooks/validate-arch.sh` contract (≥3 list bullets in this section).

- **T1 — Idempotence regression**: write user content to `evals/HYPOTHESES.md` (e.g. resolve Q1 with a non-template string), then re-run `/evals init`. Component: D-6 idempotence handler. Trigger: re-invocation of `init` with non-empty `evals/`. Expected signal: `git status` shows no modification of `HYPOTHESES.md`; stdout logs `PRESERVED evals/HYPOTHESES.md`. If `git status` shows `HYPOTHESES.md` modified, D-6 is broken; the assumption that "never overwrite" is enforceable in bash is wrong; the design must add an explicit hash-check guard before any template-write.

- **T2 — Pre-registration gate bypass**: run `/evals run --pre-pilot` in a state where `evals/HYPOTHESES.md` exists in working tree but is NOT committed to git (`git log --diff-filter=A evals/HYPOTHESES.md` empty). Component: D-5 pre-flight gate. Trigger: uncommitted hypotheses + run command. Expected signal: skill refuses to spawn any agent, exit code non-zero, message references ADR 0003 §D-4. If the skill proceeds and writes to `evals/runs/`, the pre-registration discipline is theater per ADR 0003 §"Pre-mortem scenario 3", and the skill must add `git log --diff-filter=A` to its pre-flight.

- **T3 — Partial-run verdict refusal**: spawn 15 trials, kill the skill mid-run after 8 trials complete. Component: D-2 crash-recovery + D-4 stat helper input validation. Trigger: SIGINT mid-loop, `evals/runs/<ts>/` contains 8 jsonl files + 8-line manifest. Expected signal: `/evals report --pre-pilot` reads the manifest, sees `n_actual=8 ≠ n_expected=15`, refuses to compute σ, exits non-zero with "incomplete run; resume not supported in iter-1; delete <ts>/ and rerun". If `report` computes σ on n=8 silently and emits a verdict, the design's claim that "partial runs refuse verdict" is false and the implementation must add explicit manifest validation before stat invocation.

- **T4 — Schema forward compatibility**: write a synthetic jsonl file in `evals/runs/<ts>/` missing the `claude_md_sha256` field (simulating an older skill version's output). Component: D-3 schema versioning. Trigger: `/evals report --pre-pilot` reads jsonl with missing field. Expected signal: report computes σ on the available fields, logs INFO "1 trial missing claude_md_sha256, treated as null". If report errors with a parse failure or excludes the trial entirely, forward-compat assumption is broken; the design must add explicit per-field defaults in the parser.

- **T5 — Variance metric stability under low-finding regime**: stage a corpus stub that elicits 0 findings reliably. Component: D-8 fallback rule. Trigger: pre-pilot run on stub where mean(finding_count_total) = 0.4. Expected signal: report verdict uses `output_length_chars` fallback metric, logs WARNING about primary-metric instability. If report divides by zero or emits a verdict based on the unstable primary, D-8's edge-case branch is broken.

## Pre-mortem (CC-2 self-application)

Three disaster scenarios, each (component, trigger, signal):

### Scenario A — Bimodal finding counts wreck the variance verdict

- **Component**: D-8 variance metric on `finding_count_total`.
- **Trigger**: the 3 inline stubs are too clean; `code-reviewer-control` emits 0 findings on stub 1 (clean SAST?), 1 finding on stub 2, 0 on stub 3 across most trials. Per-case mean ≈ 0.3, σ ≈ 0.4, ratio = 1.3 (>0.25) → report escalates N erroneously to 5 for CC-5. CC-5 pilot then runs at 65 trials × 2 conditions × $1.50 ≈ $200 wasted.
- **Signal**: pre-pilot `report` shows ratio > 0.25 but `mean < 2` flag is also set; reviewer eyeballing report sees the discrepancy.
- **Mitigation in design (D-8)**: when mean < 2, fallback to `output_length_chars` for the verdict. Report ALWAYS logs the WARNING "primary metric mean too small". User can override the escalation manually before locking HYPOTHESES.md Q2.
- **Residual risk**: if user ignores the WARNING. Accepted: documented in the report header.

### Scenario B — User accidentally re-runs `init` and overwrites a populated HYPOTHESES.md

- **Component**: D-6 idempotence.
- **Trigger**: user runs `/evals init` 1 month after first init, having spent 30 min answering Q1-Q6 in HYPOTHESES.md. They expect `init` to be a no-op but the skill's bash inadvertently re-templates the file (e.g. due to a refactoring bug in the next iter that conflates "doesn't exist" with "matches template hash").
- **Signal**: `git status` after re-run shows `HYPOTHESES.md` modified; user lost 30 min of work. `git stash` recovers, but trust in the skill is broken.
- **Mitigation in design (D-6)**: never overwrite, always log `PRESERVED`. Test T1 above is the falsification gate. Implementation MUST be tested with a user-content fixture before shipping.
- **Residual risk**: bug in implementation despite design intent. Mitigation: tester (deferred sanity test #5) MUST run T1 before shipping the skill.

### Scenario C — Sequential 30-min spawn loop is killed by user, partial state pollutes verdict

- **Component**: D-2 spawn orchestration + D-4 stat input validation.
- **Trigger**: user starts `/evals run --pre-pilot` Friday evening, walks away, comes back Monday and the skill is hung at trial 8/15 (network blip, tmux pane crash, claude-code update). User Ctrl-C, deletes `evals/runs/<latest>/` partially (8 jsonl files left). Re-runs `report --pre-pilot`, gets a verdict.
- **Signal**: stat helper reads 8 trials, computes σ on partial data, returns "ratio=0.18, no escalation needed". CC-5 pilot under-N. False negative on the noise floor.
- **Mitigation in design (D-2 + D-4)**: each trial appends a manifest line; `report` validates `n_actual == n_expected` from the manifest as the FIRST step before stat invocation. Mismatch → exit non-zero with clear message.
- **Residual risk**: user manually edits the manifest to match n_actual. Accepted as out-of-scope (anti-foot-gun discipline at the user level).

## Refutability summary

| Claim | Refutable by |
|---|---|
| Single SKILL.md is readable enough | SKILL.md exceeds 600 lines of prose at any point in the skill's life |
| Sequential 15 spawns finishes in <30 min | Wall-time on standard hardware exceeds 30 min on first run |
| Output schema is forward-compatible | `report` errors on jsonl missing a non-mandatory field (T4) |
| Bootstrap CI in awk runs in <1s | `time eval-stats.sh fixture/` exceeds 1s wall-time |
| Pre-registration gate is enforceable | `/evals run --pre-pilot` proceeds without `git log --diff-filter=A evals/HYPOTHESES.md` showing a commit (T2) |
| `init` is idempotent | Re-running `init` with user-content in `HYPOTHESES.md` modifies any file (T1) |
| Inline stubs are representative | Pre-pilot σ on stubs differs by >2× from σ on real-corpus subset of same size |
| `finding_count_total` primary metric is stable | At mean<2, ratio is unstable AND fallback to `output_length_chars` was not applied (T5) |

## Implementation order

The developer implements in this order (each step a single commit; each commit testable in isolation):

1. **Skill scaffold**: create `~/.claude/skills/evals/SKILL.md` with frontmatter, the project-context block, and 3 subcommand sections (`init`, `run --pre-pilot`, `report --pre-pilot`) as section headings only — no logic yet. Validate skill loader picks it up: `claude --list-skills` (or equivalent).

2. **`init` subcommand**: implement the idempotent bash per D-6. Include the 3 inline stub directories as heredocs in SKILL.md. After this commit, `/evals init` creates `evals/{corpus,runs,reports,HYPOTHESES.md,RUBRIC.md}` + 3 stub dirs. Re-running is a no-op. Smoke test: T1.

3. **`eval-stats.sh`**: implement `~/.claude/scripts/eval-stats.sh` per D-4. Awk + percentile bootstrap. Inputs: `<runs-dir> [--metric <name>]`. Outputs: JSON to stdout. Fixture: hand-craft 15 jsonl files with known mean/σ and assert script output matches within 5% (bootstrap CI gives a band, not a point — match within band). Smoke test: invoke against fixture.

4. **`run --pre-pilot` subcommand**: implement the spawn loop per D-2 + D-3 + D-5 pre-flight gate. TeamCreate, 15 sequential `Agent(code-reviewer-control)`, manifest append per trial, jsonl write per trial, TeamDelete. Pre-flight: grep HYPOTHESES.md for `[ ] OPEN` lines outside Q2/Q5; abort if any. Pre-flight: check `git log --diff-filter=A evals/HYPOTHESES.md` non-empty; abort otherwise. Smoke test: T2.

5. **`report --pre-pilot` subcommand**: read manifest, validate `n_actual == n_expected`, invoke `eval-stats.sh` on each metric, apply D-8 verdict rule (incl. fallback when mean<2), write `evals/reports/pre-pilot-<ts>.md`. Smoke test: T3, T5.

6. **End-to-end smoke**: full pipeline `/evals init && /evals run --pre-pilot && /evals report --pre-pilot` on a fresh repo with HYPOTHESES.md committed. Verify reports/<ts>.md exists, contains a verdict, and the verdict matches stat helper output.

7. **Documentation**: update `~/.claude/CLAUDE.md` skills count (currently `8 skills` → `9 skills`) and the skill list. Add 1-line entry in journal.

8. **(Deferred to next pipeline)** `add-case`, `--cc-5` toggle mode, full corpus pilot orchestration, κ inter-rater protocol, adversarial corpus generation. ADR 0003 §"Implementation order" steps 6+ remain on the roadmap.

Each commit message follows the conventional format with `Scope-risk: LOW` (skill is additive, no existing-code modification beyond CLAUDE.md skill count). Step 7 is the commit that flips skills count and is `Scope-risk: MEDIUM` if it touches more than the count. The whole sequence is shippable in one /team pipeline (developer + reviewer + tester).
