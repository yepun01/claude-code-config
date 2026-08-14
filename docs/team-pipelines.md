# /team Pipelines

Detailed reference for the pipelines orchestrated by `/team`. For the interface and strict rules, see `skills/team/SKILL.md`. This document describes the **pipeline details by task type**.

## Philosophy: minimal default, opt-in ceremony

By default, `/team <task>` runs a direct pipeline: detection → spawn → coordination → light review → tests → done. No Interview, no ROI, no Challenge, no Ultra-review.

The full ceremony is opt-in via `--ceremony` (or unitary flags).

## Pipeline detection

The lead classifies `$ARGUMENTS` by pattern:

| Detected pattern | Pipeline |
|---|---|
| "fix", "bug", "corrige", "erreur" | **Bug** |
| "review", "audit", "analyse" | **Review** |
| "refactor", "clean", "rename" | **Refactoring** |
| "design", "UI", "composant" | **UI** |
| "explore", "comprendre", "documenter" | **Exploration** |
| everything else | **Feature** |

Ambiguous (multiple patterns) → 1 AskUserQuestion with 2 options max.

Size (L/XL): heuristic on `$ARGUMENTS` mentioning "gros", "multi", "refonte", "système", >1 module. Triggers architect even on Feature.

## Pipelines by type

### Bug (minimal default)
```
deep-analyzer → developer → tester
```
- `deep-analyzer` isolates the root cause
- `developer` applies the fix
- `tester` validates (max 3 iter fix↔test)

With `--ceremony`: `deep-analyzer → diagnostic challenge → developer → code challenge → code-reviewer → tester`.

### Feature (minimal default)
```
(architect if L/XL) → developer → ultra-review → tester
```
- architect only if task is L/XL or `--arch`
- ultra-review by default (4 parallel scanners + validation), `--no-ultra` for light review (1 code-reviewer)
- The `arch.md` produced by the architect is automatically persisted as a numbered ADR in `.claude/decisions/` at the end of the pipeline (cf. `skills/team/SKILL.md` STEP 6). The `.claude/tmp/` cleanup that follows therefore does not erase the decision.

With `--ceremony`: `architect → arch challenge → developer → code challenge → ultra-review → tester`.

**Refactoring** is treated as a Feature: `developer` modifies the existing code, ultra-review validates the quality, `tester` confirms non-regression.

### UI
```
designer → developer → code-reviewer
```
- designer produces mockup/components
- developer implements
- no tester by default (UI tested manually unless e2e tests are present)

### Review
```
code-reviewer (read-only, delivers report)
```
- a single agent by default
- With `--ultra` or large scope (plugin audit): 4 parallel scanners (ultra-review pattern)

### Exploration
```
deep-analyzer OR general-purpose (read-only)
```
- no code produced
- delivers exploration report into `.claude/tmp/{team-name}/`

## Optional steps (opt-in)

### Interview 95% (`--interview` or `--ceremony`)
Ambiguity scoring CLEAR / AMBIGUOUS / VAGUE on `$ARGUMENTS`. If AMBIGUOUS → 2-3 questions per batch, target 95% confidence, max 10 questions.

### ROI Gate (`--roi` or `--ceremony`, except Bug/Exploration)
Pre-filled assessment: problem, who is affected, effort × value → GO / TO CONSIDER / TO RECONSIDER. User validates.

### Acceptance Criteria (`--criteria` or `--ceremony`, L/XL)
Generates `criteria.md` with must-pass + edge cases + DoD.

### Arch Challenge (`--challenge-arch` or `--ceremony`)
architect ↔ code-challenger loop, max 5 iter. Protocol: `team-challenge-loop.md`. Gate: CRITICAL=0 AND HIGH=0 AND Score≥8.

### Code Challenge (`--challenge-code` or `--ceremony`)
Same protocol, but dev ↔ code-challenger on implementation decisions.

### Ultra-review (`--ultra` or M+ automatic)
4 parallel scanners (2 compliance + 2 bugs, no separate security scanner) + post-hoc validation of HIGH/CRITICAL bugs. Anthropic verbatim pattern. Dedicated skill: `/ultra-review` (emits a Workflow per ADR 0017 D-2).

### Source N-Refuters (`--verify-sources`, research/exploration only)

**Why**: byline fabrication recurred *the day after* a consolidated source-verification rule (a fabricated Sjödén/Lind attribution survived a challenger pass). A single verification stage carries **correlated error** — the same reviewer who anchors on the narrative misses the same fabrication twice. The fix is independent redundancy, not a stronger single pass.

**This is the 3rd layer, not a replacement.** Keep the two existing stages: (1) the researcher self-checks each carrying byline via Crossref *before* delivery; (2) the challenger re-fetches URLs + bylines in its Phase 3b (`code-challenger.md`, 2+ compromised bylines = FAIL_CRITICAL). Layer 3 adds independent refuters on top.

**Mechanism** — for each **carrying source** (one a key claim actually depends on; skip decorative citations):
- The lead emits a small **`Workflow`** of **2-3 independent verifier `agent()` calls** per carrying source (structured return; scheduler-bounded). This is a pure fan-out (zero round-trip) → the D-6 frontier sends it to a Workflow, not tmux (rule 18 amended, ADR 0017 D-3/D-6; ADR 0014's old freeze is superseded by 0017, so no in-process/tmux arbitration is pending here).
- Each verifier receives **ONLY** `{title, cited authors, URL}` — never the surrounding narrative (narrative is the anchor that produces the correlated miss).
- **Default-refuted brief**: "Assume this byline is fabricated. Confirm — or fail to confirm — that these exact authors wrote the work at this URL/DOI. Return `refuted` unless you can positively match author list to the actual work."
- **Majority kills**: ≥2 of 3 `refuted` → the source is struck and the claim it carries is re-grounded or removed before the deliverable ships.

**Trigger**: opt-in via `--verify-sources`, and recommended-by-default whenever an exploration deliverable carries `[SOURCE]` citations with author bylines that load-bear a downstream decision.

**Falsifier**: inject one deliberately fabricated byline into a test run → the panel must kill it (≥2 refuted). If it survives, the layer is not working.

## Opt-out

- `--no-test`: skips tester
- `--no-review`: skips code-reviewer
- `--plan-only`: stops after architecture, no implementation
- `--review-only`: existing code, no new implementation
- `--auto`: no inter-step confirmation (CI/tests)
- `--parallel`: several devs in parallel by module
- `--keep-artifacts`: keeps `.claude/tmp/{team-name}/` at the end

## Diagnostic challenge (Bug-specific)

After `deep-analyzer` and BEFORE implementation, if `--ceremony`:

Challenger brief:
```
The deep-analyzer identified [X] as the root cause. Is it the REAL cause?
What other hypotheses have not been explored?
Will the proposed fix solve the symptom AND the cause?
```

Same protocol as arch challenge (team-challenge-loop.md). The deep-analyzer corrects its diagnosis, not the architect.

## References

- Challenge loop protocol: `team-challenge-loop.md`
- Ultra-review: `team-ultra-review.md`
- Unified verdict: `verdict-protocol.md`
- Anti-patterns + recovery: `team-anti-patterns.md`

