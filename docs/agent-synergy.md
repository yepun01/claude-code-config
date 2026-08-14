# Agent synergy — cross-cutting protocols

Single source of truth for protocols that apply to multiple agents. Each protocol is referenced from the agent system prompts via:

> Cross-cutting protocols: see `~/.claude/docs/agent-synergy.md`

Active protocols (iter 4 lean): **CC-2 pre-mortem**, **CC-4 falsifiability**. CC-1 (Blind-First Pass) and CC-3 (multi-persona forced findings) are deferred to a follow-up ADR pending telemetry infrastructure. CC-5 (anti-sycophancy red-flags) was active in iter 4 then SUPPRESSED 2026-05-02 per ADR 0003 §D-2 staged evaluation (HYPOTHESES.md amendments-log entry "2026-05-01 — CC-5 pilot N=4 escalation + measurement-artifact diagnosis + manual SUPPRESS override").

---

## CC-2 · Pre-mortem for creator-class

**Apply to**: `architect` (Phase 0bis before writing arch.md), `developer` (before TDD), `deep-analyzer` (before stating root cause), `designer` (before mockup), `innovator` (per alternative).

### Why (peer-reviewed)

- **`[SOURCE: Klein 2007 HBR — "Performing a Project Premortem"]`** — qualitative formalization: prospective hindsight makes it safe for dissenters to surface weakness ex-ante.
- **`[SOURCE: Mitchell, Russo & Pennington 1989, Journal of Behavioral Decision Making 2(1):25-38 — "Back to the future: Temporal perspective in the explanation of events"]`** — quantitative caveat: prospective hindsight produces ~30% MORE reasons but typically *episodic* in quality. The technique generates surface area; team discipline turns surface area into actionable risks.
- **`[SOURCE: Veinott, Klein & Wiggins 2010 ISCRAM — "Evaluating the Effectiveness of the PreMortem Technique on Plan Confidence"]`** — peer-reviewed quantitative validation: premortem reduces overconfidence ~2× more than Pro/Cons or Cons-only methods.
- **`[INTUITION]`** — LLM-transfer step: the premortem prompt structure works on LLMs analogously to humans. No peer-reviewed paper has yet measured the LLM-specific effect; the grounding is engineering judgment supported by analogy.

### How

Each creator agent runs a 1-paragraph step in Phase 0bis (or a mandatory section per output) with the following structural constraint: **every disaster scenario MUST name (a) a specific component or sub-system, (b) a concrete trigger condition, (c) a measurable failure signal**. Generic scenarios ("spec changes mid-flight", "dependency breaks") are forbidden — they are the cargo-cult target.

Per-agent prompts:

- **architect**: "Imagine this design has been live 6 months and just blew up catastrophically. Narrate the 3 most plausible disaster scenarios. Each scenario must name (a) a specific component or sub-system, (b) a concrete trigger condition (input/load/dependency), (c) a measurable failure signal. Each scenario must be addressed in the design or explicitly accepted as residual risk."
- **developer**: "Imagine the CI fails 1 hour after merge. Name the 3 most plausible failure modes — each: component + trigger + signal. Tests cover each."
- **deep-analyzer**: "Imagine my proposed root cause is wrong. What would the symptoms look like instead? What evidence would prove the alternative?"
- **designer**: "Imagine 30% of users abandoned the feature in 6 months. Why? Each scenario must name (a) user persona, (b) interaction trigger, (c) abandonment signal."
- **innovator**: per alternative — "if this alternative wins, what's the failure mode 12 months later? Use the (component, trigger, signal) tripartite."

### Cargo-cult mitigation

Addressed *structurally* by the (component, trigger, signal) tripartite requirement. Iter 3 used a passive Levenshtein-distance telemetry alert; iter 4 makes the constraint active inside the prompt.

### Refutable by `[ENGINEERING threshold]`

5-ADR audit. If architect's pre-mortem scenarios still collapse to generic-template (no specific component named, no concrete trigger, no measurable signal), the structural constraint isn't being enforced; revisit prompt phrasing or drop CC-2.

---

## CC-4 · Falsifiability extension to evidence markers

**Apply to**: `architect`, `developer`, `code-reviewer`, `security-reviewer`, `code-challenger`, `deep-analyzer`, `designer` (every agent emitting evidence-marked claims).

### Why

- **`[SOURCE: Popper 1959 — *The Logic of Scientific Discovery*]`** — foundational principle: scientific claims must specify their potential falsification. Engineering claims benefit from the same discipline.
- Existing `[SOURCE]/[OBSERVED]/[INTUITION]` markers prove a claim was grounded; the `Refutable by` line exposes what would refute it.

### How

Every CRITICAL / HIGH issue + every architectural decision must include a one-line:

```
*Refutable by:* [concrete observable evidence that would prove this is NOT a problem]
```

#### Example

- Before: `[CRITICAL] No input validation — Evidence: api.ts:42`
- After: `[CRITICAL] No input validation — Evidence: api.ts:42 — Refutable by: a fuzz test on api.ts exercising 1000 random inputs without crash or unintended state mutation`

#### Quality bar

Each `Refutable by` line specifies (i) experiment shape, (ii) data source / measurement, (iii) threshold. Generic restatements ("show me a passing test") count as collapse.

### Refutable by `[ENGINEERING threshold]`

Audit 30 review reports post-implementation. If `Refutable by` lines collapse to "show me a passing test" in >90% of cases — providing zero information beyond Evidence — drop the field. Threshold (90%) is `[ENGINEERING]`: chosen as "almost-all"; no peer-reviewed calibration.

---

## Agent → CC mapping

| Agent | CC-2 (pre-mortem) | CC-4 (falsifiability) |
|---|:---:|:---:|
| architect | ✓ Phase 0bis | ✓ per ADR Decision |
| developer | ✓ before TDD | — |
| code-reviewer | — | ✓ per finding |
| security-reviewer | — | ✓ per security finding |
| code-challenger | — | ✓ per finding (extends 4th dim) |
| deep-analyzer | ✓ of own hypothesis | ✓ per root cause |
| tester | — | — |
| designer | ✓ of UX | ✓ per design decision |
| innovator | ✓ per alternative | ✓ per alternative |

---

## Refutability summary table

| Protocol | Experiment | Data source | Threshold |
|---|---|---|---|
| CC-2 (cargo-cult check) | 5-ADR audit | architect's pre-mortem section text | `[ENGINEERING]` Mean pairwise Levenshtein < 0.4 between scenarios → drop |
| CC-2 (structural constraint) | 5-ADR audit | architect's pre-mortem section | `[ENGINEERING]` ≥80% scenarios name (component, trigger, signal) tuple → constraint enforced |
| CC-4 | 30-finding audit | review/challenge reports | `[ENGINEERING]` ≥80% CRITICAL/HIGH have non-trivial Refutable-by → CC-4 working |
| `/premortem` skill | 60-day invocation count | manual count of git commits or terminal history | `[ENGINEERING]` ≥3 invocations → keep; <3 → deprecate |

All `[ENGINEERING]` thresholds are pragmatic engineering choices with rationale stated, counted in justification denominator at weight 0.5 — no carve-out.

---

## Deferred protocols (not active in iter 4 lean)

- **CC-1 Blind-First Pass (BFP)** — review-class agent reads artifact alone before reading author justification. Deferred pending: (a) D-5 telemetry to measure effect, (b) BFP applicability disambiguation (null-op in `/ultra-review` scanners that already work diff-only by Anthropic constraint).
- **CC-3 Multi-persona forced findings** — review-class adopts 3 mindset personas (Saboteur / Future Maintainer / Security Auditor). Deferred pending: (a) explicit acknowledgment of analogical-inference step from human evaluator studies → LLM behavior, (b) D-5 telemetry to measure persona-finding overlap.

Both will be reactivated in a follow-up ADR once D-5 telemetry is in scope.
