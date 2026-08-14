# Verdict Protocol v2

## Format

Last non-empty line of the output, exact format:

```
VERDICT: PASS
VERDICT: FAIL_CRITICAL
VERDICT: FAIL_WARNING
VERDICT: NEEDS_JUSTIFICATION
```

## Definitions

| Verdict | Meaning | Action |
|---------|---------|--------|
| PASS | No blocking issue. Minor suggestions may exist. | Continue / merge |
| FAIL_CRITICAL | Critical issues that MUST be fixed. | Block. Fix before continuing. |
| FAIL_WARNING | Non-critical issues that SHOULD be fixed. | The user decides: fix or continue. |
| NEEDS_JUSTIFICATION | Decisions that require an explicit justification. Challenge only. | The author must justify their choices. |

## Rules

1. The VERDICT line must be the LAST non-empty line of the output
2. On its own line (no prefix, no suffix)
3. UPPERCASE exactly as shown
4. ONE single verdict per output
5. All review agents and skills MUST end with a verdict
6. `NEEDS_JUSTIFICATION` is emitted by `code-challenger` / `/challenge` only — `code-reviewer`, `security-reviewer` and `/ultra-review` emit the 3 standard verdicts (cf. "Agents and skills concerned" table)

## Criteria structured by context

### Context: Code Review (agent `code-reviewer`, skill `/ultra-review`)

| Verdict | Criteria (ALL must be true) |
|---------|-----------------------------|
| PASS | 0 CRITICAL, 0 HIGH, Score >= 7, **Refutable-by gate >= 80%** |
| FAIL_WARNING | 0 CRITICAL, (1-3 HIGH OR Score 5-6 OR Refutable-by gate < 80%) |
| FAIL_CRITICAL | >= 1 CRITICAL OR > 3 HIGH OR Score < 5 |

**Refutable-by gate** (per CC-4 of `~/.claude/docs/agent-synergy.md`): every CRITICAL / HIGH finding MUST include a `*Refutable by:* [concrete observable evidence]` line. The gate measures the share of CRITICAL/HIGH findings that satisfy this. Below 80% → downgrade VERDICT one tier (PASS → FAIL_WARNING).

Examples:
- 2 HIGH issues + Score 6 → FAIL_WARNING (0 CRITICAL, within the 1-3 HIGH range)
- 1 CRITICAL issue + Score 8 → FAIL_CRITICAL (>= 1 CRITICAL, regardless of score)
- 4 HIGH issues + Score 5 → FAIL_CRITICAL (> 3 HIGH)
- 0 CRITICAL, 0 HIGH, Score 7 → PASS

### Context: Challenge (skill `/challenge`, agent `code-challenger`)

| Verdict | Criteria |
|---------|---------|
| PASS | 0 CRITICAL, <= 2 HIGH, Score >= 8, Justification score >= 7, **Refutable-by gate >= 80%** |
| FAIL_WARNING | 0 CRITICAL, (> 2 HIGH OR Score < 8 OR Justification score < 7 OR Refutable-by gate < 80%) |
| FAIL_CRITICAL | >= 1 CRITICAL (including any decision without a [SOURCE]/[OBSERVED]/[INTUITION]/[ENGINEERING] marker) |
| NEEDS_JUSTIFICATION | 0 CRITICAL, unjustified decisions requiring explanation from the creator |

Examples:
- 0 CRITICAL, 1 HIGH, Score 9, justification 8 → PASS
- 0 CRITICAL, 3 HIGH, Score 7, justification 6 → FAIL_WARNING (> 2 HIGH, Score < 8, justification < 7)
- 1 decision without a marker → FAIL_CRITICAL (decision without marker = CRITICAL)
- 0 CRITICAL, 0 HIGH, Score 8, but 2 [INTUITION] decisions without clear justification → NEEDS_JUSTIFICATION

### Context: Security (agent `security-reviewer`)

| Verdict | Criteria |
|---------|---------|
| PASS | 0 exploitable vuln, 0 secret exposed, headers OK |
| FAIL_WARNING | Warnings only (misconfig, missing headers, deps outdated without critical CVE) |
| FAIL_CRITICAL | >= 1 exploitable vuln (injection, auth bypass, exposed secret) |

Examples:
- HSTS headers missing, no vuln → FAIL_WARNING
- SQL injection in a public endpoint → FAIL_CRITICAL
- Hard-coded API secret in the code → FAIL_CRITICAL
- Everything covered, no issue → PASS

### Context: Ultra-review (aggregation, skill `/ultra-review`)

Aggregation of the verdicts of the 4 scanners (2 compliance + 2 bugs) + verifiers:

| Condition | Final verdict |
|-----------|---------------|
| >= 1 scanner emits FAIL_CRITICAL after verification | FAIL_CRITICAL |
| Unresolved compliance findings + Confirmed bugs >= 2 | FAIL_CRITICAL |
| 1-2 confirmed non-critical issues | FAIL_WARNING |
| All scanners PASS after verification | PASS |

Reference: `~/.claude/docs/team-ultra-review.md` Phase 5.

## Agents and skills concerned

| Source | Possible verdicts |
|--------|-------------------|
| agent `code-reviewer` | PASS, FAIL_CRITICAL, FAIL_WARNING |
| agent `security-reviewer` | PASS, FAIL_CRITICAL, FAIL_WARNING |
| agent `code-challenger` | PASS, FAIL_CRITICAL, FAIL_WARNING, NEEDS_JUSTIFICATION |
| `/ultra-review` | PASS, FAIL_CRITICAL, FAIL_WARNING |
| `/challenge` | PASS, FAIL_CRITICAL, FAIL_WARNING, NEEDS_JUSTIFICATION |

## Empirical justification markers

Every substantive design decision must carry one of these markers. Markers feed the **Justification score** (used in Challenge context) and enable the Refutable-by gate (used in Code Review and Challenge contexts).

| Marker | Meaning | Weight (in justification denominator) |
|--------|---------|----:|
| `[SOURCE]` / `[SOURCE peer-reviewed]` | Claim grounded in a peer-reviewed paper or primary authoritative source. Author byline must be verified at write time (WebFetch on the source URL). | 1.0 |
| `[SOURCE community]` | Claim grounded in a community engineering pattern (production codebase, recognized skill, blog post by domain expert). Not peer-reviewed but verifiable. | 0.7 |
| `[OBSERVED: file:line]` or `[OBSERVED: artifact section]` | Claim grounded in observable state of the codebase or artifact under review. Must point to a real, accessible location. | 0.7 |
| `[INTUITION]` | Author's experience-based judgment without external source. Acceptable but flagged. Reviewers should challenge if > 30% of decisions are `[INTUITION]`. | 0.3 |
| `[ENGINEERING]` | Pragmatic engineering threshold without external scientific source (e.g., "≥80% gate", "5-ADR audit window", "60-day deprecation cutoff"). Counted in denominator at 0.5 — **NOT excluded as a carve-out**. Transparency tag: readers know which numbers are pragmatic engineering choices. | 0.5 |
| (no marker) | Decision without any marker. CRITICAL violation in Challenge context — reviewers must flag. | 0.0 |

### Justification score formula

```
Score = ((SOURCE × 1.0) + (SOURCE community × 0.7) + (OBSERVED × 0.7) + (INTUITION × 0.3) + (ENGINEERING × 0.5) + (no_marker × 0.0)) / total_decisions × 10
```

Where `total_decisions` includes ALL substantive decisions including [ENGINEERING] ones. Per `~/.claude/decisions/agent-synergy-redesign-iter*` discussion: engineering disciplines (Nygard ADR, IETF RFC, IEEE 1471) do not grant denominator-exclusion for engineering thresholds; the [ENGINEERING] marker is a transparency tag, not a carve-out.

### When the marker is "compromised"

A `[SOURCE]` marker whose attribution is verified wrong (incorrect byline, wrong arXiv ID, paper title doesn't match) must be either dropped or re-attributed correctly. Until corrected, weight at 0.7 (penalty equivalent to community source). A reviewer who finds 2+ compromised attributions in a single artifact emits FAIL_CRITICAL — the source-integrity dimension is foundational.

### Counting [ENGINEERING] markers — no consolidation

Each **distinct** [ENGINEERING] threshold is a separate decision in the denominator. Do NOT consolidate multiple thresholds inside a single protocol into one [ENGINEERING] entry — that hides thresholds and inflates the score. If CC-X has 3 [ENGINEERING] thresholds (e.g., a 5-ADR audit window, an ≥80% gate, a 60-day deprecation cutoff), count it as 3, not 1. The transparency tag is per-threshold, not per-protocol.

When the count is ambiguous (e.g., a threshold appears in both the protocol body and the refutability table), count once with the most specific location. State the consolidation rule explicitly if the artefact bundles related thresholds.

### Composition decisions (B/C/D sections inheriting a parent CC)

When a per-agent (B-*) / per-skill (C-*) / per-doc (D-*) section mechanically applies a parent CC, it inherits the parent's marker by default — the design-quality decision lives upstream in the CC, not in the mechanical application.

This is the **charitable** interpretation. The **strict** interpretation would treat compositional decisions as `[OBSERVED: agent-synergy.md]` (weight 0.7) since the mechanical application is just a verifiable reference to the parent decision.

When the score is sensitive to this choice (i.e., the verdict differs between charitable and strict accounting), the artefact MUST show both calculations and justify the chosen interpretation. Silent adoption of the charitable interpretation in a borderline case is the same denominator-favouring pattern as [ENGINEERING] consolidation — flag as a HIGH issue at challenge time.

## Migration from old formats

| Old | New |
|-----|-----|
| SECURE | PASS |
| VULNERABLE_CRITICAL | FAIL_CRITICAL |
| VULNERABLE_WARNING | FAIL_WARNING |
| SENIOR_APPROVED | PASS |
| RETHINK_REQUIRED | FAIL_CRITICAL |
| "Ready to merge" | PASS |
| "Do not merge" | FAIL_CRITICAL |
| "Corrections required" | FAIL_WARNING |

## Parsing (for /team and orchestrators)

1. Look for the exact line `VERDICT: <VALUE>`
2. If absent, look for PASS|FAIL_CRITICAL|FAIL_WARNING|NEEDS_JUSTIFICATION in uppercase within the last 10 lines
3. If still absent: ask the reviewer to reformulate with an explicit VERDICT line. NEVER default to PASS. If after reformulation there is still no verdict → treat as FAIL_WARNING (precautionary principle).

