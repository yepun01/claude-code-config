# ADR 0018 — Eval + viewer cluster: implementation-status reconciliation

## Status

Accepted (2026-06-08). Reconciles the Status of ADR 0004 / 0005 / 0006 / 0007 / 0009 (shipped but still labelled "Proposed"). Does **not** supersede their decisions — those stand and were executed. Mirrors the promotion mechanism of ADR 0016 §D-3 (which promoted 0001/0002 by reference).

## Context

A plugin-wide coherence audit (2026-06-08, 8-scanner Workflow + adversarial verification) surfaced five ADRs whose Status reads "Proposed" / "Implementation pending" while their decisions are demonstrably shipped on disk:

- **0004** (viewer-multi-plateforme) — `viewer/server/indexer.ts`, `viewer/server/server.ts` present; 0004's own D-4 note already records "viewer ships with server-side index at request time". The "Implementation pending" head contradicts that note.
- **0005** (/evals skill design) — `skills/evals/SKILL.md` shipped; the skill cites 0005 as its design source.
- **0006** (/evals multi-file split) — `skills/evals/{scripts,templates,references}/` present, the exact structure D-1 mandates.
- **0007** (CC-5 A/B pilot runner) — `/evals run --pilot` shipped; the pilot executed (`evals/reports/pilot-*.md`).
- **0009** (corpus 3→13) — `evals/corpus/` holds exactly 13 cases.

The append-only rule forbids freely flipping each "Proposed" → "Accepted" in place (an unrecorded status transition). ADR 0016 set the precedent: a governance-closure ADR promotes others by reference and codifies Status-line back-pointer maintenance (§D-2).

The nuance that kept these "Proposed" is real and must be preserved: the eval *program*'s scientific verdict is **UNDETERMINED** (ADR 0016 §A8: d_z=0.249, IC95 includes 0.5), and the CC-4/CC-2 evaluation is **paused until the 2026-09-04 sunset** (ADR 0016 §D-4). So "Proposed" was half-true: false on "not built", true on "not validated".

## Decision

**D-1. Decouple the two layers.** Record that the *implementations* of 0004/0005/0006/0007/0009 shipped (observable on disk), while the eval *program*'s verdict remains UNDETERMINED and paused per ADR 0016 §A8/§D-4.

**D-2. Reconcile by back-pointer, not in-place flip.** Each of the five ADRs gains a Status-line back-pointer — "Implementation reconciled by 0018 (shipped; eval-program verdict UNDETERMINED, paused sunset 2026-09-04)" — the 0016 §D-2 maintenance pattern. Their bodies stay immutable.

**D-3. No research conclusion is claimed.** This ADR reconciles build-status only. Whether CC-5/CC-4 produce a measurable effect stays open until the post-sunset resumption ADR.

## Consequences

- The five ADRs stop falsely signalling "nothing built"; a reader sees: shipped, validation paused.
- The "Proposed-but-shipped" coherence defect (5× MEDIUM) raised by the audit is closed without violating append-only.
- If the post-2026-09-04 resumption reaches a verdict, a further ADR promotes the eval *program* itself (Accepted or Rejected) — this ADR does not pre-empt that.
- **Falsifier**: if any of `viewer/server/`, `skills/evals/SKILL.md`, `skills/evals/scripts/`, `evals/reports/pilot-*.md`, or 13 entries in `evals/corpus/` is absent, the "shipped" claim is wrong and this reconciliation must be revisited.

## Date
2026-06-08
