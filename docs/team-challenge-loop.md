# Iterative challenge loop protocol

This protocol is used by STEPS 1.5 (arch challenge) and 2.5 (code challenge) of the /team pipeline. Only the challenger's brief and the creator who corrects change with the context.

## Loop parameters

| Parameter | Value | Role |
|-----------|-------|------|
| MAX_ITERATIONS | 5 | Absolute cap, human escalation after |
| SCORE_THRESHOLD | 8/10 | Minimum score to exit (demanding) |
| JUSTIFICATION_THRESHOLD | 7/10 | Minimum empirical justification score (4th dimension). **Why 7**: with the weighted formula (SOURCE=1.0, OBSERVED=0.7, INTUITION=0.3), 7/10 forces a healthy mix — majority SOURCE/OBSERVED with a few acceptable INTUITION (~30% max). Below that, the artifact relies too much on unverified intuition. |
| CRITICAL_ALLOWED | 0 | Zero tolerance on critical issues |
| HIGH_ALLOWED | 0 | Zero tolerance on high issues |
| MIN_DELTA | 0.5 | Minimum improvement between 2 iterations (otherwise diminishing returns) |

## Phase 1: Self-review (before the external challenge)

BEFORE spawning the challenger, ask the creator (architect or dev) to perform a **self-review** of their own deliverable:

"Re-read your deliverable and check this checklist:
- [ ] No single point of failure
- [ ] Horizontal scalability possible
- [ ] Security: auth, validation, encryption covered
- [ ] Complete error handling (not just the happy path)
- [ ] No unnecessary tight coupling between components
- [ ] Each component is testable in isolation
- [ ] No undocumented assumption
Fix the obvious problems and update the document."

This eliminates gross errors before spending tokens on an external challenger.

## Phase 2: Adversarial loop

Spawn a `code-challenger` teammate. Initialize the counter: `iteration = 1`, `previous_score = 0`, `previous_criticals = 999`.

**At each iteration:**

1. **Challenger critiques** — Send to the challenger:
```
Read the deliverable to challenge.
{If iteration > 1: "This is iteration {iteration}. The previous report is in .claude/tmp/{team-name}/challenge-{iteration-1}.md. Identify RESOLVED issues (fixed) and PERSISTENT issues (not fixed). Then look for NEW flaws."}

Produce a report in the MANDATORY format:

## Challenge Report — Iteration {iteration}

### Score: [X/10]

### Issues
- [CRITICAL] Title — Evidence: [section/file] — Problem — Suggestion
- [HIGH] Title — Evidence: [section/file] — Problem — Suggestion
- [MEDIUM] Title — Evidence: [section/file] — Problem — Suggestion

### RESOLVED (issues from the previous iteration that have been fixed)
- [title of the fixed issue]

### PERSISTENT (issues from the previous iteration NOT fixed)
- [title — why still present]

### VERDICT: PASS / FAIL_CRITICAL / FAIL_WARNING / NEEDS_JUSTIFICATION

RULES:
- Each issue MUST have concrete evidence (specific section or element of the document)
- Minimum number of issues by scope: >200 lines → 3, 50-200 → 2, <50 → 1. If sincerely no issue after thorough analysis, document what you verified.
- Do NOT compliment the work. Your job is to find the flaws.
- If this is iteration 1 and everything looks perfect, you are probably in sycophancy mode — dig deeper.
```

The challenger writes its report into `.claude/tmp/{team-name}/challenge-{iteration}.md`.

2. **Evaluate the report** — Parse the challenger's report:
   - Count `criticals`, `highs`, `score`, `justification_score`

3. **Exit gate (extended)** — Check in this order:

   **a) CONVERGENCE:** If `criticals == 0 AND highs == 0 AND score >= 8 AND justification_score >= 7` → PASS. Exit the loop.

   If `criticals == 0 AND highs == 0 AND score >= 8 AND justification_score < 7` → FAIL_WARNING with synthetic HIGH issue. **You MUST inject this issue into the report** `.claude/tmp/{team-name}/challenge-{iteration}.md` (append to the Issues section) otherwise the creator will not see it. Format to add:
   ```
   - [HIGH] Insufficient empirical justification — Evidence: section "Empirical justification" (score={X}/10 < 7) — Problem: too much unsourced intuition, the 7/10 threshold is not reached — Suggestion: replace [INTUITION] with [SOURCE] (web search) or [OBSERVED] (reference to the code) on the key decisions
   ```
   Continue the loop — the creator must source their decisions.

   **b) DIMINISHING RETURNS:** If `iteration > 1 AND (score - previous_score) < 0.5 AND criticals == 0` → the challenger no longer finds anything significant. Display: "Diminishing returns (delta score < 0.5, 0 CRITICAL). Current score: {score}/10." If score >= 7 → exit with PASS. Otherwise → ask the user whether to continue.

   **c) STAGNATION:** If `iteration > 1 AND score == previous_score AND criticals == previous_criticals AND at least 50% of the issue titles are identical to those of the previous iteration` → the same issues persist. Display to the user: "The challenger and the creator are not converging on these points: [list]. Do you want to arbitrate or continue?" If the user arbitrates → exit. If continue → next iteration. **CAUTION**: if the issues are NEW (different titles), this is NOT stagnation — it is progress with new findings. Continue the cycle.

   **d) REGRESSION:** If `iteration > 1 AND score < previous_score` → the deliverable got worse. STOP. Display: "Warning: the score dropped from {previous_score} to {score}. The creator may have over-corrected. Roll back to the previous version?"

   **e) MAX ITERATIONS:** If `iteration == 5` → ESCALATE. Display to the user a summary of each iteration (scores, remaining issues) and ask: "5 iterations without convergence. Do you want to accept as is, give directives, or abandon?"

   **f) OTHERWISE:** Continue — proceed to step 4.

4. **Creator corrects** — Send the challenger's report to the original creator:
```
The challenger has produced its iteration {iteration} report in .claude/tmp/{team-name}/challenge-{iteration}.md. Read it.
For each CRITICAL and HIGH issue:
- Either fix the deliverable
- Or explicitly justify why the issue is not valid (with evidence)
MEDIUM issues are optional.
```

5. **Update counters**: `previous_score = score`, `previous_criticals = criticals`, `iteration += 1`. Back to step 1.

## After the loop

- Shutdown the challenger
- Display the summary to the user:

```
[CHALLENGE] Done
Iterations: [N]/5
Final score: [X]/10 (evolution: [score1] → [score2] → [scoreN])
Remaining CRITICAL issues: [N]
Total issues resolved: [N]
Exit by: [convergence / stagnation / regression / max iterations / user arbitration]
```

- Ask for the user's final validation before moving to the next step

