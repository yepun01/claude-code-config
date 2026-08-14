# ADR 0003 — Empirical evaluation protocol for cross-cutting protocols (`/evals`)

## Status
Proposed (2026-04-29). Implementation pending. Partially superseded by [0011 §D-4](0011-eval-metric-construct-validity-rule.md) (2026-05-02) — primary-metric pre-registration clause replaced by mention-only fixture validation rule. Other clauses (D-1 corpus, D-2 sequence, D-3 toggle, D-5 reproducibility) unchanged.

## Context

ADR 0002 ships CC-2/CC-4/CC-5 grounded on peer-reviewed sources from human domains (firefighters, surgeons, decision researchers). The transfer step "human evidence → LLM agent on code" is `[INTUITION]` — no paper has measured the LLM-specific effect.

Without empirical validation the plugin is faith-based: every claim "CC-X improves quality" rests on extrapolation. CC-4 itself demands falsifiability of every CRITICAL/HIGH finding; the same standard applied to CC-2/CC-4/CC-5 themselves requires measurable signal of effect.

This ADR commits to a measurement protocol with **pre-registered hypotheses**, **suppression-on-null** commitment, and an **independent corpus anchor** to prevent author-bias inflation.

### Inputs

3 deep-analyzer reports (parallel pipeline 2026-04-28, team `evals-design-2026-04-28`):
- `answer-corpus.md` — corpus origin analysis
- `answer-cc-order.md` — CC test sequencing
- `answer-toggle.md` — A/B mechanism analysis

### Evidence base (WebFetch-verified at write time by the analyzers)

| # | Source | Finding | Marker |
|---|---|---|---|
| 1 | Cohen 1992 *Psychol Bull* 112(1):155-159 — "A Power Primer" | At α=.05, power=.80: effect d=0.8 needs n≈26/group; d=0.5 needs n≈64; d=0.2 needs n≈393. Below this, null is sub-power-determined. | `[SOURCE peer-reviewed]` |
| 2 | Simmons, Nelson & Simonsohn 2011 *Psychol Sci* 22(11):1359-66 — "False-Positive Psychology" | Researcher degrees of freedom (optional stopping, condition selection) inflate Type I error to ~60%. Disclosure-based 6-author requirement is the proposed solution. | `[SOURCE peer-reviewed]` |
| 3 | Nosek, Ebersole, DeHaven & Mellor 2018 *PNAS* 115(11):2600-2606 — "The preregistration revolution" | Pre-registration of analysis plans before data collection separates confirmatory from exploratory analysis. | `[SOURCE peer-reviewed]` |
| 4 | Natella, Cotroneo, Duraes, Madeira 2013 *IEEE TSE* 39(1):80-96 — "On Fault Representativeness of Software Fault Injection" | Up to **72% of seeded faults are NOT representative** of residual real faults. Synthetic-only corpora systematically distort precision/recall measurement. | `[SOURCE peer-reviewed]` |
| 5 | Just, Jalali & Ernst 2014 *ISSTA* — "Defects4J: A Database of Existing Faults to Enable Controlled Testing Studies" | Real-bug corpus from Java projects with fix commits as ground-truth oracle. Methodology pattern for line-bucket matching. | `[SOURCE peer-reviewed]` |
| 6 | OWASP Benchmark Project v1.2 (https://owasp.org/www-project-benchmark/) | 2,740 test cases over 11 CWE categories with TP/FP labels. Public, frozen, near-zero author bias. | `[SOURCE community]` |
| 7 | Just, Jalali, Inozemtseva, Ernst, Holmes, Fraser 2014 *FSE* — "Are Mutants a Valid Substitute for Real Faults?" | Mutational testing correlates with real-fault detection for *test-suite effectiveness* — extrapolation to *code-review finding generation* unwarranted. | `[SOURCE peer-reviewed]` (rules out mutational testing as primary corpus) |
| 8 | Landis & Koch 1977 *Biometrics* 33(1):159-174 — "The Measurement of Observer Agreement for Categorical Data" | Cohen's κ ≥ 0.6 = "moderate-to-substantial" inter-rater agreement. Engineering threshold for rubric reliability. | `[SOURCE peer-reviewed]` |
| 9 | Jimenez, Yang, Wettig, Yao, Pei, Press, Narasimhan 2024 *ICLR* arXiv:2310.06770 — "SWE-bench: Can Language Models Resolve Real-World GitHub Issues?" | Real-issue benchmark for LLM code work. Cited as alternative external benchmark; not primary because focus is fix-generation, not finding-detection. | `[SOURCE peer-reviewed]` |

## Decision

### D-1 · Corpus design — Hybrid (synthetic + OWASP anchor + real)

**Composition** (13-17 cases total, ~6-10h initial setup, ~1h/quarter maintenance):
- **8-10 synthetic seeded** (~30-50 LoC each): 3 SAST cases overlapping OWASP categories + 2 design defects (dead code, premature abstraction) + 2 sycophancy baits + 1 clean calibration (FP rate baseline) + 1 borderline severity
- **3-5 OWASP Benchmark v1.2 servlets** as external anchor — runs through identical harness; divergence on overlap categories triggers redesign of the synthetic core
- **2 real diffs** from this plugin's own `git log` (reviewer-caught bugs) — sanity check that the corpus isn't a museum piece

**Why hybrid, not synthetic-only** `[SOURCE: Natella et al. 2013]`: synthetic-only corpora can distort precision/recall by up to 72% relative to residual real faults. The OWASP anchor is the bias antidote — if the synthetic core diverges from a public corpus on overlapping types, the synthetic is mis-designed, not CC-4 mis-measured.

**Adversarial corpus generation** (mitigation against author bias): 50% of defects generated by a separate Opus-class LLM with a prompt that does NOT mention CC-4; the author writes the other 50%. Per-source detection rates published. `[INTUITION]` — no peer-reviewed paper validating this exact pattern, but a direct application of blind labeling discipline.

**Matching methodology** (3-tier per OWASP TP/FP × Defects4J line-bucket):
- **Strict TP**: same `type` AND `|finding.line - defect.line_start| ≤ 5` `[ENGINEERING: 5-line window]`
- **Type-only TP**: same `type` anywhere in same file → weight 0.5
- **No match**: candidate FP, but **manual adjudication required** (Natella distortion: agent may find a real residual bug we didn't seed). Adjudicator marks `bonus_TP` vs `actual_FP`.

**Inter-rater reliability**: 20% of findings double-labeled, target Cohen's κ ≥ 0.6 `[SOURCE: Landis & Koch 1977]`.

**Schema** (`evals/corpus/<id>/`):
- `code/` — code under review
- `prompt.md` — what the agent receives
- `ground_truth.jsonl` — `{defect_id, file, line_start, line_end, type, severity, fix_hint}`
- `bonus_labels.jsonl` — adjudicated findings not in ground_truth (built incrementally)

*Refutable by:* if across 30 trials the inter-rater κ on Refutable-by quality falls below 0.5, OR if synthetic SAST findings diverge >20% from OWASP-anchor on overlapping types, the hybrid recommendation is invalidated and `/evals` falls back to external-only (OWASP) with reduced coverage scope.

### D-2 · Sequence — Staged CC-5 → CC-4 → CC-2

**Why this order**:
1. **CC-5 first = methodological derisk** `[INTUITION supported by ENGINEERING reasoning]`. Toggle, corpus, rubric, harness validate on the most mechanically-measurable CC. n=20 atteignable. If the infrastructure fails on CC-5, it cannot succeed on CC-4 or CC-2.
2. **CC-4 second** inherits the validated infrastructure, adds one new degree of freedom (Refutable-by quality rubric).
3. **CC-2 last** is most expensive to instrument (needs gold-standard senior review of disaster scenarios or multi-month materialization tracking). If CC-4/CC-5 are both invalidated, the pattern "meta-discipline on LLM output" doesn't transfer; CC-2 can be suspended without testing — net economy.

**Rejected alternatives**:
- **All three shallow** (1-2 cases per CC): familywise error ~14% at α=.05; sub-power multiplicative; no credible verdict possible. `[SOURCE: Simmons-Nelson-Simonsohn 2011]`
- **Adaptive** (data-dependent next): "choose next based on result" is the prototypical researcher degree of freedom inflating Type I; incompatible with light pre-registration. `[SOURCE: Simmons-Nelson-Simonsohn 2011]`
- **CC-4 first**: defensible, but methodological infra not yet derisked. CC-5 first is strictly dominant when infra readiness is uncertain.
- **CC-2 first**: most fragile theoretical extrapolation (human → LLM), highest "test-this-first-because-most-suspect" appeal — but measurement is hardest (gold-standard or long-tail); risk of suppressing a working CC by underpower exceeds risk of provisionally keeping it.

**Suppression criterion per stage** (pre-registered):
- d ≥ 0.8 + IC95 excludes 0 → **GARDE**, advance to next CC
- null + IC95 excludes d=0.5 → **SUPPRIME**, remove CC from plugin within 30 days
- IC95 includes d=0.5 → **UNDETERMINED**, document and escalate budget if stake warrants; do not auto-suppress

`[SOURCE: Cohen 1992]` floor: at n=20 cases × 2-3 trials per condition, only large effects (d ≥ 0.8) are reliably detectable. The protocol acknowledges this limit explicitly via the UNDETERMINED bucket — pre-committing to "absence of evidence ≠ evidence of absence" when underpowered.

*Refutable by:* if the CC-5 pilot (n=10) shows toggle-ON / toggle-OFF producing identical red-flag counts (i.e. the corpus does not naturally elicit sycophantic phrases), CC-5 has no measurable surface, methodological derisk fails, and the protocol pivots to CC-4 first with corpus redesign to elicit medium-quality code reviews where red-flags emerge naturally.

### D-3 · A/B toggle mechanism — Generated control sub-agents (markers + autogen)

**Mechanism**:
1. **Markers**: insert `<!-- CC-START id=CC-X -->` ... `<!-- CC-END id=CC-X -->` HTML comments around each CC block in the 8 CC-bearing agents (one-shot edit ~30 min). HTML comments are syntactically inert in markdown rendering; the LLM treats them as plain text, but the autogen script can pattern-match them.
2. **Autogen script** `scripts/gen-control-agents.sh`: reads `agents/X.md`, strips marked blocks, writes `agents/X-control.md`. Idempotent.
3. **Pre-commit hook** auto-regenerates `*-control.md` whenever the corresponding `*.md` is staged for commit. Drift = 0 by construction.
4. **Spawn**: lead calls `Agent(subagent_type=X)` for condition A or `Agent(subagent_type=X-control)` for condition B.
5. **Reproducibility**: `metrics.jsonl` logs `sha256(agents/X.md)` + `sha256(agents/X-control.md)` per run — exact prompt version pinnable.

**Setup ~2h, ongoing ~0.**

**Rejected alternatives**:
- **Env var `EVAL_NO_CC=1`**: `[INTUITION]` placebo / Hawthorne confound — agent sees CC text in context AND meta-instruction to ignore. Tokens consumed, attention biased. Mesure invalide.
- **Brief prepend "ignore CC-X"**: same confound + violates rule 19 (5 mandatory brief sections — instruction-to-ignore is a hidden 6th section).
- **Dual tree manual**: drift quasi-guaranteed at solo-senior cadence; ~50 min/week propagation cost.
- **Git branch `eval-control`**: rebase conflicts on every CC modification; race conditions with active sessions reading `agents/*.md`.
- **PreToolUse wrapper file-swap**: race conditions on parallel spawns (file modified mid-read).
- **Stripped sub-agents manuels**: same drift as dual tree.

**Migration paths** if iter-1 doesn't hold:
- If regex-based stripping becomes fragile (multi-level sections, edge cases) → migrate to AST markdown parser (e.g., `mistletoe` Python or `remark` JS) extracting by heading IDs.
- If ablation-fine-grain is needed (CC-2 only, CC-4 only, CC-5 only, combos = 7 variants) → generator produces a matrix; each variant = subagent_type encoded as `<agent>-cc<bitmap>` (e.g., `code-reviewer-cc010` for CC-4 only).
- If full eval framework is needed → export each `<subagent_type, sha256>` to a versioned manifest YAML separate from the plugin repo, indexable by external eval runner.

*Refutable by:* if after 2 weeks of usage the autogen script produces ≥1 case of malformed prompt (orphaned references to stripped CC blocks, broken output format) that passes pre-commit hooks and pollutes an eval batch — the mechanism has a latent bug-mode and falls back to dual-tree manual with monthly re-evaluation.

### D-4 · Pre-registration + suppression commitment

**Pre-registration file**: `evals/HYPOTHESES.md` committed to git BEFORE first agent run. Contents:
- Per CC: primary hypothesis (e.g., "CC-5 reduces red-flag count by ≥30% on the corpus")
- Effect-size threshold (d ≥ 0.8)
- N (cases × trials × conditions)
- Suppression rule (verbatim from D-2)
- Stop criteria

**Verifiability**: `git log --diff-filter=A evals/HYPOTHESES.md` produces a timestamp predating any `evals/runs/*` artifact. Immutable git history is the audit anchor.

**Suppression follow-through**: if a CC fails its pre-registered threshold, a follow-up ADR `ADR-NNNN-supersede-cc-X.md` is committed within 30 days, and the corresponding markers + sections are removed from agents in the same commit window. The README is updated to reflect the empirical state. No carve-outs, no "one more iter".

*Refutable by:* check `git log -- evals/ agents/ docs/` 60 days after a null pilot. If CC-X is still mentioned in agent prompts and verdict-protocol.md without a superseding ADR, the suppression discipline failed; the entire eval protocol is theater.

### D-5 · Reproducibility & cost projection

**Trial multiplier**: Claude has no seed parameter. Same prompt → variable outputs. Pilot at n=2 trials per (case, condition); if test-retest variance (run-to-run delta on identical input) is >25% of mean, escalate to n=5+ at the cost of 2.5× total runs.

**Cost projection** (indicative `[ENGINEERING]`):
- CC-5 pilot: 13 cases × 2 trials × 2 conditions × ~$1/run ≈ $52
- CC-4 deep: 17 cases × 5 trials × 2 conditions × ~$1.50/run ≈ $255
- CC-2 (if reached): cost dominated by gold-standard human review, not LLM compute

Total budget envelope `[ENGINEERING]`: ~$500-1500 across the 3 stages.

**Trial logging**: every run produces `evals/runs/<timestamp>/<case_id>-<condition>-<trial>.json` with full prompt + output + metrics. Append-only.

## Consequences

### Positive
- The plugin's central epistemic claim (CC-X improves quality) becomes measurable, not faith-based.
- Suppression-on-null commits to honest failure modes — the plugin can shrink based on evidence, not just grow.
- The eval infrastructure (corpus, toggle, harness) is reusable for future CC additions or for cross-model adversarial review (deferred from earlier discussions).
- Public adoption gains credibility: users can replicate the eval and verify CC-X holds for their use case.

### Negative
- Setup cost: ~10-15h initial + ongoing maintenance (~1h/quarter on corpus + occasional rubric calibration).
- Token budget: ~$500-1500 across 3 CC pilots.
- Risk of UNDETERMINED verdicts at small N — the protocol explicitly accepts this rather than over-claiming.
- The autogen mechanism introduces a code-generation step in the agent build pipeline; bugs in the generator can corrupt eval batches (mitigated by the pre-commit hook running diff-hashes pre/post).

### Neutral / open
- CC-2 measurability remains the hardest problem. If CC-5/CC-4 succeed but CC-2 cannot be feasibly tested at affordable cost, the protocol explicitly documents CC-2 as "kept on theoretical grounding alone" rather than silently leaving it untested. Reader transparency over false rigor.

## Pre-mortem (CC-2 self-application)

Imagine `/evals` ships and 6 months later the eval protocol is itself revealed as theater. The 3 most plausible disaster scenarios, each named per (component, trigger, signal):

1. **Component**: synthetic corpus generator. **Trigger**: 100% of synthetic defects authored by the same person who designs CC-4. **Signal**: at first eval run, CC-4 toggle ON shows d=2.0 effect — way too high — because the corpus pattern-matches CC-4's own heuristics.
   - **Mitigation**: adversarial corpus generation (D-1) — 50% of defects authored blind to CC-4. If d>1.5 observed, pause and audit corpus generation prompts for leakage.

2. **Component**: marker-based autogen script. **Trigger**: an agent file is edited with a CC section that spans across an unmarked transition. **Signal**: pre-commit hook regenerates `*-control.md`, but a residual reference to CC-2 remains in the control's output format template — the control agent emits `*Refutable by:*` lines despite supposedly having no CC-4. Detection: hash-diff between expected stripped output and actual stripped output flags the orphan reference.
   - **Mitigation**: pre-commit hook runs an additional check that no `Refutable by:` / `pre-mortem` / `red-flag` keywords survive in `*-control.md`. If they do, abort commit.

3. **Component**: pre-registration discipline. **Trigger**: CC-5 pilot returns null at d=0.3. **Signal**: 60 days later, `git log -- agents/` shows no superseding ADR; CC-5 sections are still in 3 agent prompts; the README still cites Jetzen 2024. The plugin has silently preserved a falsified protocol.
   - **Mitigation**: the suppression commitment in D-4 is monitored by an external 60-day cron check that reads `evals/runs/` for any null verdicts and greps `agents/` for the corresponding CC keyword; mismatch triggers a journal entry "**SUPPRESSION OVERDUE**". If the user dismisses the journal entry without acting, that itself is the falsification of the eval protocol's credibility.

These scenarios are not hypothetical risks invented to satisfy CC-2 — each matches a specific failure mode flagged by the deep-analyzers or made plausible by the existing plugin's iter-3 fabrication history.

## Refutability summary

| Claim | Refutable by |
|---|---|
| Hybrid corpus reduces author-bias artifact | `evals/runs/` shows synthetic findings diverge >20% from OWASP-anchor on overlapping types over 30 trials |
| Staged CC-5 → CC-4 → CC-2 minimizes p-hacking | Inspection of `evals/HYPOTHESES.md` git history shows ≥1 amendment after data collection began |
| Generated control sub-agents = zero drift | `git diff agents/code-reviewer.md agents/code-reviewer-control.md` reveals divergence beyond the CC blocks |
| Pre-registration enforces suppression | 60 days post-null-verdict, the plugin still ships the falsified CC without a superseding ADR |
| Cost stays within ~$1500 envelope | `evals/runs/` token-tracker shows >$2000 for CC-5+CC-4+CC-2 combined |
| Inter-rater κ ≥ 0.6 on Refutable-by quality | Double-labeling on 20% sample yields κ < 0.5 across 30 findings |

## Status of dependencies

- **ADR 0002** (CC-2/CC-4/CC-5 design): unchanged. ADR 0003 measures, does not redefine.
- **CC-1 BFP** and **CC-3 multi-persona** (deferred from ADR 0002): out of scope for this ADR — measurement comes only after design ships.
- **`token-tracker.sh`** hook: reused for cost tracking; no modification.
- **`block-pollution-files.sh`** hook: extended in implementation phase to allow `agents/*-control.md` (otherwise the autogen would be blocked).

## Open methodological questions (deferred to `evals/HYPOTHESES.md` at implementation)

These questions surfaced during ADR drafting and are deferred — not closed — to the moment `evals/HYPOTHESES.md` is committed. Each MUST be answered explicitly before the first eval run.

1. **CC-5 control specification** — `*-control` agents currently have NO red-flag instruction at all (clean strip). Open: should the control instead carry a NEUTRAL anti-bullshit checklist (different list of generic phrases) so the comparison isolates "the specific 9 phrases vs a generic checklist" rather than "any checklist vs none"? Decide before pilot.
2. **N calibration via pre-pilot** — n=2 trials/condition (CC-5) and n=5 (CC-4) are heuristic. Run a pre-pilot of 3 cases × 5 trials per condition first; measure intra-condition variance σ; if σ exceeds the d=0.8 effect target, escalate N until variance is detection-compatible.
3. **Refutable-by grid pre-calibration** — score 20 existing Refutable-by lines from prior `/team` outputs against the 3-criterion grid. If >70% of lines land at 0.5, the grid lacks discrimination; refine before the 170-line CC-4 pilot.
4. **Adversarial corpus stratification** — instead of 50/50 mixed across all cases, partition: 1/3 fully author-written, 1/3 fully blind-LLM-generated, 1/3 mixed. Per-stratum detection rates published. Distinguishes author-bias from LLM-bias.
5. **Test-retest baseline** — before any A/B comparison, run 3 cases × 5 trials × 1 condition (no toggle) and measure run-to-run output variance. This is the noise floor; any d below 1.5× σ_noise is indistinguishable from Claude stochasticity. Without this, every effect size estimate floats unanchored.
6. **Inter-rater κ at solo scale** — second labeler unspecified. Three options: (a) self at 1-week interval (intra-rater test-retest, weaker), (b) second LLM in labeling mode (different model/prompt to reduce shared bias), (c) accept solo limit and label it transparently in metrics. Pick before any scoring.

## Implementation order (when this ADR is Accepted)

1. Insert `<!-- CC-START -->`/`<!-- CC-END -->` markers in 8 CC-bearing agents (one-shot edit)
2. Write `scripts/gen-control-agents.sh` + idempotency tests
3. Pre-commit hook regenerating `*-control.md` on `agents/*.md` change
4. Extend `block-pollution-files.sh` allowlist for `*-control.md`
5. Skill `/evals` scaffolding: `init`, `run`, `report`, `add-case`
6. Resolve the 6 open methodological questions above; write `evals/HYPOTHESES.md` + `evals/RUBRIC.md`
7. Pre-pilot (Q2 + Q5 calibration): 3 cases × 5 trials × 2 conditions on CC-5
8. Corpus pilot (CC-5 scope): 13 cases incl. 3 OWASP servlets + 2 real diffs + 8 synthetic
9. `evals/HYPOTHESES.md` committed BEFORE step 8 first run (`git log --diff-filter=A` audit anchor)
10. CC-5 pilot run → verdict per D-2 → if PASS, proceed to CC-4; if SUPPRESS, ADR 0004 supersedes CC-5

Each step generates an entry in `state/JOURNAL.md`.
