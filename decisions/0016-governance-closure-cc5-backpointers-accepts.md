# ADR 0016 — Governance closure: supersede CC-5, codify back-pointer maintenance, accept implemented ADRs, pause CC-4/CC-2

## Status
Accepted (2026-06-04). Closes A1+A3+A4+A8 of the coherence audit 2026-06-04 (`tmp/audit-coherence-20260604/coherence-review.md`, verdict FAIL_CRITICAL — 4 HIGH, all documentary-governance debt; key findings summarized in Context below so this ADR survives tmp GC).

Date: 2026-06-04
Supersedes: ADR 0002 §CC-5 (formalizes suppression commit `80561e9`)
Superseded by: —

## Context

The 2026-06-04 coherence audit found zero execution defects but 4 HIGH documentary-governance contradictions:

- **A1** — CC-5 was suppressed plugin-wide on 2026-05-02 (commit `80561e9`, −133 lines across 4 agents + `docs/agent-synergy.md`) `[OBSERVED: git show --stat 80561e9]`, but no superseding ADR exists. ADR 0003 §D-4 pre-registered: *"a follow-up ADR `ADR-NNNN-supersede-cc-X.md` is committed within 30 days […] No carve-outs"* `[SOURCE: decisions/0003-evaluation-protocol.md:122]`. The 30-day window expired 2026-06-01. Meanwhile ADR 0002 still describes CC-5 as an active protocol (17 mentions, zero back-pointer) `[OBSERVED: grep -c "CC-5" decisions/0002-*.md → 17]` — the 6 ADR-aware agents read a falsified protocol as designed-and-active.
- **A3** — back-pointer practice is inconsistent: ADR 0003 received a post-hoc Status back-pointer (backlog N2) `[OBSERVED: decisions/0003:4]`, ADRs 0002/0004/0005 received none, and CLAUDE.md §ADR says "NEVER modify an existing ADR" without codifying the Status-line exception the N2 precedent demonstrates.
- **A4** — ADRs 0001 and 0002 are marked Proposed while their decisions are shipped and enforced in production.
- **A8** — the eval sequence CC-5 → CC-4 → CC-2 (ADR 0003 §D-2) stalled after the CC-5 pilot returned **UNDETERMINED** on 2026-05-01 (d_z=0.249460, IC95 [0.000000, 0.503092], n=104/104) `[OBSERVED: evals/reports/pilot-20260501T103203Z.md]`. The pause decision lives only in mutable state (ROADMAP, stale since 2026-05-10) while 8 `*-control` agents + pre-commit regen + opus eval-lock (ADR 0015 §Deferred) keep imposing their cost.

## Decision

### D-1 · Supersede CC-5 — formalize commit `80561e9`

The plugin-wide suppression of CC-5 (anti-sycophancy red-flags) executed on 2026-05-02 is hereby the decided state. Empirical basis: the CC-5 pilot's primary metric failed construct validity — the instrument measured *mention* of the rule, not *use* of it (mention-vs-use confound, diagnosed in ADR 0011 §Context) — and the manual SUPPRESS override of 2026-05-01 (HYPOTHESES.md amendments-log) was applied to the whole plugin per ADR 0003 §D-2 "remove CC from plugin". Residual state: 0 CC-5 mentions in `agents/*.md` `[OBSERVED: grep -rn "CC-5" agents/ → 0 hit]`; `docs/agent-synergy.md:7` annotates the suppression. This decision closes the ADR 0003 §D-4 30-day follow-up obligation, 3 days past its 2026-06-01 deadline — the delay is acknowledged, not excused.

### D-2 · Codify Status-line back-pointer maintenance

The append-only rule applies to the **body** of an ADR (Context / Decision / Consequences / Tests). The `Status:` line is maintainable. Authorized patterns:

- `Status: Accepted (YYYY-MM-DD). Superseded by NNNN §<scope>.`
- `Status: Accepted. D-X amended by NNNN §<scope>.`
- `Status: Proposed (…). D-X superseded/amended by NNNN §<scope>.` or `Status: Proposed (…). D-X obsoleted by <shipped implementation> (NNNN §<scope>).`

Precedent: ADR 0003:4 received exactly this treatment (backlog N2, shipped 2026-05-10). Applied in the same commit as this ADR:

- **ADR 0002** — back-pointer to 0016 §D-1 (CC-5 superseded; CC-2/CC-4 unaffected).
- **ADR 0004** — D-1 amended by 0010 §D-1; D-2 partially superseded by 0008 §D-1; D-4 obsoleted: the shipped viewer builds its index server-side at request time (`viewer/server/indexer.ts`) instead of the hook M-1 / `cache/viewer-index.jsonl` / `/viewer` skill plan `[OBSERVED: viewer/server/server.ts:7,47 ; hooks/index-claims.sh absent]`.
- **ADR 0005** — D-1 superseded by 0006 §D-1 (single-file convention → multi-file split; declared in 0006's own Status) `[OBSERVED: decisions/0006:4]`.

### D-3 · Promote ADR 0001 and ADR 0002 to Accepted

- **ADR 0001** (`Proposed (v2)` → Accepted): all 3 layers are shipped and enforced — common "Team communication protocol" block in the 17 `agents/*.md`, `send-message-guard.sh` wired as PreToolUse(SendMessage) `[OBSERVED: settings.json hooks section]`, rule 19 + grep validation in `skills/team/SKILL.md`.
- **ADR 0002** (`Proposed` → Accepted): CC-2 and CC-4 are active in every agent prompt + `docs/agent-synergy.md`. CC-5 scope carved out per D-1.

Format follows the ADR 0012 precedent (`Accepted (date). Implementation: …`).

### D-4 · Formal pause of CC-4/CC-2 evaluation, with a hard date

The CC-4 → CC-2 sequence of ADR 0003 §D-2 never started after CC-5's SUPPRESS. The pause is now formal, not a stale ROADMAP artifact:

- **Paused until 2026-09-04** (3 months).
- **Resumption condition**: a follow-up ADR resolving the CC-5 pilot's UNDETERMINED (escalate budget per the report's recommendation, or suppress definitively — both are honorable exits; the stall is not).
- **Sunset clause**: if no resumption ADR exists by 2026-09-04, the 8 `*-control.md` agents are removed and the pre-commit regen (`regen-control-agents.sh`) is unwired — the tester precedent (no paired arm, ADR 0015) becomes the general rule, unlocking the model-tiering of the 8 pairs and their token cost immediately.

## Consequences

- **Positive**: the 6 ADR-aware agents no longer read CC-5 as active; the decisional record matches `agents/*.md` reality. Back-pointer maintenance has a written rule instead of an implicit precedent. The eval program has an owner-less-stall escape hatch with a date.
- **Negative**: the ADR 0003 §D-4 deadline was missed by 3 days — recorded here as a discipline failure signal; a second miss should trigger a review of whether pre-registered deadlines are realistic for a solo setup.
- **Neutral**: historical ADRs (0002, 0003, 0005, 0006, 0007, 0009, 0011) keep their CC-5 mentions in their append-only bodies; navigation to the suppression decision goes through the Status back-pointers.

## Tests that would invalidate this design

- **T1 (D-1)** — `grep -rn "CC-5" agents/*.md` returns ≥1 hit without a new ADR re-introducing the protocol → undocumented re-falsification; this ADR's suppression claim is void. (Historical mentions in ADR bodies are expected and excluded — they are append-only.)
- **T2 (D-2)** — a superseded/amended ADR without a visible Status back-pointer contradicts D-2. Post-fix measure (line-level, Status section only): `for f in decisions/0002-*.md decisions/0004-*.md decisions/0005-*.md; do head -5 "$f" | grep -E "uperseded|mended|bsoleted" || { echo "FAIL: $f"; exit 1; }; done` → must print a back-pointer hit for each of the 3 ADRs, zero FAIL.
- **T3 (D-3)** — an ADR whose decisions run in production still marked Proposed after this commit = contradiction. Expected post-fix state: 0001/0002 Accepted; ADR 0013 deliberately stays Proposed (its T6 E2E gate was never executed — promoting it would endorse an unvalidated pipeline).
- **T4 (D-4)** — current date > 2026-09-04 AND no resumption ADR in `decisions/` → the sunset clause MUST execute (remove the 8 `*-control.md` + unwire pre-commit regen, via a recorded ADR). If the `*-control` agents survive past the deadline without either ADR, D-4 is theater and this governance-closure pattern is falsified.
