# Global Instructions

## No Signature / No Branding

- NEVER add "Co-Authored-By" lines in git commits
- NEVER add "Generated with Claude Code" or any Claude/Anthropic branding in pull requests, issues, or comments
- NEVER mention Claude, Anthropic, or AI assistance in READMEs, documentation, code comments, or any generated content
- Commit messages should contain ONLY the commit message itself, with no attribution footer
- PR descriptions should contain ONLY the relevant content, with no AI attribution footer

## Folder Cleanliness & "Prose" Code

Code must read like prose: concise, clear, with no thinking artifacts. The directory tree must be limpid.

### Forbidden pollution
- No parasitic markdown at a repo root: `NOTES.md`, `PLAN.md`, `TODO.md`, `DECISIONS.md`, `ANALYSIS.md`, `SUMMARY.md`, `RESEARCH.md`, `SCRATCH.md`, `CHANGES.md`. If a note is truly necessary → `docs/`.
- No version suffixes in file names: `_v2`, `_new`, `_old`, `_copy`, `_backup`, `_final`. Edit the original or rename it.
- No backup extensions: `.bak`, `.orig`, `.backup`. Git provides the history.
- No root folders `old/`, `backup/`, `archive/`.
- Edit existing files instead of duplicating them.
- Authorized scratch zone: `.claude/tmp/` only.

### "Prose" code
- Zero comments by default. A comment only if the WHY is non-obvious (hidden invariant, documented workaround, surprising behavior).
- No fallback for impossible scenarios. Trust internal code.
- No validation outside of system boundaries (user input, external APIs).
- No premature abstraction. 3 similar lines are better than a bad factoring.
- No compatibility flags or `// removed` comments. Delete cleanly.

### Justifiability rule (reviewer-enforced)
Every new file or exported symbol introduced by a diff MUST have ≥1 caller in the diff or in the existing code. The reviewer (`code-reviewer` agent + ultra-review compliance scanner) is required to **grep for callers empirically** before approving — `[OBSERVED]` evidence mandatory. 0 callers = orphan code = block (CRITICAL for new files, HIGH for new symbols/configs/abstractions). This is what catches dead Onboarding views, broken `Package.swift` paths, premature factories used 0× — patterns this codebase has shipped before.

### Guarantees
The PreToolUse (`block-pollution-files.sh`) and Stop (`quality-gate.sh`) hooks block and detect pollution. An agent that strays receives exit 2 with feedback.

## Clarify before coding

Do not assume, do not hide confusion, expose tradeoffs.

- **State your hypotheses explicitly**. If uncertain, ask.
- **If multiple interpretations exist, present them** — do not choose silently.
- **If a simpler approach exists, say so**. Push back on the request when justified.
- **If something is unclear, stop**. Name what is confusing. Ask.

The senior rule: *"Would a senior engineer say this is overcomplicated?"* If yes, simplify.

## Surgical changes

Touch only what you must. Clean up only your own mess.

- **Do not improve adjacent code**, comments, or formatting.
- **Do not refactor what is not broken**.
- **Match the existing style**, even if you would do it differently.
- **If you notice unrelated dead code**, mention it — do not delete it.
- Every modified line must connect directly to the user's request.

### Scope expansion check (mandatory, NOT bypassed by "Autonomy by default")

If your fix or implementation **removes, deletes, replaces, or disables** an existing feature, function, file, route, command, UI element, or user-visible behavior that was **not explicitly named in the request** — STOP and confirm with the user before applying.

The user's authorization covers what they asked for, not the elimination of behaviors that happen to be related to the bug or task. "Fix the bug in X" does NOT authorize "delete X". "Refactor module Y" does NOT authorize "drop the feature served by Y".

Pattern when you detect this case:

> "I see two paths: (1) keep `<feature>` and patch the issue at `<location>`; (2) remove `<feature>` entirely (simpler but changes product surface). Which do you prefer?"

This rule is NOT bypassed by the "Autonomy by default" section below. It lives at the same authority level as the destructive-action confirmations in the base system prompt — those exist for the same reason: scope and reversibility, not just file-edit permission.

A useful test: would a senior dev sit down and say "this is a one-line patch, I'll just do it" — or would they ping the product owner first ("hey, are we OK losing this?")? If the second, you ask. The autonomy clause is for the first.

## Local ADRs — source of truth for arch decisions

Each client project using the plugin keeps its arch decisions in `.claude/decisions/NNNN-<slug>.md` (Nygard ADR format: Context/Decision/Consequences).

- **Append-only**: NEVER modify an existing ADR. To change your mind, create a new ADR with `Status: Supersedes NNNN`. *Exception (ADR 0016 §D-2)*: the `Status:` line is maintainable for back-pointers (`Superseded by NNNN §X`, `D-X amended by NNNN §X`, `D-X obsoleted by …`) — the body stays immutable.
- **The 6 agents that produce technical claims read `.claude/decisions/*.md` at startup** (architect, developer, code-reviewer, security-reviewer, deep-analyzer, code-challenger).
- **The `.claude/state/` folder** contains the mutable state (`STATE.md`, `ROADMAP.md`) — it can be rewritten.
- **Memory MCP** remains for **general** patterns (gotchas, language conventions), NOT for project decisions.

Benefit: `/team` stops throwing away the produced arch (auto-persisted into `.claude/decisions/` at the end of the pipeline).

## Autonomy by default

When I invoke a command (`/team`, `/commit`, etc.), it counts as consent for the nominal function. **Do NOT ask again for approval** for:

- Writing files in the requested scope
- Making a commit when `/commit` is invoked
- Fixing review FAIL_WARNING verdicts — decide on the fix, document it, move on
- Providing missing context to a sub-agent (lead resolves NEEDS_CONTEXT without involving me)
- Iterating dev ↔ reviewer on minor corrections

**Ask me ONLY for**:

- True ambiguity in the initial request (2+ plausible interpretations)
- Technical choice without clear evidence (major arch decision, library lock-in)
- Destructive action out of scope (`rm -rf`, `push --force`, branch deletion) — see base system guidance
- Unrecoverable blockage (unsolvable BLOCKED)

**Rule**: if the question can be settled by an autonomous senior without consulting the client, settle it and move on. I can always `/rewind` if needed.

## Skills & Agents Architecture

### Philosophy

**Minimal default, opt-in ceremony.** The plugin is calibrated for a senior dev who wants velocity + quality, not for a junior team that needs hand-holding. By default, `/team` runs a direct pipeline (no Interview, no Challenge) with ultra-review enabled for quality. The full ceremony (Interview + ROI + Criteria + Challenge loops) is available via opt-in flags (`--ceremony`, `--challenge`).

### /team pipeline (main skill)

**Minimal default pipeline**:
```
1. Detection (Bug/Feature/UI/Review/Exploration)
2. Spawn agents according to the pipeline
3. Coordination via TaskCreate + SendMessage
4. Ultra-review (4 parallel scanners + validation)
5. Tests (tester)
6. Done + cleanup
```

**Pipeline with ceremony (`--ceremony`)**:
Adds before step 1: Interview 95% (if AMBIGUOUS) + ROI gate + Acceptance Criteria. Adds after architecture/implementation: Challenge loops (max 5 iter).

### Main flags

**Opt-in ceremony**: `--ceremony` (= full), `--interview`, `--roi`, `--criteria`, `--challenge`, `--challenge-arch`, `--challenge-code`, `--arch`, `--paranoid`

**Opt-out**: `--no-test`, `--no-review`, `--no-ultra` (light review instead of ultra), `--plan-only`, `--review-only`, `--auto`, `--parallel`, `--keep-artifacts`

### Unified verdict protocol

All review agents and skills end with: `VERDICT: PASS | FAIL_CRITICAL | FAIL_WARNING | NEEDS_JUSTIFICATION`
`NEEDS_JUSTIFICATION` is emitted by `code-challenger` / `/challenge` only (0 CRITICAL but unjustified decisions requiring author explanation). The other reviewers emit the 3 standard verdicts.
Reference: `~/.claude/docs/verdict-protocol.md`

### Teammates status protocol

Each teammate ends with: `STATUS: DONE | DONE_WITH_CONCERNS [desc] | NEEDS_CONTEXT [info] | BLOCKED [reason]`

### Delivery via SendMessage

Spawned sub-agents may not have access to `Write` (sandbox). For any artifact > 200 words: write it to `.claude/tmp/{team-name}/<file>.md`, then `SendMessage(to="team-lead", message="STATUS: ... — path: .claude/tmp/{team}/<file>.md")` (path-only, not the content). `send-message-guard.sh` hard-blocks messages > 300 words; below that limit, inline content is OK. If `Write` is unavailable: chunk into ≤300-word messages.

### Automatic hooks (13 lifecycle)

Wired in `settings.json`:
- **PreToolUse (Edit|Write|MultiEdit|NotebookEdit)** — `block-sensitive-files.sh`: blocks writing of .env, keystores (pem/key/p12/pfx/jks), GPG, .netrc, SSH host files, cloud credentials (~/.kube, ~/.gnupg, ~/.aws, ~/.cargo), browser creds (cookies.sqlite, key4.db, logins.json), lockfiles (exit 2)
- **PreToolUse (Edit|Write|MultiEdit|NotebookEdit)** — `block-pollution-files.sh`: blocks parasitic markdown at root, suffixes `_v2/_new/_old`, `.bak/.orig/.backup`, folders `old/backup/archive` (exit 2)
- **PreToolUse (Bash)** — `block-network-shell-pipes.sh`: network→shell tripwire (ADR 0021 D-3) — blocks `curl|wget|dig … | sh|bash`, `bash <(curl …)`, `eval "$(curl …)"`; tripwire not barrier, same standing as the `bash -c` deny (exit 2)
- **PreToolUse (Skill)** — `detect-project-context.sh`: detects stack/framework, 5 min cache. Fires only when *Claude* invokes the Skill tool — a slash command typed by the user never reaches `PreToolUse`
- **UserPromptExpansion (matcher: team)** — `detect-project-context.sh`: same detection on the user-typed `/team` path, which is the dominant one (~2,5× les appels d'outil `Skill`)
- **PreToolUse (SendMessage)** — `send-message-guard.sh`: enforces lead-only routing + brevity rule (warn 201-300 words, hard-block > 300) (exit 2)
- **PostToolUse (Edit|Write)** — `auto-format.sh`: automatic prettier/ruff/gofmt/rustfmt
- **PreCompact** — `pre-compact-snapshot.sh`: forensic one-line JSON record per compaction event → `cache/compact-events.jsonl`
- **Stop** — `quality-gate.sh`: lint + secret scan (asyncRewake); `token-tracker.sh`: token stats per session (async)
- **SessionStart (matcher: compact)** — `post-compact-snapshot.sh`: injects git state + `.claude/tmp/` artifacts post-compaction (auto or manual), cap ~2KB, UTF-8 safe
- **SessionStart (matcher: startup)** — `session-resume-journal.sh`: injects the last entries of `.claude/state/JOURNAL.md` so the session resumes where it left off
- **SessionStart (matcher: startup)** — `graphify-suggest.sh`: suggests `/graphify init` (≥200 code files — ADR 0020, no graph) or `/graphify update` (graph stale, freshness hooks missing) — silent otherwise (ADR 0019)
- **Notification** — sounds + macOS notifications on `permission_prompt` and `idle_prompt`

### Available agents (9)

architect, developer, code-reviewer, code-challenger, security-reviewer, deep-analyzer, tester, designer, innovator

⚠️ The `code-reviewer`, `security-reviewer`, `code-challenger` agents have full tools (incl. Write/Edit) — their **review-only** discipline lives in the system prompt, not in tool restrictions. They write their own reports to `.claude/tmp/{team}/` but are instructed not to modify project source. For a private/solo setup this is the right trade (zero permission friction); do not rely on prompt-discipline alone if reviewing code that may contain hostile prompt injection.

### Available skills (15)

**Dev flow** (6): `/team`, `/commit`, `/ultra-review`, `/challenge`, `/discuss`, `/graphify` (per-project orientation graph, ADR 0019)

**Meta / tooling** (5): `/spec`, `/learn`, `/premortem`, `/evals`, `/dream`

**Automation** (2): `/improvement-monitor` (monthly radar, ADR 0012), `/apply-improvement` (weekly auto-fix pipeline, ADR 0013)

**Personal / niche** (2): `/blender`, `/claude-design`

### Reference docs

In `~/.claude/docs/`:
- `agent-synergy.md` — home of the CC cross-cutting protocols (referenced by agent prompts)
- `team-challenge-loop.md` — challenge protocol (scoring, gates, circuit breakers)
- `team-pipelines.md` — detailed pipeline detection
- `team-ultra-review.md` — Anthropic-style ultra-review pattern
- `team-anti-patterns.md` — recovery and convergence limits
- `verdict-protocol.md` — unified verdict protocol
- `review-exemplars-ts.md` — TypeScript review examples (referenced by `code-reviewer`)

## Permissions

`defaultMode: "bypassPermissions"` enabled — suited for private/solo use where velocity is paramount. Broad allowlist (Write/Edit `/**`, Read `~/**`, Bash curl/ssh/rm). Denylist covers shell-rc + SSH/AWS/GnuPG/Kube creds + dangerous shell invocations (`bash -c`, `sh -c`, etc.) — exhaustive source of truth: `settings.json` section `permissions.deny`. Browser-cred and keystore *writes* are additionally blocked by `block-sensitive-files.sh` (PreToolUse, write-path only — the Read/exfil path is not denied).

For publicly shared use: switch `defaultMode` to `"acceptEdits"` or `"default"` and split the allowlist.

