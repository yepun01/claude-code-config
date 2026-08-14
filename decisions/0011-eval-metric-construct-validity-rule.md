# ADR 0011 · eval-metric-construct-validity-rule

**Status**: Proposed. Supersedes ADR 0003 §D-4 (primary-metric pre-registration clause) and §"Implementation order" step 6. Other clauses unchanged.

**Date**: 2026-05-02

## Context

The CC-5 pilot returned UNDETERMINED across N=2 then N=4 with a sign flip (d_z = −0.254 → +0.249, IC95 0.003 from algorithmic SUPPRESS). Manual inspection traced the result to a mention-vs-use confound: the treatment agent quotes the 9 forbidden phrases verbatim inside its self-audit text to demonstrate compliance, and the case-insensitive `grep -oFi` over `output_text` counts those mentions as infractions of the rule the agent is following. The construct-valid effect is ≤ 0; the apparent +0.249 is a measurement artifact. `[OBSERVED evals/HYPOTHESES.md:266-323, 314-316]` CC-5 was suppressed plugin-wide on 2026-05-02 (commits `7dd29a2` empirical anchor → `80561e9` SUPPRESS, run `evals/runs/20260501T103203Z-pilot/`); the lesson is prospective. `[SOURCE: Cronbach & Meehl 1955 *Psychological Bulletin* 52(4):281-302 — "Construct validity in psychological tests"]` formalized instrument validation against trait-irrelevant variance; this is exactly the missing step.

## Decision

Any future eval pilot MUST validate the bare instrument against ≥3 hand-crafted **mention-only fixtures** — synthetic agent-output records that quote the rule verbatim without applying it — BEFORE pre-registering its primary metric in HYPOTHESES.md. If any fixture produces a non-null measurement in the inflation direction, the metric is rejected and redesigned. No specific machinery is prescribed: no gate script, no directory convention, no Gate E in `run-pilot.sh`. Procedural discipline only, recorded in the HYPOTHESES.md amendment that locks the metric. `[ENGINEERING]` (≥3 fixtures threshold) The `/evals` skill is paused per current ROADMAP; this ADR records the rule for any reactivation, not a build-out.

*Refutable by:* a future eval pilot ships a primary metric without a pre-registered mention-fixture validation paragraph in HYPOTHESES.md AND post-hoc inspection surfaces a construct-validity issue → the rule was not enforced.

## Tests that would invalidate this design

- **T1 — Retroactive coverage**: applying the rule to the historical CC-5 `red_flag_count` regex with 3 mention-fixtures based on the actual N=4 self-audit text MUST flag the metric as rejected. If the rule does not flag the regex that motivated this ADR, the rule is too weak.
- **T2 — Discoverability**: a future pilot author reading ADR 0003 + this ADR + HYPOTHESES.md MUST be able to author the mention-fixture step without further guidance. If the next pilot ships without a fixture paragraph despite the ADR being in `.claude/decisions/`, the discipline is unreadable as written and needs operationalization (machinery deferred but mandatory then).
- **T3 — Procedural footprint**: 60 days post-acceptance, `git log -- .claude/decisions/ ~/.claude/skills/evals/` shows no mention of "mention-fixture" or "construct-validity" in any artifact whose author asked the question — the rule has decayed to ceremony. Trigger: `/evals` reactivation without referencing this ADR in the kickoff commit.

## Consequences

The construct-validity lesson is preserved in the audit-trail without committing to gate machinery the user has chosen not to maintain. CC-5 history (HYPOTHESES.md:266-338) is untouched. If `/evals` is reactivated for CC-4 or any successor, this ADR is the prerequisite to read — and machinery (mention-fixture artifact directory, pre-flight gate) becomes a follow-up ADR at that time.
