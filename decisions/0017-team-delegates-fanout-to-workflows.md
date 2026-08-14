# ADR 0017 — /team delegates fan-out stages to native Workflows (hybrid)

Status: Accepted (2026-06-08)
Date: 2026-06-08
Supersedes: ADR 0014 (Proposed → resolved)
Superseded by: —

## Context

ADR 0014 (Proposed, 2026-05-31) deferred the question *should `/team` be rebuilt on native dynamic workflows, kept as-is, or become a thin router that emits a workflow?* — pending a `/discuss` grounded in evidence, not a blind implementation pass.

That evaluation ran 2026-06-08. Empirical input: three native-`Workflow` runs executed this session (verification of plugin roadmap waves 0/1/2 — 26 verifier agents, reliable structured returns, one resume-after-bug via `resumeFromRunId`, a fabricated byline killed 3/3 by an in-process refuter panel) set against two real `/team` runs (retention + avatar research — tmux panes, dialogue round-trips, **40-60 % SendMessage loss**, manual pane capture, zombie-pane cleanup). The full mapping is the parity matrix `state/0014-parity-evidence.md`, which covers the 4 axes ADR 0014 named (coverage parity / wrap-vs-replace-vs-coexist / migration cost / loss surface).

Finding: the two systems are **orthogonal**, not rivals. `Workflow` wins execution (fan-out, structured return, budget, resume, cleanup, concurrency) `[OBSERVED state/0014-parity-evidence.md axis 1]`. `/team` holds an irreducible loss surface — **human arbitration mid-run, governed challenge loops (stagnation/regression/over-correction gates), semantic recovery (NEEDS_CONTEXT round-trips), inter-agent dialogue** — for which `Workflow` has **no native equivalent** `[OBSERVED state/0014-parity-evidence.md axis 4; docs/team-challenge-loop.md:86-90; skills/team/SKILL.md AskUserQuestion ×5]`. Neither is a superset of the other.

## Decision

Adopt **Option C — hybrid**. `/team` stays the orchestrator of dialogue, governance, and human gates; it **delegates fan-out stages to a native `Workflow`** it emits.

- **D-1 — Hybrid, not replace, not status-quo.** Reject Option B (full rewrite on `Workflow`): it pays an L-cost to lose the entire axis-4 loss surface — `--ceremony` and `--challenge` would become impossible or degraded; it is the dominated option. Reject Option A (status quo): the tmux debt persists and doc↔practice drift (rule 18 mandates tmux while June ran in-process) accrues.
- **D-2 — Pilot = `ultra-review`.** First and only migrated stage until measured: it is a pure fan-out (4 scanners, zero dialogue) and the stage that bleeds most SendMessage today. The 4 scanners (2 compliance Sonnet + 2 bugs Opus) + Phase-4 verification become `agent()` calls with `agentType:'code-reviewer'` and forced verdict schemas; Phase 0 (bash pre-checks) and Phase 5 (verdict + report) stay lead-side. Reference design: `state/0014-parity-evidence.md` + the pilot script presented in the `/discuss`.
- **D-3 — Amend rule 18.** `skills/team/SKILL.md:497` ("ALWAYS tmux, team_name mandatory") is amended to: *tmux + team_name mandatory for **dialogue teammates**; native `Workflow` (in-process agents) permitted for **fan-out stages**.* This is the single rule change required; it is the technical lock that A→C must lift. A skill whose instructions call `Workflow` counts as a legitimate ultracode opt-in, so no per-invocation keyword is needed.
- **D-4 — Preservation is total on the governance layer.** No agent is deleted: the 9 agents are reused as-is by `Workflow` via `agentType` (same registry as the `Agent` tool), keeping their system prompts — including reading `.claude/decisions/*.md` at startup, so ADR governance survives *into* Workflow-spawned agents. `.claude/decisions/`, `state/`, `JOURNAL.md`, the 19 rules (those taming tmux fragility — dedup/capacity/shutdown/lifecycle, rules 14-17 — narrow in scope to dialogue teammates but are not removed), and the SendMessage comms pattern (kept for dialogue, replaced by structured return only on migrated stages) all persist. The `*-control` twins are untouched (eval baseline).
- **D-5 — Epistemology becomes machine-enforced on migrated stages.** Evidence markers / verdicts, imposed in prose today, become a forced `schema` (`verdict: enum`, `refutable_by: required`) on Workflow-delegated stages — a strict gain over prose.
- **D-6 — Frontier rule (fan-out vs dialogue).** A stage is **fan-out** (→ Workflow) iff it has zero teammate↔teammate and zero teammate↔human round-trips *during* execution; otherwise it is **dialogue** (→ tmux). Ultra-review, N-refuters, research sweeps are fan-out. Architect round-trips, challenge loops, NEEDS_CONTEXT recovery are dialogue. Extension beyond the pilot requires applying D-6 explicitly per stage.
- **D-7 — Reversibility gate.** The pilot is one stage; rollback = revert that stage to the tmux path. Extending the hybrid to any further stage requires a measured PASS on the pilot first (see falsification tests). No second stage migrates blind.

## Consequences

- **Positive**: the root debt (40-60 % SendMessage loss) dies exactly where it occurs — the parallel stages — without sacrificing dialogue, governance, or human arbitration. Epistemology is hardened. The change is incremental and reversible.
- **Positive**: ADR 0014's most-disruptive radar item is resolved with evidence, not parked.
- **Negative**: two mental models coexist — a maintainer must know the D-6 frontier (which stage is fan-out vs dialogue). This is the honest, accepted cost of the hybrid.
- **Negative**: migrated stages lose live per-agent pane observability (`tmux capture-pane`); `/workflows` progress replaces it, opaquer per agent. Acceptable for stages that only emit structured findings.
- **Follow-up**: implement the `ultra-review` pilot (D-2), measure against the falsification tests, then decide extension under D-7. `state/MONITORING-2026-06.md` Actionable top-1 (native-workflows-vs-team) is resolved by this ADR.

## Tests that would invalidate this design

- **Coverage regression**: run the same diff through the tmux ultra-review and the Workflow pilot. If the Workflow pilot surfaces **fewer** confirmed findings (lost/dropped), or a different verdict, the reliability claim is false → rollback the pilot (D-7).
- **Governance break in Workflow**: if a `Workflow`-spawned agent with `agentType:'code-reviewer'` does **not** read `.claude/decisions/*.md` at startup (verify: inject an ADR-dependent claim and check the agent honors it), D-4's "governance survives into Workflow agents" is falsified → the migration is unsafe and the pilot is withdrawn.
- **Frontier unworkable**: if D-6 cannot be applied unambiguously to an existing pipeline stage (a stage that is *both* fan-out and dialogue mid-execution), the frontier rule is incomplete → revise D-6 before any extension.
- **Net friction loss**: if maintaining the two-model boundary costs more edits/confusion than the SendMessage loss it removes (measure: count the stages that actually qualify as fan-out — if ≤1, the hybrid is not worth its conceptual overhead) → keep only the pilot, do not generalize.
