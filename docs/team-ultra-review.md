# Ultra Review Protocol

This protocol is used by the /ultra-review skill (standalone or via /team STEP 3.5). It reproduces **literally** the Anthropic "Code Review" pattern: 2 compliance scanners (consensus by dual-scan) + 2 bug scanners (consensus by post-hoc validation). Goal: high confidence, <1% false positives. [SOURCE: Anthropic code-review plugin verbatim]

## Parameters

| Parameter | Value | Role |
|-----------|-------|------|
| MAX_PARALLEL_SCANNERS | 4 | 2× Compliance (Sonnet) + 2× Bugs (Opus) |
| SCANNERS_PER_CLASS | 2 | Dual-scan per class (compliance, bugs) |
| MAX_PARALLEL_VERIFIERS | 5 | Cap on concurrent verifiers |
| SCANNER_TIMEOUT | 120s | Max time per scanner |
| VERIFIER_TIMEOUT | 90s | Max time per verifier |
| VERIFY_THRESHOLD | HIGH | Minimum severity to trigger verification (**bug findings only**) |
| FAILURE_BEHAVIOR | keep | Finding kept on timeout/crash/malformed |
| MAX_DIFF_LINES | 2000 | Beyond, truncate and switch to files-only mode |

## Architecture (pipeline flow)

```
PHASE 0: Pre-checks (bash)
         ↓
     [diff.txt, context.md]
         ↓
PHASE 1: Summarize (conditional, >= 500 lines)
         ↓
PHASE 2: PARALLEL REVIEW (4 agents)
|
├── Agent 1: Compliance (Sonnet)  ──┐
├── Agent 2: Compliance (Sonnet)  ──┤─→ findings-compliance.md (dual-scan union)
├── Agent 3: Bugs (Opus)          ──┐
└── Agent 4: Bugs (Opus)          ──┤─→ findings-bugs.md (dual-scan union)
                                      ↓
                                 PHASE 4: Verify (bugs only)
                                      ↓
                                 Each bug finding → 1 verifier (Sonnet, minimal context)
                                      ↓
                                 PHASE 5: Merge compliance (as-is) + verified bugs
                                      ↓
                                 report.md + VERDICT
```

**Key invariants** [SOURCE: Anthropic code-review plugin verbatim]:
- 4 agents = 2 compliance + 2 bugs. No separate security scanner: the relevant security (logic bugs, secrets leaked in the diff) falls under the bug scanner criteria.
- **Bug scanners read ONLY the diff** — forbidden to read the source files. This is the verbatim Anthropic instruction ("Focus only on the diff itself without reading extra context").
- Compliance: the dual-scan IS the consensus filter (no post-hoc validation).
- Bugs: post-hoc validation in Phase 4 (each bug finding → 1 independent verifier).

## Invocation modes

### FULL mode (standalone)

Invocation: `/ultra-review [scope]` or `/team --ultra`
Phases 0-5 complete.
- Input: `git diff [scope]`
- Output: `.claude/tmp/ultra-review/report.md`

### VERIFY-ONLY mode (from /team or standalone)

Invocation: `/ultra-review --verify-only <path>`
Phase 0 (detect) → Phase 3b (parse report) → Phase 4 (verify) → Phase 5 (filter + verdict).
- Input: path to an existing report containing findings [CRITICAL|HIGH|MEDIUM]
- Output: verified report + recomputed verdict

## Phase 0: Pre-checks (bash, ~2s)

**Goal**: Validate that there is something to review and collect the context.

**Actions**:
1. Determine the diff scope (first positional argument of the skill):
   - If positional arg `staged`: `git diff --staged`
   - If positional arg `HEAD~N`: `git diff HEAD~N`
   - If positional arg is a file path: `git diff -- <file>`
   - If `--verify-only <path>`: no diff, enter directly into Phase 3b
   - Otherwise (default): `git diff` (staged if non-empty, otherwise unstaged)
2. Check that the diff is not empty → if empty, abort with a message
3. Count modified lines:
   - If < 5 lines → warning "Very small diff, ultra-review may be overkill"
   - If > MAX_DIFF_LINES (2000) → truncate the diff written to `diff.txt` to its first 2000 lines AND capture `TOTAL_LINES` (raw `wc -l` of the untruncated diff) and `EXCLUDED_LINES=$((TOTAL_LINES-MAX_DIFF_LINES))`. The truncation warning is written in the append block of step 7 (no-silent-caps: a bounded review must declare its bound, never imply full coverage). File attribution of the out-of-scope region is computed there by a single awk pass — no separate file-count variable.
4. Detect the stack (via shell expansion)
5. Write the diff into `.claude/tmp/ultra-review/diff.txt` (overwrite `>`)
6. Write the initial context into `.claude/tmp/ultra-review/context.md` (overwrite `>`): detected stack, scope, modified files, line count
7. Pre-checks — **append** (`>>`) after the initial write of context.md so as not to overwrite it:
   ```bash
   # 7a. Test/hygiene
   TEST_FILES=$(git diff --name-only $SCOPE | grep -E "\.(test|spec)\.|test_|_test\.|(^|/)tests?/|(^|/)__tests__/" | wc -l)
   if [ "$TEST_FILES" -eq 0 ]; then
     echo "WARNING: No test file in the diff" >> .claude/tmp/ultra-review/context.md
   fi
   # 7b. No-silent-caps: if the diff was truncated at step 3, declare the unreviewed
   #     remainder. OUT_OF_SCOPE = every file that has ANY content past the cutoff line,
   #     derived deterministically from the full (untruncated) diff — no file-count var.
   if [ "$TOTAL_LINES" -gt "$MAX_DIFF_LINES" ]; then
     OUT_OF_SCOPE=$(git diff $SCOPE | awk -v cut="$MAX_DIFF_LINES" '
       /^diff --git / { f=$0; sub(/^diff --git a\/.* b\//, "", f) }
       NR>cut && f!="" && !seen[f]++ { print f }
     ' | tr '\n' ' ')
     echo "WARNING: diff truncated at $MAX_DIFF_LINES lines — $EXCLUDED_LINES raw diff line(s) NOT seen by the scanners. Files with content past the cutoff: ${OUT_OF_SCOPE:-<none attributable>}" >> .claude/tmp/ultra-review/context.md
   fi
   ```
   Both 7a and 7b append (`>>`) — each must append independently. The awk anchors on the `diff --git a/… b/<path>` header — present for **every** change type including deletions (`+++ b/` is not: a delete emits `+++ /dev/null`, which would misattribute the dropped lines) — and for any line beyond the cutoff prints that file once. A single file larger than the cutoff lists itself; a deleted large file lists itself; so the out-of-scope list is never empty when lines were dropped. Both warnings are injected into the final report in Phase 5 as MEDIUM findings (see Phase 5, "Wiring with Phase 0" section).

**Critical order**: steps 5/6 use `>` (overwrite), steps 7a AND 7b each use `>>` (append). Using `>` in either of 7a/7b would clobber the step-6 context block and any earlier warning — the silent-truncation failure this very block exists to prevent.

**Early exit**: empty diff → VERDICT: PASS ("Nothing to review")

## Phase 1: Summarize (Sonnet, ~10s) — CONDITIONAL

**Condition**: diff >= 500 lines. For small diffs, Phase 1 is skipped — scanners receive the diff directly.

**Carrier**: a single conditional agent — folded into the Phase 2-4 Workflow as a first `agent('…', {agentType:'Explore', model:'sonnet'})` whose `summary.md` the scanners then receive, or run in-process by the lead before emitting the Workflow. No team, no tmux (it is one agent, not a fan-out that needs panes).

**Brief**:
```
Read the diff at .claude/tmp/ultra-review/diff.txt.
Produce a structured summary:
1. Modified files (list)
2. What changed (1-2 sentences per file)
3. Points of attention (risk areas: auth, DB, input parsing, concurrency)
4. Detected stack

Write the summary into .claude/tmp/ultra-review/summary.md
Short, factual format, no opinions.
```

**Output**: `.claude/tmp/ultra-review/summary.md`

**On failure**: Log warning, continue Phase 2 without summary. Scanners receive the diff directly.

## Phase 2-4 as a Workflow (canonical, per ADR 0017 D-2)

Phases 2-4 are a **pure fan-out** (4 scanners + targeted verifiers, zero dialogue during execution → D-6 fan-out side) and are emitted as ONE native `Workflow({script})` by the lead, after Phase 0/1. This replaces `TeamCreate` + 4 tmux `Agent()` + `_status_` polling + `TeamDelete`. The lead calls the `Workflow` tool with the script below, then runs Phase 5 on its structured return.

Why a Workflow here (and not for, say, the challenge loop): the count is **bounded by spec** (4 scanners + verifiers for HIGH/CRITICAL bugs only — never "fan out until exhaustive"), the returns are **schema-forced** (verdict non-falsifiable, not last-line prose), and the reviewer agents are **reused via `agentType`** so the plugin's curated `code-reviewer` prompt + discipline come for free. The `claudemd_consulted` field is the **governance-echo** (ADR 0017 D-4/D-5): it turns "I checked compliance" from soft prose into a machine-visible output — a compliance scanner that consulted no CLAUDE.md is now visible, not assumed.

```javascript
export const meta = {
  name: 'ultra-review-fanout',
  description: '4 scanners (2 compliance Sonnet + 2 bugs Opus) + verification of HIGH/CRITICAL bug findings',
  phases: [{ title: 'Scan' }, { title: 'Verify' }],
}
const DIFF = '.claude/tmp/ultra-review/diff.txt'
const FINDING = { type:'object', properties:{
  severity:{type:'string',enum:['CRITICAL','HIGH','MEDIUM']}, title:{type:'string'},
  location:{type:'string',description:'file:line'}, evidence:{type:'string'}, fix:{type:'string'},
}, required:['severity','title','location','evidence'] }
// Compliance MUST echo which CLAUDE.md files it consulted (governance-echo, D-4/D-5)
const COMPLIANCE = { type:'object', properties:{
  claudemd_consulted:{type:'array',items:{type:'string'},description:'paths of CLAUDE.md files actually read; [] if none applied'},
  findings:{type:'array',items:FINDING},
}, required:['claudemd_consulted','findings'] }
const BUGS = { type:'object', properties:{ findings:{type:'array',items:FINDING} }, required:['findings'] }
const VERDICT = { type:'object', properties:{
  status:{type:'string',enum:['CONFIRMED','NOT-CONFIRMED']}, evidence:{type:'string',description:'file:line + what you observe'},
}, required:['status','evidence'] }

const COMP_BRIEF = `Audit changes for CLAUDE.md compliance. Read the diff at ${DIFF}. For each modified file, walk up from its directory to the repo root collecting every CLAUDE.md — those are the ONLY compliance sources for that file; list every one you consult in claudemd_consulted (empty array if none apply). Flag ONLY: a clear unambiguous CLAUDE.md violation (quote the rule); compile/parse failure; definitely-wrong-results logic errors; ORPHAN CODE (a new file or exported symbol with 0 callers — verify with grep -rE "import.*<symbol>|<symbol>\\(" excluding the declaration, cite the CLAUDE.md Justifiability rule and the grep command run). Do NOT flag style/subjective/input-dependent issues.`
const BUGS_BRIEF = `Scan for obvious bugs. Focus ONLY on the diff itself at ${DIFF} — do NOT read any other source file. Flag only significant bugs (fails to compile/parse, definitely wrong results); ignore nitpicks and likely false positives.`

phase('Scan')
const [c1, c2, b1, b2] = await parallel([
  () => agent(COMP_BRIEF, { label:'compliance-1', phase:'Scan', agentType:'code-reviewer', model:'sonnet', schema: COMPLIANCE }),
  () => agent(COMP_BRIEF, { label:'compliance-2', phase:'Scan', agentType:'code-reviewer', model:'sonnet', schema: COMPLIANCE }),
  () => agent(BUGS_BRIEF, { label:'bugs-1',       phase:'Scan', agentType:'code-reviewer', model:'opus',   schema: BUGS }),
  () => agent(BUGS_BRIEF, { label:'bugs-2',       phase:'Scan', agentType:'code-reviewer', model:'opus',   schema: BUGS }),
])
const key = f => `${f.location}|${f.title}`
function dedupe(fs){ const m=new Map(); for(const f of fs){ m.has(key(f)) ? (m.get(key(f)).dual=true) : m.set(key(f), {...f}) } return [...m.values()] }
const compliance      = dedupe([c1,c2].filter(Boolean).flatMap(r => r.findings))     // kept ALL (dual-scan consensus)
const claudemd_seen   = [...new Set([c1,c2].filter(Boolean).flatMap(r => r.claudemd_consulted))]
const bugs            = dedupe([b1,b2].filter(Boolean).flatMap(r => r.findings))

// Phase 4 — only HIGH/CRITICAL bug findings are verified; compliance + MEDIUM are not.
// `--no-verify` (passed as args.noVerify) skips Phase 4: the scanners are trusted, no spawns.
const toVerify = bugs.filter(f => f.severity==='HIGH' || f.severity==='CRITICAL')
let verified
if (args && args.noVerify) {
  verified = toVerify.map(f => ({ ...f, verified: '[unverified-trusted]' }))   // Phase 4 skipped, kept at severity
} else {
  phase('Verify')
  verified = (await parallel(toVerify.map(f => () =>
    agent(`Independently verify this single claim — you MAY read source files. Claim: "${f.title}" at ${f.location}. Reply CONFIRMED only if you observe it yourself; you receive no other context.`,
          { label:`verify:${f.location}`, phase:'Verify', model:'sonnet', schema: VERDICT })
      .then(v => ({ ...f, verified: v?.status==='CONFIRMED' ? '[verified]' : '[unverified]' }))))).filter(Boolean)
}

return {
  compliance,                                   // all kept; lead recomputes verdict
  claudemd_consulted: claudemd_seen,            // governance-echo surfaced to the lead
  bugs_kept: verified.filter(f => f.verified !== '[unverified]'),       // [verified] or [unverified-trusted] → count toward verdict
  bugs_dropped: verified.filter(f => f.verified === '[unverified]'),    // refuted by Phase 4 → informational only
  bugs_medium: bugs.filter(f => f.severity==='MEDIUM'),
}
```

The lead reads this return and runs Phase 5 (verdict + report). If `claudemd_consulted` is empty while CLAUDE.md files existed for the changed paths, the lead adds a MEDIUM `[source:governance-echo] compliance scan consulted no CLAUDE.md` — the soft read is now auditable. Phase 5's existing `WARNING:`→MEDIUM wiring is unchanged.

## Phase 2: Parallel Review — detailed briefs (carried verbatim into the Workflow script above)

The 4 scanners form two dual-scan pairs: 2× Compliance (native consensus via union of findings) + 2× Bugs (consensus by post-hoc validation in Phase 4). [SOURCE: Anthropic code-review plugin verbatim] The briefs below are the authoritative wording; they are embedded as `COMP_BRIEF`/`BUGS_BRIEF` in the script.

**Important note**: Anthropic does **not** have a separate security scanner. The security relevant to a diff review (leaked secrets, logic bugs creating a vulnerability) is included in the bug scanner criteria ("will definitely produce wrong results"). Deep OWASP analyses outside review remain the role of the `security-reviewer` agent.

### Agents 1 & 2: Compliance Scanners (Sonnet ×2)

These are the **two `compliance` `agent()` calls** of the Workflow script above (`agentType:'code-reviewer'`, `model:'sonnet'`, `schema: COMPLIANCE`) — not tmux spawns. `COMP_BRIEF` is the abbreviated form of the authoritative instruction; the full wording (incl. the orphan-code justifiability check) is folded into `COMP_BRIEF` in the script. Output is the `COMPLIANCE` schema (`findings[]` + `claudemd_consulted[]`), returned in-band — no `.md` file written.

**Scope**: compliance scanners read the diff and the applicable `CLAUDE.md` files (walk up from each changed file to the repo root). They DO NOT read full source files. Each finding: `severity`, `title`, `location` (file:line), the quoted CLAUDE.md rule in `evidence`, `fix`. `claudemd_consulted` MUST list every CLAUDE.md actually read (the governance-echo: an empty list while CLAUDE.md files existed is itself a Phase-5 MEDIUM).

### Agents 3 & 4: Bug Scanners (Opus ×2)

These are the **two `bugs` `agent()` calls** of the Workflow script (`agentType:'code-reviewer'`, `model:'opus'`, `schema: BUGS`). `BUGS_BRIEF` carries the verbatim instruction.

**Scope**: bug scanners read **ONLY the diff** (`.claude/tmp/ultra-review/diff.txt`). Absolute prohibition on reading source files, files around the diff, or any other project file — verbatim Anthropic, **non-negotiable**. They flag only: compile/parse failure, definitely-wrong-results logic errors. They do NOT flag style/subjective/input-dependent issues. Output is the `BUGS` schema (`findings[]`), returned in-band — no `.md` file written.

## Phase 3: Merge & Dedup (~2s, lead, no agent)

> **Mode note**: in **FULL mode**, Phase 3 dedup and Phase 4 verification run **inside the Phase 2-4 Workflow** (the `dedupe()` step and the `Verify` pipeline stage of the canonical script) — the lead receives an already-deduped, already-verified structured return; the `scan-*.md` / `findings-*.md` files below are the **VERIFY-ONLY mode** representation (parsing an external report), not written in FULL mode. The stream logic, severities, and consensus rules are identical in both modes — only the carrier differs (structured object vs `.md`).

**Key principle**: two **distinct streams** are maintained — compliance and bugs. Each stream has its own consensus.

| Stream | Source files | Consensus | Phase 4 validation |
|--------|--------------|-----------|--------------------|
| Compliance | `scan-compliance-1.md`, `scan-compliance-2.md` | Dual-scan (union of findings) | **NO** — the dual-scan IS the filter |
| Bugs | `scan-bugs-1.md`, `scan-bugs-2.md` | Dual-scan + post-hoc validation | **YES** — each finding → 1 verifier |

The two streams are NEVER merged together. They are kept distinct until the final report.

### Phase 3a — FULL mode (after Phase 2)

**Compliance stream**:
1. Parse `scan-compliance-1.md` and `scan-compliance-2.md` (if one is missing: treat as scanner failure, continue with the other)
2. **Union by `file:line`**: if EITHER agent 1 or 2 finds a finding, keep it. If both find the same `file:line`, merge the descriptions and keep the higher severity.
3. Mark each finding with `source:compliance-{1|2|1+2}` (which agent found it)
4. Write into `.claude/tmp/ultra-review/findings-compliance.md`

**Bugs stream**:
1. Parse `scan-bugs-1.md` and `scan-bugs-2.md` (same tolerance as above)
2. **Union by `file:line`**: same logic as compliance
3. Mark with `source:bugs-{1|2|1+2}`
4. Write into `.claude/tmp/ultra-review/findings-bugs.md`

5. Count per stream: `compliance_{criticals,highs,mediums}` and `bugs_{criticals,highs,mediums}`
6. **Early exit**: if `compliance_criticals + compliance_highs + bugs_criticals + bugs_highs == 0` → skip Phase 4, go directly to Phase 5 (only MEDIUM or 0 finding)

### Phase 3b — VERIFY-ONLY mode (direct entry, after Phase 0)

This mode comes from an external report (code-reviewer of /team STEP 3.5). The parsed findings **all** go into the `bugs` stream (no compliance dual-scan available — so the post-hoc validation of Phase 4 is necessary for consensus).

1. Read the report provided via `--verify-only <path>`
2. Parse the findings with a **multi-format parser**. The regexes below all support an **optional emoji prefix** (red circle critical, yellow circle warning, green circle suggestion) because the `code-reviewer` and `security-reviewer` agents produce their headings with these emojis (e.g.: `## 🔴 Critiques (bloquant)`):
   - **Inline tags format**: lines containing `[CRITICAL]`, `[HIGH]`, `[MEDIUM]`
   - **Heading-based code-reviewer format**: regex `^#{1,3}\s+(?:🔴\s+)?Critiques` / `^#{1,3}\s+(?:🟡\s+)?Warnings` / `^#{1,3}\s+(?:🟢\s+)?Suggestions` — matches `## 🔴 Critiques (bloquant)`, `## Critiques`, `### 🟡 Warnings`, etc.
   - **Heading-based security-reviewer format**: regex `^#{1,3}\s+(?:🔴\s+)?Critiques` / `^#{1,3}\s+(?:🟡\s+)?Warnings` — matches `### 🔴 Critiques (exploitation immediate possible)`, `### 🟡 Warnings (risque modere)`
   - **Fallback heuristic**: lines starting with `- ` under headings matching `(?:[🔴🟡🟢]\s+)?(?:Critique|Critical|Warning|High|Bloquant)` (case-insensitive, optional emoji)
3. If no format is recognized → abort with an error message listing the supported formats
4. Normalize: extract title, file:line, description, assign severity:
   - `## 🔴 Critiques` / `## Critiques` / `[CRITICAL]` → CRITICAL
   - `## 🟡 Warnings` / `## Warnings` / `[HIGH]` → HIGH
   - `## 🟢 Suggestions` / `## Suggestions` / `[MEDIUM]` → MEDIUM

**Why**: STEP 3.5 of /team invokes `--verify-only` on the `code-reviewer` report, which produces its headings with emoji (see `agents/code-reviewer.md:105-117` and `agents/security-reviewer.md:136-152`). Those headings are **English** (`## 🔴 Critical (blocking)`), so the French `Critiques` primary regexes above match them through the case-insensitive fallback heuristic, not the primary pattern — keep the fallback. A parser that only matches the emoji-less version would break the main use case.
5. Write into `.claude/tmp/ultra-review/findings-bugs.md` (bugs stream). `findings-compliance.md` remains empty in this mode.
6. If 0 HIGH/CRITICAL → early exit, VERDICT inherits the verdict of the original report

### Format of findings-compliance.md / findings-bugs.md

```
## Findings — {compliance|bugs} stream
Total: X (C criticals, H highs, M mediums)

### Finding 1
- Severity: CRITICAL
- Source: compliance-1+2 (found by both agents) | compliance-1 | compliance-2 | bugs-1+2 | bugs-1 | bugs-2
- DualConfirmed: true/false (true if `source` contains `1+2` — both agents converged independently)
- Title: [title]
- File: [file:line]
- Description: [description]
- Suggestion: [fix]
- CLAUDE.md rule quoted: [compliance stream only]

### Finding 2
...
```

**Early exit**: If 0 HIGH and 0 CRITICAL combined across both streams → skip Phase 4, go directly to Phase 5.

## Phase 4: Verify (Sonnet subagents, parallel, ~20-40s)

**Critical scope — BUG FINDINGS ONLY** [SOURCE: Anthropic code-review plugin verbatim]

> "For each issue found in the previous step **by agents 3 and 4**, launch parallel subagents to validate the issue."

Anthropic explicitly specifies that validation only applies to findings from agents 3 & 4 (bugs). Findings from agents 1 & 2 (compliance) **do NOT go through** Phase 4: their consensus is the dual-scan.

**Input**: `findings-bugs.md` only. `findings-compliance.md` is skipped.

For each HIGH or CRITICAL finding from the bugs stream, an independent verifier confirms or refutes.

**Carrier**: in FULL mode this is the `Verify` pipeline stage of the canonical Workflow — one `agent(…, {model:'sonnet', schema: VERDICT})` per HIGH/CRITICAL bug finding, no barrier, scheduler-bounded concurrency. In VERIFY-ONLY mode (no Workflow was emitted for scanning) the lead emits a small verify-only Workflow with just this stage, or runs the verifiers in-process. Either way the verifier reuses `agentType:'code-reviewer'` and the minimal-context protocol below.

### Confirmation-bias-resistant protocol

For each HIGH/CRITICAL bug finding, spawn a verifier subagent with ONLY:

```
Independently verify this claim:

CLAIM: "[finding title in 1-2 sentences]"
FILE(S): [path(s)]
LINES: [range if known]

Read the code at the indicated location(s). Analyze independently.
Reply in the EXACT format:

STATUS: CONFIRMED | NOT-CONFIRMED
EVIDENCE: [file:line + explanation of what you observe]
```

**WHAT THE VERIFIER DOES NOT RECEIVE**:
- The full scanner report
- The other findings
- The original scanner's reasoning
- The severity assigned by the scanner

This forces an independent assessment, free of confirmation bias.

**Note**: unlike the bug scanners (Phase 2, agents 3 & 4) which see ONLY the diff, the Phase 4 verifier CAN read the source files. This is the difference between "high-signal superficial scanner" and "targeted validator with minimal context".

### Parameters

| Parameter | Value | Justification |
|-----------|-------|---------------|
| MAX_PARALLEL_VERIFIERS | 5 | Caps concurrent spawns |
| TIMEOUT_PER_VERIFIER | 90s | The verifier must read code |
| FAILURE_BEHAVIOR | Keep finding as-is | Precautionary principle — timeout/crash → finding stays at its original severity, marked [unverified-timeout] |
| VERIFY_THRESHOLD | HIGH | Applies to **bug findings only** (compliance is skipped) |

**Grouping**: If more than 5 HIGH/CRITICAL bug findings, group into batches of 5.

## Phase 5: Filter + Verdict + Report (~5s, lead, no agent)

### Filtering logic

1. **Compliance findings** (`findings-compliance.md`): keep **ALL** findings as is. Compliance dual-scan is the native consensus — no post-hoc validation, no downgrade. Each finding keeps its original severity and its `compliance-{1|2|1+2}` source.
   - If `source` contains `1+2` → add the `[dual-confirmed]` tag (the 2 agents converged independently = maximum confidence)
2. **Bug findings** (`findings-bugs.md` + Phase 4 results):
   - CONFIRMED → mark `[verified]`, keep the original severity
   - CONFIRMED + `source:bugs-1+2` → mark `[verified] [dual-confirmed]` (3 agents agree = maximum confidence)
   - NOT-CONFIRMED → mark `[unverified]`, downgrade to informational (does NOT count toward the verdict)
   - TIMEOUT → mark `[unverified-timeout]`, keep the severity (precaution)
3. **MEDIUM bug findings**: do not go through verification (VERIFY_THRESHOLD = HIGH) → keep as is, do not count toward the verdict.
4. Recompute the verdict counts on: **compliance findings (all)** + **bug findings CONFIRMED + TIMEOUT**.

### Wiring with Phase 0 (context.md)

**Read `.claude/tmp/ultra-review/context.md`** and look for lines starting with `WARNING:`. Each detected warning is injected into the final report as a MEDIUM finding, source `phase-0-precheck`.

Example: if Phase 0 wrote `WARNING: No test file in the diff`, add to the MEDIUM section:
```
- [source:phase-0-precheck] No test file in the diff — Impact: regressions undetectable — Fix: add tests covering the change
```

Without this wiring, the warning is lost. MEDIUM findings from Phase 0 do not count toward the verdict (same treatment as other MEDIUM) but appear in the final report.

### Verdict computation

Reference: `~/.claude/docs/verdict-protocol.md`, "Code Review" context.

Combined counts (compliance + bugs verified/timeout):

| Condition | Verdict |
|-----------|---------|
| 0 CRITICAL, 0 HIGH | PASS |
| 0 CRITICAL, 1-3 HIGH | FAIL_WARNING |
| >= 1 CRITICAL OR > 3 HIGH | FAIL_CRITICAL |

### Final report format

Output: `.claude/tmp/ultra-review/report.md`

```markdown
# Ultra Review Report

## Summary
- Scope: [diff description]
- Files analyzed: [N]
- Lines changed: [N]
- Agents: 2× Compliance (Sonnet) + 2× Bugs (Opus) [SOURCE: Anthropic code-review plugin verbatim]

## Compliance Findings (dual-scan consensus, no post-hoc validation)

### CRITICAL
- [dual-confirmed] [source:compliance-1+2] Title — file:line — CLAUDE.md rule quoted — Evidence — Fix

### HIGH
- [source:compliance-1] Title — file:line — CLAUDE.md rule quoted — Evidence — Fix

### MEDIUM
- [dual-confirmed] [source:compliance-2+1] Title — file:line — CLAUDE.md rule quoted — Evidence — Fix

## Bug Findings (post-hoc validated)

### CRITICAL
- [verified] [dual-confirmed] [source:bugs-1+2] Title — file:line — Description — Fix

### HIGH
- [verified] [source:bugs-1] Title — file:line — Description — Fix

### MEDIUM (not submitted for verification)
- [source:bugs-2] Title — file:line — Description — Fix

## Unverified Bugs (informational, not blocking)
- [unverified] Title — file:line — Reason: [verifier's justification]

## Confidence Legend
- `[dual-confirmed]` = found by the 2 agents of the same class independently (native consensus)
- `[verified]` = confirmed by an independent verifier agent (post-hoc validation)
- `[verified] [dual-confirmed]` = 3 agents agree (native consensus + validation) = maximum confidence
- `[unverified]` = not confirmed by the verifier, downgraded to informational

## Verification Stats
- Compliance findings: [N] (dual-scan consensus, no validation performed)
- Bug findings submitted for verification: [N]
- Confirmed: [N] ([%])
- Not confirmed: [N] ([%])
- Timeout: [N]

## VERDICT: PASS | FAIL_CRITICAL | FAIL_WARNING
```

### Cleanup

None. FULL mode emits a `Workflow` (no team, no panes) → nothing to tear down; the zombie-pane / ghost-`TeamDelete` failure mode is structurally gone. VERIFY-ONLY mode runs no scanner team either.

## Resilience and error handling

Each phase can fail. Default behavior: **graceful degradation** rather than abort.

| Component | Failure type | Behavior |
|-----------|--------------|----------|
| Summarizer (Phase 1) | Crash, timeout, empty output | Log warning, continue Phase 2 WITHOUT summary |
| Individual scanner (Phase 2) | Crash, timeout (>120s), malformed output | Log warning, continue with the remaining scanners. Note: if ONE agent of a dual-scan pair (e.g.: compliance-1) goes down but the other (compliance-2) passes, the stream continues in degraded mode with a single scanner — no real dual-scan consensus, but findings preserved. |
| An entire pair (compliance OR bugs) fails | Both agents of the pair crash | The affected stream is empty. The other stream continues. The report notes the missing stream. |
| ALL scanners (Phase 2) | All 4 fail | Abort. VERDICT: FAIL_WARNING (precaution) |
| Individual verifier (Phase 4) | Crash, timeout (>90s), malformed output | Treat the bug finding as [unverified-timeout] — keep the original severity |
| ALL verifiers (Phase 4) | All N fail | Keep ALL bug findings as is. The report notes "verification unavailable". Compliance findings are NOT affected (they do not go through Phase 4). |
| Missing intermediate file | E.g.: scan-bugs-1.md not found | Treat as scanner failure — log warning, continue |
| Malformed input report (verify-only) | Unparseable format | Abort. Error message listing the supported formats |

**Fundamental principle**: when in doubt, DO NOT downgrade. An unverified finding stays at its original severity.

## Handling large diffs

The bug scanners (agents 3 & 4) CANNOT read the source files — that is the verbatim Anthropic constraint. The strategy for large diffs must therefore stay "diff-only".

| Diff size | Behavior |
|-----------|----------|
| < 500 lines | Normal — full diff goes to the 4 scanners |
| 500-2000 lines | Warning displayed. Summary (Phase 1) generated. The 4 scanners receive the full diff; the summary helps prioritize the risk areas. The compliance scanners can additionally consult the applicable CLAUDE.md files. |
| > 2000 lines | Diff truncated to MAX_DIFF_LINES. The 4 scanners receive the truncated version + the full list of modified files (via `git diff --name-only`) at the top. The Phase 1 summary becomes critical. **Bug scanners remain constrained to the truncated diff — they NEVER read the source files** (Anthropic verbatim). Degraded coverage assumed: for an exhaustive review of a diff > 2000 lines, split into several commits. |

## Exit gates

- **Phase 0**: empty diff → VERDICT: PASS immediate
- **Phase 3a/3b**: 0 HIGH/CRITICAL combined (compliance + bugs) → skip Phase 4, go directly to Phase 5
- **Phase 5**: final verdict based on **compliance findings (all, dual-scan)** + **bug findings verified/timeout**. Bug findings not-confirmed are downgraded to informational and do not count.

## /team integration

### STEP 3.5 — VERIFY-ONLY mode

The lead invokes `/ultra-review --verify-only .claude/tmp/{team-name}/review-report.md` after the standard STEP 3.

```
STEP 3: code-reviewer → review-report.md (PASS/FAIL)
  If FAIL with HIGH/CRITICAL:
    STEP 3.5: /ultra-review --verify-only review-report.md
    → verified findings, verdict recomputed
  If PASS:
    Skip STEP 3.5
```

### --ultra option — FULL mode

Replaces STEP 3 + 3.5 with a full ultra-review: 4 parallel scanners (2 compliance + 2 bugs) + post-hoc validation of bug findings + full report.

```
STEP 3+3.5: /ultra-review staged
  → 4 parallel agents (2× compliance Sonnet + 2× bugs Opus)
  → post-hoc validation of bug findings (bugs only)
  → full report + verdict
```

**Interaction with STEP 4 (correction loop)**: the re-review after correction is done by a regular code-reviewer (not a re-run of ultra-review). Ultra-review is a one-shot high-signal filter, not an iterative tool.

