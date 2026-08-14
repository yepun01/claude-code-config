---
description: When a task requires several coordinated agents (feature, complex bug, refactoring, audit)
argument-hint: <feature or task to implement> [flags]
---

## Project context
- Stack: !`cat package.json 2>/dev/null | head -5 || cat requirements.txt 2>/dev/null | head -5 || echo "Stack non detectee"`
- Structure: !`ls src/ 2>/dev/null || ls app/ 2>/dev/null || ls -d */ 2>/dev/null | head -10`
- Latest commits: !`git log --oneline -10 2>/dev/null || echo "Pas de repo git"`
- Current diff: !`git diff --stat 2>/dev/null`

## Goal

Orchestrate a team of agents to: $ARGUMENTS

## PHILOSOPHY: MINIMAL DEFAULT, OPT-IN CEREMONY

By default, the pipeline is **minimal and fast**: no Interview 95%, no ROI gate, no Challenge loops, no Ultra-review, no blocking validation workflow. A senior who knows what they want runs `/team <task>` and gets a direct pipeline.

**The full ceremony is opt-in** via `--ceremony` (or unit flags `--interview`, `--challenge`, `--criteria`, `--roi`). Ultra-review is on by default (override: `--no-ultra`).

### When to activate the ceremony
- Big task (L/XL, multiple modules) or ill-defined → `--ceremony`
- Critical prod bug, system poorly mastered → `--ceremony`
- Simple feature on a known stack → minimal default
- Clear bugfix → minimal default

## PREREQUISITES

If `$ARGUMENTS` is empty, ask via AskUserQuestion what needs to be done. Do not start anything without a clear goal.

## YOUR ROLE

You are the LEAD. You NEVER code yourself. You analyze the task, you decide which teammates to spawn, you coordinate, you re-inject context, you manage the lifecycle of each teammate.

You run in the main session. The harness runs a **single implicit team** (TeamCreate/TeamDelete removed in v2.1.178 — nothing to create or tear down). **Dialogue teammates** (roles that round-trip with the lead during execution) = in-process agents spawned via `Agent(subagent_type=X, name=<role>, model="opus")`, communicating via `SendMessage` (address = the spawn `name`). **Fan-out stages** (N independent agents, zero round-trip during execution) = one native `Workflow({script})` call instead (rule 18, ADR 0017). Spawn on Opus — the agent frontmatter already pins it; state `model: "opus"` at the spawn anyway, so a frontmatter edit cannot silently downgrade a run.

**Delivery via SendMessage**: sub-agents cannot always use `Write` (sandbox). When a teammate must deliver a bulky artifact (report, code), ask them to send it via SendMessage to the lead — you write it yourself in `.claude/tmp/{team-name}/`.

## SHARED FILES

Bulky artifacts (archi, reports) → files in `.claude/tmp/{team-name}/`, where `{team-name}` is the **run id** picked at STEP 2 (`auto-<timestamp>` — it names the tmp folder and the rule-14 dedup keys; no team object exists anymore). Teammates receive the **path**, not the content. Single source of truth, zero degradation.

Conventions:
- `arch.md` — architecture document (written by the architect or the lead)
- `criteria.md` — acceptance criteria (if `--criteria`)
- `final-report.md` — consolidated report (audits)

## FLAGS

### Opt-in ceremony
- `--ceremony` or `--full`: activates Interview + ROI + Criteria + Challenge archi + Challenge code (ultra-review is already on by default)
- `--interview`: Interview 95% only (clarify hypotheses)
- `--roi`: ROI gate only (effort/value)
- `--criteria`: generates `criteria.md` (must-pass + DoD)
- `--challenge`: adversarial archi + code loops
- `--challenge-arch` / `--challenge-code`: only one of the two
- `--arch`: forces the Architecture step even for a small task
- `--paranoid`: alias for `--ceremony`

### Opt-out
- `--no-test`: skips test validation
- `--no-review`: skips the review
- `--no-ultra`: uses light review (1 reviewer) instead of the default ultra-review
- `--plan-only`: produces only the architecture, does not implement
- `--review-only`: review on existing code, no implementation
- `--auto`: no confirmation between steps (for tests/CI)
- `--parallel`: several devs in parallel per module (big feature)
- `--keep-artifacts`: does not delete `.claude/tmp/{team-name}/` at the end
- `--no-route`: skip STEP 0c skill routing; force the multi-agent pipeline even if `$ARGUMENTS` matches another skill
- `--no-gc`: skip the STEP 0bis orphan GC (alias env `TEAM_NO_GC=1`)
- `--strict`: brief-validation block mode (missing section / notification channel → BLOCKED instead of warning)
- `--verify-sources`: research/exploration only — adds the Source N-Refuters stage (3rd independent byline layer, emitted as a Workflow)

### Defaults summary
**By default**: direct to implementation + **ultra-review** (4 parallel scanners) + tests. No waiting, no questions unless `$ARGUMENTS` is ambiguous.

## STRICT RULES

_Placed high on purpose: after compaction a skill body is re-injected **capped at 5 000 tokens, keeping the START of the file** — these invariants must stay above that cut. Do not push them down._

1. Default = minimal. Ceremony = opt-in via flags.
2. **ALWAYS** pass an explicit `name` AND an explicit `model` override in each dialogue `Agent()` call (`model: "opus"` — same value as the frontmatter default, stated explicitly so a frontmatter edit cannot silently downgrade a run; same in Workflow scripts via `opts.model: 'opus'`). The `mode` param is deprecated/ignored — spawns inherit the session's permission mode
3. **NEVER** code yourself — you are the lead
4. **NEVER** exceed max iterations: 5 for challenge, 3 for review/fix, 3 for test/fix (independent)
5. **NEVER** rewrite an agent's instructions — it loads its system prompt automatically
6. **ALWAYS** forward the full context to each teammate
7. **ALWAYS** shutdown dialogue teammates (shutdown_request) as soon as their deliverable is validated
8. The dev fixes their own bugs — no separate "fixer" agent
9. **ALWAYS** use TaskCreate/TaskUpdate to track progress
10. Tests are not optional (except `--no-test`)
11. **NEVER** copy the content of an artifact > 200 words into a prompt — always give the path
12. **LEAD alone** creates `.claude/tmp/{team-name}/` with `mkdir -p` BEFORE any `Agent()` spawn. Verify existence: `[ -d .claude/tmp/{team-name} ] || { echo ERROR-MKDIR; exit 1; }`. If error → BLOCKED immediately (escalate to user, no retry).
13. If architecture produced, preserve it before cleanup (mv `.claude/tmp/{team-name}/arch.md` to `.claude/decisions/NNNN-<slug>.md`)
14. **Dedup teammate messages (anti phantom re-delivery)**: once a teammate X has sent `STATUS: DONE` for task T, `TaskUpdate(taskId=T, metadata={"delivered_by": "X", "delivered_at": <timestamp>})`. `delivered_by` equals `<run-id>/<agent_name>` (run id = `{team-name}` from STEP 2) to avoid collision between two agents of the same `subagent_type` in the same pipeline (e.g.: two `code-reviewer` in ultra-review). Any later `idle_notification` or re-delivery from X → IGNORE silently; only `shutdown_response` is expected. Before processing a message from X: check `TaskGet(T).metadata.delivered_by == "<run-id>/X"` → if yes, IGNORE.
15. **Fan-out capacity is scheduler-governed**: Workflow `agent()` calls are capped automatically (min(16, cores−2) concurrent; excess queues). Do not hand-manage concurrency. Keep one workflow under ~15 agents unless the pipeline spec demands more.
16. **Shutdown timeout 30s**: after `SendMessage(type=shutdown_request)`, wait 30s for the `shutdown_response`. Received → clean shutdown. Not received after 30s → log "X timeout" and move on (close its task row per rule 17, run the STEP 6 process check) — there is no registry teardown to block on.
17. **Lifecycle task auto-cleanup**: before ANY teammate shutdown, `TaskUpdate(taskId, status="completed")` if their work was delivered. If the teammate shuts down without having delivered (BLOCKED/timeout): `TaskUpdate(owner=null, status="pending")` to allow reassignment.
18. **Agent() for dialogue, Workflow for fan-out** (amended per ADR 0017 D-3): a **dialogue teammate** — one that round-trips during execution (architect ↔ lead, NEEDS_CONTEXT recovery, challenge-loop creator/challenger) — MUST be spawned via `Agent()` with an explicit `name` (its SendMessage address in the single implicit team) AND an explicit `model`. A **fan-out stage** — N independent agents with zero teammate↔teammate or teammate↔human round-trip *during* execution (ultra-review's 4 scanners, N-refuter panels, research sweeps; D-6 frontier) — SHOULD instead be emitted as a native `Workflow({script})`: the lead calls the `Workflow` tool, whose `agent()` calls reuse the plugin's agents via `agentType:'<agent>'` and force a verdict `schema`. A skill whose instructions call `Workflow` counts as a legitimate ultracode opt-in — no per-invocation keyword needed. The fan-out count is **bounded by the pipeline spec** (ultra-review = exactly 4 scanners + verifiers for HIGH/CRITICAL only), never "fan out until exhaustive". An unnamed dialogue agent cannot be pinged or continued via SendMessage — name every dialogue spawn. Skills with multiple `Agent(...)` that are pure fan-out (`ultra-review`) emit a Workflow; skills that need dialogue keep named in-process agents.
19. **5 mandatory brief sections + explicit notification channel (cf. ADR 0001)**: each brief before `Agent()` spawn must contain the 5 named sections `## Contexte`, `## Objectif`, `## Livrable`, `## Teammates`, `## Protocole de fin`, AND at least one word among `SendMessage|inbox|_status_` (notification channel). `grep` validation (cf. CONTEXT TO FORWARD section). Warning mode by default, block mode if `--strict`. Closes RC2 of the ADR 0001 diagnostic (50% of historical briefs omitted SendMessage). The common "Team communication protocol" block inserted in the 9 base + 8 control `agents/*.md` (Layer 1 ADR 0001) guarantees the sub-agent's task end on the system-prompt side — rule 19 guarantees the reminder on the lead's disposable brief side.

## MINIMAL PIPELINE (default)

### STEP -1: LOAD ORCHESTRATION TOOL SCHEMAS (hard gate, before anything else)

The team tools are **deferred**: calling one without its schema loaded fails with a silent `InputValidationError` (root cause of a full-pipeline rollback already observed). Before ANY other step:

1. Run `ToolSearch(query="select:TaskCreate,TaskUpdate,TaskGet,TaskList,SendMessage", max_results=10)`.
2. Verify every one of these 5 schemas appears in the result.
3. If ANY schema is missing → STOP. Report `BLOCKED [tool schema missing: <names>]` to the user. Do NOT proceed to STEP 0, do NOT spawn anything.

### STEP 0: PROJECT CONTEXT (systematic prerequisite)

Before any spawn, **read `./CLAUDE.md` if present** (current repo). Extract the `Architecture`, `Structure`, `Stack`, `Conventions`, `Rules` sections, or any equivalent section.

Store these sections under `CONTEXTE_PROJET`. You will **inline** them in the brief of each sub-agent (not a link — inline, because the sub-agents start cold and do not automatically read this file).

If no local `CLAUDE.md` → continue without.

**Orientation graph (Graphify, ADR 0019)**: if `graphify-out/GRAPH_REPORT.md` exists, refresh it when stale (`[ graphify-out/graph.json -ot "$(git rev-parse --git-dir)/HEAD" ] && graphify update .` — AST-only, seconds), then append one line to `CONTEXTE_PROJET`, inlined in every brief: `Orientation: graphify-out/GRAPH_REPORT.md + graphify query "<question>" --context call --context import before broad greps ([SOURCE]); verification claims stay [OBSERVED] on the working tree.` If absent → continue without (never initialize it yourself — that is the user's `/graphify init` call).

### STEP 0bis: GC ORPHANS (auto-skip if empty)

Run `~/.claude/hooks/team-gc.sh` (dry-run by default, threshold 7 days).
- Exit 0 → continue silently
- Exit 1 → display the summary, ask the user via AskUserQuestion "Cleanup ces N orphans ?"
  - Yes → re-run with `--force`
  - No → continue without cleaning

Skip this step if flag `--no-gc` or env `TEAM_NO_GC=1`.

### STEP 0ter: SKILL ROUTING (delegate before spawning a team)

`/team` is the promoted entry point of the plugin, but ~10 other invokable skills exist (`/commit`, `/premortem`, `/challenge`, `/discuss`, `/spec`, `/learn`, `/ultra-review`, `/dream`, `/improvement-monitor`, `/evals`). Before falling into the multi-agent pipeline, check if `$ARGUMENTS` clearly matches one of them — if so, delegate via the `Skill` tool and return.

| User intent in `$ARGUMENTS` | Delegate to |
|---|---|
| "commit", "stage all", "create a commit", "conventional commit" | `/commit` |
| "premortem", "what could go wrong", "risks of X before launch" | `/premortem` |
| "challenge", "stress-test this decision", "adversarial on X" | `/challenge` |
| "discuss", "exploratory", "let's talk about / réfléchir à" | `/discuss` |
| "spec out", "write a spec", "manage ADRs" | `/spec` |
| "learn from this", "capture lesson", "persist knowledge" | `/learn` |
| "ultra-review only", "4-scanner audit" | `/ultra-review` |
| "audit memory", "stale memory", "dream" | `/dream` |
| "what's new in CC", "monthly monitor", "check changelog" | `/improvement-monitor` |
| "run evals", "evaluate X" | `/evals` |

Routing rules:
- Match must be **unambiguous**: if `$ARGUMENTS` could plausibly fit 2+ skills, do NOT route — fall through to STEP 1 so the multi-agent pipeline can disambiguate.
- If routed: call `Skill(skill="<matched>", args="$ARGUMENTS")`, surface its output, done. Do **not** create a team.
- The user can always invoke skills directly (`/commit`, `/premortem`, …). Two-tier intentional: `/team` is the muscle-memory entry, the others remain power-use shortcuts.
- Skip this step if flag `--no-route` (force the multi-agent pipeline even when a skill matches).

If no clear match → fall through.

### STEP 1: DETECTION (fast, no question)

Detect the type from `$ARGUMENTS`:

| Detected pattern | Pipeline |
|---|---|
| "fix", "bug", "corrige", "erreur" | Bug |
| "review", "audit", "analyse" | Review |
| "design", "UI", "composant" | UI |
| "explore", "comprendre", "documenter" | Exploration |
| everything else (including "refactor", "clean", "rename") | Feature |

If ambiguous (multiple patterns) → ask 1 short question via AskUserQuestion, 2 options max.

### STEP 2: SPAWN AGENTS

Pick the run id: `{team-name}` = `auto-<timestamp>` (no team to create — the harness runs a single implicit team). Then create the tmp folder with guard (rule 12):

```bash
mkdir -p .claude/tmp/{team-name}/
[ -d .claude/tmp/{team-name} ] || { echo "ERROR-MKDIR: cannot create .claude/tmp/{team-name}/"; exit 1; }
```

If `mkdir` fails → BLOCKED immediately (no retry, escalate to user).

**Vehicle per phase shape (rule 18, ADR 0017)**: a fan-out stage (ultra-review's 4 scanners, parallel auditors/spec-writers/testers) = one `Workflow({script})` call — `agent()` with `agentType:'<agent>'`, a verdict `schema`, and `opts.model:'opus'`; a dialogue role (architect↔lead, dev fix rounds) = an `Agent()` teammate spawned with an explicit `name`.

Depending on the pipeline:
- **Bug**: deep-analyzer → developer → tester
- **Feature**: (architect if L/XL otherwise skip) → developer → ultra-review (code-reviewer if `--no-ultra`) → tester
- **UI**: designer → developer → code-reviewer
- **Review**: code-reviewer (read-only, delivers report)
- **Exploration**: deep-analyzer or general-purpose (read only). If the deliverable carries `[SOURCE]` citations whose bylines load-bear a decision, add the **Source N-Refuters** stage (`--verify-sources`, 3rd independent byline layer — see `~/.claude/docs/team-pipelines.md`).

Refactoring is treated as a Feature: `developer` modifies the existing code, `code-reviewer` validates, `tester` confirms non-regression.

Size (L/XL) = heuristic detection: if `$ARGUMENTS` mentions "gros", "multi", "refonte", "système", >1 module → L/XL.

#### STEP 2bis: ARCHITECTURE VALIDATION GATE (unconditional whenever architect ran)

If the pipeline included an `architect` spawn that produced `.claude/tmp/{team}/arch.md`, the lead runs `~/.claude/hooks/validate-arch.sh .claude/tmp/{team}/arch.md` BEFORE spawning the developer. This fires in **any** pipeline (minimal default included), not only under `--challenge-arch`/`--ceremony`. The hook:

- verifies the `## Tests that would invalidate this design` section exists with ≥3 bullets
- extracts the section content to `.claude/tmp/{team}/arch.tests.txt`
- exit 2 = block: lead returns to architect with `NEEDS_CONTEXT [validate-arch.sh feedback]`
- exit 0 = proceed: lead inlines `arch.tests.txt` content into the developer brief (tests-first protocol per `agent-synergy.md` CC-2 → CC-4 synergy contract)

This gate enforces the architect→dev/tester handoff at the structural level (per ADR 0002 D-4). Without it, the falsification handoff is prose-only and silently bypassable. With it, an architect emitting an arch.md without the falsification section is caught immediately.

If the pipeline did NOT spawn an architect (Bug, S-size Feature, UI, Review, Exploration), this step is skipped silently — no arch.md to validate.

### STEP 3: COORDINATION

Create the tasks via `TaskCreate` with dependencies (blockedBy). Assign via `TaskUpdate(owner=name)`. Notifications arrive automatically (`<teammate-message>` rendered in the LLM context, or `idle_notification`). No polling daemon — **LLM-reactive** model (cf. ADR 0001 Layer 2).

Each teammate MUST end with a status:
- `STATUS: DONE` — work completed
- `STATUS: DONE_WITH_CONCERNS [description]` — completed with doubts
- `STATUS: NEEDS_CONTEXT [info]` — blocked by missing info
- `STATUS: BLOCKED [reason]` — unable to continue

**LLM-reactive polling (at each lead turn, triggered by an idle/teammate notification)**:

1. Teammate messages arrive natively in your context (`<teammate-message>` turns). If a STATUS performative is present: `TaskUpdate(metadata.delivered_by=X)` (rule 14 dedup) → process the result
2. Otherwise: `Bash("cat ~/.claude/tmp/{team}/_status_<X>.md 2>/dev/null")` (channel #2 fallback)
3. Otherwise: send a PING via `SendMessage(to=X, ...)` — X = the `name` given at spawn
4. Hard timeout 30s without STATUS received after PING → `STATUS: BLOCKED [silence after PING]` in the TaskList and escalate to the user.

If `DONE_WITH_CONCERNS` → assess severity, re-launch if necessary.
If `NEEDS_CONTEXT` → provide the missing context.
If `BLOCKED` → diagnose, change approach or escalate.

### STEP 4: REVIEW (default ultra, except --no-ultra)

**Ultra-review (default)**: invoke skill `/ultra-review` (4 parallel scanners + independent validation). See `~/.claude/docs/team-ultra-review.md`.

**Light review (if `--no-ultra`)**: 1 `code-reviewer` who runs `git diff`, checks quality + adherence to archi (if applicable), produces verdict.

Verdict: `PASS` / `FAIL_CRITICAL` / `FAIL_WARNING` / `NEEDS_JUSTIFICATION`.
- PASS → step 5
- FAIL_CRITICAL → mandatory correction (dev ↔ reviewer loop max 3 iter)
- FAIL_WARNING → decide on the fix if obvious and move forward; document the warning in the final summary. Only escalate to the user if the warning involves a trade-off that changes the scope of the initial request.

**Iteration count + FINAL_VERDICT (subprocess contract, cf. STEP 6)**. After each dev↔reviewer cycle, the lead runs:

```bash
ITER_FILE="$HOME/.claude/tmp/{team-name}/iter-count.txt"
echo $(($(cat "$ITER_FILE" 2>/dev/null || echo 0) + 1)) > "$ITER_FILE"
```

After the review settles on a final verdict (PASS, FAIL_CRITICAL, FAIL_WARNING, NEEDS_JUSTIFICATION), the lead assigns the shell variable AND persists it to disk so STEP 6 can read it from a separate Bash tool call (each Bash invocation is a fresh shell — variables do not persist across calls):

```bash
FINAL_VERDICT=<PASS|FAIL_CRITICAL|FAIL_WARNING|NEEDS_JUSTIFICATION>
echo "$FINAL_VERDICT" > "$HOME/.claude/tmp/{team-name}/team-verdict.txt"
```

Solo runs (no `IMPROVEMENT_PIPELINE=1` / `AUTO_IMPROVEMENT_SOURCE` set) can skip both — the STEP 6 contract block is gated on those env vars.

### STEP 5: TESTS (except --no-test)

Spawn `tester`. Run the existing tests, analyze the results. If failure → dev fixes, tester re-runs (max 3 iter).

### STEP 6: DONE

Shutdown teammates (`SendMessage type: shutdown_request`, wait for confirmation). Display summary:
```
## Pipeline termine
- Pipeline: <type>
- Agents: <liste>
- Fichiers: <crees/modifies>
- Tests: <X/Y passes>
- Verdict: <PASS ou autre>
```

Before cleanup, **preserve the ADRs**: if `.claude/tmp/{team-name}/arch.md` exists, move it to `.claude/decisions/NNNN-<slug>.md` (NNNN = highest existing number + 1, zero-padded to 4 digits; slug = title in kebab-case). Create `.claude/decisions/` and `.claude/state/` if missing. **Then substitute `NNNN` only in the header** of the ADR with the assigned number. The number reservation is done via an **atomic `mkdir` lock** (atomic on any POSIX FS) to avoid collision between two concurrent `/team` runs:

```bash
mkdir -p .claude/decisions/
mkdir -p .claude/state/

# Calcul N + lock atomique (mkdir est atomique POSIX)
max=$(ls .claude/decisions/[0-9]*.md 2>/dev/null | tail -1 | sed 's|.*/||;s|-.*||' | sed 's|^0*||')
max=${max:-0}
N_INT=$((max + 1))
N=$(printf '%04d' "$N_INT")

for retry in 1 2 3 4 5 6 7 8 9 10; do
  if mkdir .claude/decisions/.lock-$N 2>/dev/null; then
    break  # lock acquis
  fi
  # Collision : un autre /team a réservé ce numéro. Incrémente et retry.
  N_INT=$((N_INT + 1))
  N=$(printf '%04d' "$N_INT")
done

mv .claude/tmp/{team-name}/arch.md .claude/decisions/$N-<slug>.md
sed -i '' "s/^# ADR NNNN/# ADR $N/" .claude/decisions/$N-<slug>.md

# Warning uniquement si NNNN résiduel HORS placeholders Supersedes/Superseded by (placeholders légitimes non renseignés).
if grep -n "NNNN" .claude/decisions/$N-*.md 2>/dev/null | grep -v "Superseded" | grep -v "Supersedes" | grep -q .; then
  echo "WARNING: ADR $N contient des placeholders NNNN non substitues (hors Supersedes/Superseded by). L'architect doit les nettoyer."
fi

# Release lock (directory temporaire, supprimé en fin de pipeline)
rmdir .claude/decisions/.lock-$N 2>/dev/null || true
```

BSD sed on macOS requires `-i ''`. The substitution is **limited to the header** (`^# ADR NNNN`) to prevent a residual `NNNN` in the body (Supersedes/Superseded by template not cleaned by the architect) from becoming an absurd self-reference (`Supersedes 0042` in ADR 0042). The other bulky artifacts (audit reports, criteria, etc.) are kept only if `--keep-artifacts`.

**End-of-run task hygiene**: clean the TaskUpdate dedup metadata. `TaskUpdate` does NOT clean `metadata.delivered_by` / `metadata.delivered_at` — for each task with these keys, emit `TaskUpdate(taskId, metadata={"delivered_by": null, "delivered_at": null})` to avoid inter-pipeline pollution (rule 14).

**Append to project journal** (`.claude/state/JOURNAL.md`): the lead writes one entry summarizing the pipeline outcome, with markdown links to truth files (ADRs, state, commits). The journal is the user's continuity anchor across multi-day sessions — they read it on session resume to know "what was done, what's next".

Format:
```markdown
## YYYY-MM-DD HH:MM — <project> — <task summary> (<pipeline type>)
- Agents: <list> — <verdict>
- ADRs: [NNNN slug](.claude/decisions/NNNN-slug.md) (if any new)
- State: [STATE.md:Lline](.claude/state/STATE.md) (if updated)
- Commit: [`<sha>`](#) — <message first line>
- Files: N modified, M created
- CC-4 ratio: refutable=<X>/<Y> (target ≥80%)
- Next: <1-line suggested next step, or "—" if none>
```

Bash to append:
```bash
mkdir -p .claude/state
JOURNAL=.claude/state/JOURNAL.md
[ -f "$JOURNAL" ] || echo -e "# Project Journal\n\nAuto-maintained by /team. Each entry links back to the truth files (ADRs, state, commits).\n" > "$JOURNAL"

# NB: pas de $1/$2 dans un SKILL.md — la substitution d'arguments du skill les remplace au rendu
NEW_ADRS=$(ls .claude/decisions/[0-9]*.md 2>/dev/null | while read -r f; do m=$(stat -f %m "$f" 2>/dev/null); [ -n "$m" ] && [ "$m" -ge "$(date -v-1H +%s)" ] && echo "$f"; done | head -3)
COMMIT=$(git log -1 --format='%h %s' 2>/dev/null || echo "no commit")

cat >> "$JOURNAL" <<EOF

## $(date '+%Y-%m-%d %H:%M') — $(basename "$(pwd)") — <task summary> (<pipeline>)
- Agents: <list> — <verdict>
- ADRs: $(echo "$NEW_ADRS" | sed 's|^|[|;s|$|](&)|' | tr '\n' ' ')
- Commit: \`$(echo "$COMMIT" | cut -d' ' -f1)\` — $(echo "$COMMIT" | cut -d' ' -f2-)
- CC-4 ratio: refutable=<X>/<Y> (target ≥80%)
- Next: <1-line suggested next step>
EOF
```

The lead substitutes `<task summary>`, `<pipeline>`, `<list>`, `<verdict>`, `<next step>` with concrete values from the run, and `<X>/<Y>` for the CC-4 gate: X = findings carrying a `*Refutable by:*` line, Y = total CRITICAL+HIGH+MEDIUM findings observed this session (`0/0` if no review ran).

**Subprocess contract (ADR 0013)** — when invoked from `/apply-improvement` (or any parent that sets `IMPROVEMENT_PIPELINE=1` / `AUTO_IMPROVEMENT_SOURCE`), write `team-status.json` before the tmp cleanup so the caller can parse the verdict out-of-band:

```bash
if [ -n "${IMPROVEMENT_PIPELINE:-}" ] || [ -n "${AUTO_IMPROVEMENT_SOURCE:-}" ]; then
  ITER=$(cat ~/.claude/tmp/{team-name}/iter-count.txt 2>/dev/null || echo 0)
  COMMITS=$(git rev-list --count main..HEAD 2>/dev/null || echo 0)
  FINAL_VERDICT=$(cat "$HOME/.claude/tmp/{team-name}/team-verdict.txt" 2>/dev/null || echo "unknown")
  cat > ~/.claude/tmp/{team-name}/team-status.json <<EOF
{"verdict":"$FINAL_VERDICT","review_iterations":$ITER,"commits_count":$COMMITS,"branch":"$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)","team_id":"{team-name}"}
EOF
fi
```

`$FINAL_VERDICT` is read from `team-verdict.txt` (written at STEP 4); valid values: `PASS | FAIL_CRITICAL | FAIL_WARNING | NEEDS_JUSTIFICATION`. Absence of the file → `"unknown"` (signals crash before verdict assignment). The `iter-count.txt` file is incremented by the lead at each review retry; absence = 0. Write the JSON even on `FAIL_CRITICAL` (the consumer distinguishes verdicts by parsing). Solo runs (no env vars set) skip this block — non-breaking, no orphan file.

**Shutdown (current harness)**: there is no team registry to tear down. Send `shutdown_request` to each dialogue teammate still active and wait for the `shutdown_response`s (rule 16); Workflow fan-outs need no teardown. Cleanup `.claude/tmp/{team-name}/` (except if `--keep-artifacts`). **Then verify no agent process survived** (observed 2026-06-10: 9 in-process agents outlived shutdown_request, freezing UI panels and leaking tsserver stacks): `ps -axo pid,command | grep -- "--agent-id"` → if survivors match a `name` YOU spawned this run, `kill` them (TERM, then -9 after 3s); leave other sessions' agents alone.

## PIPELINE WITH CEREMONY (--ceremony)

Add **before** step 1:

### STEP 0a: INTERVIEW 95% (if --interview or --ceremony)

Ambiguity scoring on `$ARGUMENTS`:
- CLEAR: what + boundaries + criteria deducible → skip interview
- AMBIGUOUS: at least 1 fuzzy question → interview
- VAGUE: goal not clear → suggest `/discuss`

If interview triggered: rephrase + ask 2-3 questions per batch via AskUserQuestion. Target 95% confidence. Max 10 questions, beyond → warning + continue.

### STEP 0b: ROI GATE (if --roi or --ceremony, except Bug/Exploration)

Present a pre-filled assessment (NOT questions):
- Problem solved, who is affected, if we do nothing
- Estimated effort (XS/S/M/L/XL) × Value (HIGH/MEDIUM/LOW) → GO / TO CONSIDER / TO RECONSIDER
- User validates via AskUserQuestion (continue / adjust / abandon)

### STEP 0c: ACCEPTANCE CRITERIA (if --criteria or --ceremony, L/XL task)

Generate `.claude/tmp/{team-name}/criteria.md` with must-pass scenarios + edge cases + DoD. Referenced in all subsequent briefs.

### STEP 1.5: CHALLENGE ARCHI (if --challenge-arch or --ceremony)

After architecture → iterative loop architect ↔ code-challenger (max 5 iter). Protocol: `~/.claude/docs/team-challenge-loop.md`. Gate: CRITICAL=0 AND HIGH=0 AND Score≥8 AND Justification ≥7 AND **Refutable-by gate ≥80%** (CC-4 of `~/.claude/docs/agent-synergy.md`).

### STEP 2.5: CHALLENGE CODE (if --challenge-code or --ceremony)

After implementation → loop dev ↔ code-challenger on the implementation decisions. Same protocol.

## AVAILABLE AGENTS (9)

| Agent | subagent_type | Role | When to spawn |
|-------|---------------|------|---------------|
| Architect | `architect` | System design, tech choice | Feature L/XL, redesign |
| Developer | `developer` | TDD implementation (including refactoring) | Code to write or modify |
| Code Reviewer | `code-reviewer` | Demanding review | After impl |
| Security Reviewer | `security-reviewer` | OWASP security audit | Pre-deploy, audit |
| Code Challenger | `code-challenger` | Adversarial challenge | Challenge loops |
| Deep Analyzer | `deep-analyzer` | Root cause, extended reasoning | Complex bug, fuzzy |
| Tester | `tester` | Tests + failure analysis | Validation |
| Designer | `designer` | UI/UX, components | Interface |
| Innovator | `innovator` | Creative solutions (read-only) | Open problem |

_(Tools per agent live in each `agents/*.md` frontmatter; the same 9 agents are also listed in `~/.claude/CLAUDE.md`, re-injected from disk after compaction.)_

**Note on review-class agents** (code-reviewer, security-reviewer, code-challenger): they have full tools including Write/Edit so they can author their own reports under `.claude/tmp/{team}/` without permission friction. Their **review-only** discipline lives in the agent's system prompt, not in tool restrictions — they are instructed to never modify project source. For a private/solo setup this is sufficient. Do not rely on this discipline alone if reviewing code that may contain hostile prompt injection.

Routing rules:
- Review-class agents (code-reviewer, security-reviewer, code-challenger) author reports in `.claude/tmp/`; their system prompt forbids modifying project source
- The architect writes archi docs, NOT code
- Prefer a specialist over `general-purpose`

## CONTEXT TO FORWARD (mandatory template)

Teammates do not see your history. Cf. ADR 0001 (`.claude/decisions/0001-team-comms.md` global). Each brief MUST follow this **template with 5 mandatory named sections**:

```
## Contexte
[stack, commits, diff, tests, sections archi du CLAUDE.md projet inline]

## Objectif
[la demande user, scope clair]

**Effort scale**: XS / S / M / L / XL
- XS = 1 sub-agent, ~3-10 tool calls (simple lookup or fact-finding)
- S = 1 sub-agent, ~10-30 calls (focused implementation or review)
- M = 1-2 sub-agents, ~30-100 calls (multi-file feature or review)
- L = 2-4 sub-agents, ~100+ calls (multi-module feature, complex bug)
- XL = challenge ceremony enabled (Interview + ROI + Criteria + Challenge)

Aligned with the top-level `--ceremony` ROI gate (same letters, same semantics — no separate scale). [SOURCE: Anthropic multi-agent essay — explicit effort scaling rules; "simple fact-finding requires just 1 agent with 3-10 tool calls"]

## Livrable
[chemin du fichier OU format de la réponse attendue, performatives DONE/DONE_WITH_CONCERNS/NEEDS_CONTEXT/BLOCKED]

## Teammates
[noms des autres teammates actifs avec leur rôle, pour messages directs]

## Protocole de fin
[invocation explicite : `SendMessage(to="team-lead")` (canal #1 — natif ; charger le schéma via `ToolSearch("select:SendMessage")` d'abord, l'outil est deferred) OU Write `.claude/tmp/{team-name}/_status_<nom>.md` (canal #2 fallback). Doit contenir le mot `SendMessage` ou `_status_`.]
```

**Validation before `Agent()` spawn** (rule 19) — the lead bash-checks its brief:

```bash
brief_file=$(mktemp)
echo "$brief_content" > "$brief_file"
for section in "## Contexte" "## Objectif" "## Livrable" "## Teammates" "## Protocole de fin"; do
  grep -qF "$section" "$brief_file" || { echo "BRIEF INVALID: missing $section"; exit 1; }
done
grep -qE "(SendMessage|inbox|_status_)" "$brief_file" || { echo "BRIEF INVALID: no notification channel"; exit 1; }
rm "$brief_file"
```

Warning mode by default (continue with warning log). Block mode only if flag `--strict`.

Additional details:
- **Previous results**: path of bulky files (not the content), or short 2-3 sentence summary.
- **Evidence markers**: if the brief goes to `architect`, `code-reviewer`, `security-reviewer`, `deep-analyzer` or `code-challenger`, explicitly require `[SOURCE]` / `[SOURCE community]` / `[OBSERVED]` / `[INTUITION]` / `[ENGINEERING]` in their output (cf. `docs/verdict-protocol.md` empirical justification markers section). Gate `justification >= 7` even in a pipeline without a challenge loop. CC-4 falsifiability: every CRITICAL/HIGH includes `*Refutable by:*` line; Refutable-by gate >= 80% per `docs/agent-synergy.md`.
- **Artifacts > 200 words**: shared file in `.claude/tmp/{team-name}/`, never copied into the prompt.

The common "Team communication protocol" block inserted in the 9 base + 8 control `agents/*.md` (cf. ADR 0001 Layer 1) already covers the sub-agent's task end. The lead's brief must nevertheless **explicitly remind it** in the `## Protocole de fin` section — the triple insistence (system prompt + brief + common block) closes RC2 (50% of historical briefs without SendMessage).

## LEAD CONTEXT ROT

You stay light to coordinate. Do not store the full reports — read the files when needed. Summarize in 2-3 sentences before the next step. Goal: keep ~80% of context free.

## TEAM MANAGEMENT

- **Spawn on demand**: only spawn a teammate when you need them
- **Shutdown at deliverable validation, IMMEDIATELY**: as soon as the lead has verified a teammate's deliverable and closed its task, send `shutdown_request` — do NOT keep finished agents as idle members "in reserve for fix rounds" (observed 2026-06-11: 3 finished agents kept alive 8h+ for nothing, polluting the user's status line). Fix rounds use FRESH respawns anyway (a completed in-process agent cannot receive SendMessage — send-message-guard blocks it). The only agent alive at any moment should be one with work in flight.
- **Crash recovery**: message → shutdown if blocked → `git status`/`git diff --stat` → respawn with context + git state → inform the user

## ROUTING (lead-only)

All teammate communication routes through `team-lead`. Direct teammate-to-teammate `SendMessage` is blocked by the PreToolUse hook (exit 2). For tight loops (dev↔reviewer fix, tester↔developer test failure), the lead routes — adds <1s latency vs the visibility cost of "behind the scenes" peer exchanges. Empirically (audit 2026-04-28), all observable communication already routed through lead — this rule formalizes the de facto pattern.

Lead intervenes for: major architectural decisions, conflicts, blockages > 3 round-trips.

## DOCS REFERENCES

- Challenge loop protocol: `~/.claude/docs/team-challenge-loop.md`
- Verdict protocol: `~/.claude/docs/verdict-protocol.md`
- Ultra-review: `~/.claude/docs/team-ultra-review.md`
- Anti-patterns + recovery: `~/.claude/docs/team-anti-patterns.md`
- Detailed pipelines: `~/.claude/docs/team-pipelines.md`

## PARALLEL MODE (--parallel)

For a big feature, several devs in parallel:
1. Planner or architect splits by module/folder
2. Each dev receives an **explicit list** of files they can touch
3. No file in two lists
4. Conflict → dev sends a message to the lead who coordinates
5. Consider `isolation: "worktree"` to avoid git conflicts

## MICRO-RETRO (end of pipeline, ≥3 steps)

Before cleanup, display:
```
## Retro — {team-name}
- Pipeline: {type} | Étapes: {N} | Iterations challenge: {N}
- Bien marché: {1 phrase}
- Ralenti: {1 phrase}
- Pattern à retenir: {1-2 observations}
```

If ≥3 steps → invoke `/learn` with context to persist the learnings.
Otherwise → if (and only if) the retro surfaced a durable process lesson, update the matching `feedback_*.md` in `~/.claude/projects/$(pwd | sed 's|[/.]|-|g')/memory/` (+ index line in `MEMORY.md` if new file); a <3-step pipeline that taught nothing persists nothing.

Anti-duplicate rule: never both at the same time.

