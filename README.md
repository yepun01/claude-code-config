# Claude Code plugin — `~/.claude/`

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) configuration optimized for **velocity + quality** at solo-senior scale: 9 specialized agents, 15 skills (1 promoted entry + power-use + automation/niche), lifecycle hooks, ADR-driven architecture, and peer-reviewed cross-cutting protocols (pre-mortem, falsifiability).

A working configuration, iterated against real codebases. The empirical claims in the docs are checked against peer-reviewed sources.

## Scope of this repository

This is a published extract of a working `~/.claude/`, not a mirror. Three things are
deliberately absent, and some documents below still reference them:

- `evals/runs/` — ~400 raw eval transcripts (2 MB of JSON). Noise for a reader; the
  protocol that produced them lives in `skills/evals/` and ADRs 0003, 0005, 0006, 0007.
- `state/` — `JOURNAL.md`, `ROADMAP.md`, `PENDING-IMPROVEMENT.md`. Personal working notes.
  The hooks and skills that read them are shipped; the contents are not.
- `skills/mouly/` — a school-specific grader, meaningless outside that context.

ADRs are append-only, so references to the above were left untouched inside
`decisions/`. `settings.json` ships with `defaultMode: "acceptEdits"` rather than the
`bypassPermissions` used locally — **review the 99-rule allowlist before adopting it.**

## Philosophy

**Minimal default, opt-in ceremony.**

`/team <task>` runs a direct pipeline (no Interview, no ROI gate, no Challenge loops) with ultra-review enabled by default. A senior who knows what they want gets velocity. The full ceremony (Interview 95% + ROI + Acceptance Criteria + Challenge loops) is available via opt-in flags (`--ceremony`, `--challenge-arch`, etc.). See `skills/team/SKILL.md` for the full flag matrix.

**Evidence-based.** Every technical claim in agents/skills/docs carries a marker:

| Marker | Meaning | Weight in justification denominator |
|---|---|---:|
| `[SOURCE]` / `[SOURCE peer-reviewed]` | Peer-reviewed paper or primary authoritative source. **Author byline verified at write time via WebFetch.** | 1.0 |
| `[SOURCE community]` | Community engineering pattern (production codebase, recognized skill, blog post by domain expert) | 0.7 |
| `[OBSERVED: file:line]` | Verifiable in current codebase | 0.7 |
| `[INTUITION]` | Experience-based judgment, no external source — flagged if >30% of decisions | 0.3 |
| `[ENGINEERING]` | Pragmatic threshold without scientific source (e.g., "≥80% gate"). **Counted in denominator at 0.5 — not excluded.** | 0.5 |

Full marker semantics in `docs/verdict-protocol.md`.

## Quick start

This is a personal config. To adopt:

```bash
# Backup any existing ~/.claude/
mv ~/.claude ~/.claude-backup-$(date +%Y%m%d) 2>/dev/null

# Clone
git clone https://github.com/yepun01/claude-config.git ~/.claude

# Make hooks executable
chmod +x ~/.claude/hooks/*.sh

# Settings
# - Review ~/.claude/settings.json before first run
# - defaultMode: "bypassPermissions" is enabled (private/solo trade-off, see Permissions below)
# - For shared/public use, switch to "acceptEdits" or "default"
```

Then in any project:

```
/team add a feature X
/team --ceremony refactor module Y         # full ceremony
/challenge src/auth/                       # adversarial review
/premortem the migration plan              # creator-mode pre-mortem
/ultra-review staged                       # 4-scanner high-confidence review
```

## Available agents (9)

In `agents/`. Each has its own system prompt with cross-cutting protocols inlined.

| Agent | Role | Cross-cutting protocols |
|---|---|---|
| `architect` | System design, tech choice | CC-2 pre-mortem (Phase 0bis) + CC-4 falsifiability |
| `developer` | TDD implementation | CC-2 pre-mortem (before TDD) + tests-first protocol |
| `code-reviewer` | Demanding review | CC-4 + justifiability rule (grep callers) |
| `security-reviewer` | OWASP audit | CC-4 |
| `code-challenger` | Adversarial challenge (7 axes + 6 grids + Phase 3b empirical justification) | CC-4 + byline verification mandate |
| `deep-analyzer` | Root cause + extended reasoning | CC-2 (alternative hypotheses) + CC-4 |
| `tester` | Tests + failure analysis | reads `arch.tests.txt` from D-4 hook |
| `designer` | UI/UX | CC-2 (UX abandonment scenarios) + CC-4 |
| `innovator` | Creative solutions, native steelman | CC-2 + CC-4 + effort-justification warning |

## Available skills (16)

Two-tier surface: **`/team` is the promoted entry point** — it auto-routes to a specialized skill when the request unambiguously matches one (STEP 0c in `skills/team/SKILL.md`), or falls back to the multi-agent pipeline. The other skills remain direct-invocable for power-use.

### Primary entry

| Skill | Purpose |
|---|---|
| `/team` | Routes to specialized skill OR multi-agent orchestration (default minimal pipeline; flags add ceremony) |

### Specialized (called by `/team` or direct)

| Skill | Purpose |
|---|---|
| `/commit` | Smart commit (conventional commits + scope detection) |
| `/ultra-review` | 4-scanner high-confidence review (Anthropic Code Review pattern verbatim) |
| `/challenge` | Stress-test decisions adversarially |
| `/premortem` | Pre-mortem on any artifact (creator-mode CC-2 standalone) |
| `/discuss` | Discuss gray zones before coding |
| `/spec` | Manage ADRs + project state |
| `/learn` | Persist knowledge from a /team pipeline |
| `/dream` | Audit auto-memory for stale entries (radar, no auto-modify) |
| `/improvement-monitor` | Monthly radar on CC changelog deltas vs plugin (per ADR 0012) |
| `/apply-improvement` | Weekly auto-fix pipeline — applies the top pending improvement on a dedicated branch (per ADR 0013) |
| `/evals` | Eval harness (CC-5 A/B pilot per ADR 0003) — **paused**, verdict UNDETERMINED, sunset 2026-09-04 (ADR 0016) |
| `/blender` | (personal — Blender MCP scene authoring) |
| `/claude-design` | (personal — design prompt builder) |

## Cross-cutting protocols

Documented in `docs/agent-synergy.md` (single source of truth). **Active protocols: CC-2 + CC-4.** CC-1/CC-3 deferred; CC-5 (anti-sycophancy) was suppressed 2026-05-02 per ADR 0003 §D-2 — **not active in any agent prompt** (kept below for reference).

### CC-2 · Pre-mortem for creator-class

`[SOURCE: Klein 2007 HBR + Mitchell-Russo-Pennington 1989 J Behav Decis Mak + Veinott-Klein-Wiggins 2010 ISCRAM]`. Architect/developer/deep-analyzer/designer/innovator narrate 3 disaster scenarios prospectively, **each naming (component, trigger, signal)**. Generic scenarios ("spec changes", "dep breaks") explicitly forbidden as cargo-cult target.

### CC-4 · Falsifiability extension to evidence markers

`[SOURCE: Popper 1959]`. Every CRITICAL/HIGH finding + every architectural decision must include a `*Refutable by:* [concrete evidence that would prove this is NOT a problem]` line. Generic "show me a passing test" counts as collapse.

Refutable-by gate: **≥80%** of CRITICAL/HIGH must have non-trivial Refutable-by line for PASS verdict.

### CC-5 · Anti-sycophancy red-flags table (suppressed 2026-05-02)

**Suppressed per ADR 0003 §D-2 (staged evaluation) — not active in any agent prompt; kept for reference.** `[SOURCE: Jetzen et al. 2024 arXiv 2407.01407 + Haynes et al. 2009 NEJM 360(5):491-9]`. 9 red-flag phrases (LGTM, "generally well-structured", "to be fair", etc.). Concrete checklists outperform prose discipline (peer-reviewed evidence from healthcare WHO surgical safety study).

### Synergy contract

The architect→dev/tester handoff is **machine-validated** via `~/.claude/hooks/validate-arch.sh`:

- Architect's `arch.md` MUST contain `## Tests that would invalidate this design` section with ≥3 bullets
- Hook extracts the section to `arch.tests.txt`
- Lead inlines `arch.tests.txt` into developer brief
- Developer reads it FIRST, writes tests BEFORE implementation

Fires unconditionally whenever architect runs (any /team pipeline, not only `--challenge-arch`).

## ADR system + JOURNAL

`/team` auto-persists architectural decisions:

- `arch.md` produced by architect → moved to `.claude/decisions/NNNN-<slug>.md` at end of pipeline (Nygard ADR format: Context / Decision / Consequences)
- ADRs are **append-only**. To change a decision, write a new ADR with `Status: Supersedes NNNN`.
- The 6 agents producing technical claims read `.claude/decisions/*.md` at startup (architect, developer, code-reviewer, security-reviewer, deep-analyzer, code-challenger) — accepted ADRs are the source of truth.

`.claude/state/JOURNAL.md` is the multi-day continuity anchor. `/team` appends one entry per pipeline outcome with markdown links to ADRs / commits / state files. Read on session resume to know "what was done, what's next".

## Hooks (lifecycle)

In `hooks/`, wired in `settings.json`:

- **PreToolUse(Edit/Write)** — `block-sensitive-files.sh` (.env, keystores, credentials), `block-pollution-files.sh` (parasitic markdown, `_v2/_old`, `.bak`)
- **PreToolUse(Skill)** — `detect-project-context.sh` (stack/framework cache, 5 min)
- **PreToolUse(SendMessage)** — `send-message-guard.sh` (lead-only routing + 200-word brevity rule)
- **PostToolUse(Edit/Write)** — `auto-format.sh` (prettier/ruff/gofmt/rustfmt)
- **Stop** — `quality-gate.sh` (lint + secret scan), `token-tracker.sh` (token stats per session)
- **SessionStart(compact)** — `post-compact-snapshot.sh` (git state + tmp artifacts post-compaction)
- **SessionStart(startup)** — `session-resume-journal.sh` (display last 5 JOURNAL entries)
- **Notification** — sounds + macOS notifications on permission/idle prompts

Plus the synergy contract hook:
- **`validate-arch.sh`** — called by /team after architect step (not a Claude Code lifecycle hook; runs as a bash gate)

## Permissions

`settings.json` ships with `defaultMode: "bypassPermissions"` — suited for **private/solo use** where velocity is paramount. Broad allowlist (Write/Edit `/**`, Read `~/**`, Bash for common tools). Denylist covers shell-rc + SSH/AWS/GnuPG/Kube creds + dangerous shell invocations (`bash -c`, `sh -c`); browser-cred + keystore *writes* are blocked by the `block-sensitive-files.sh` hook (write-path only).

For publicly shared use: switch `defaultMode` to `"acceptEdits"` or `"default"` and split the allowlist by trust tier.

## Project structure

```
~/.claude/
├── README.md                  ← you are here
├── CLAUDE.md                  ← LLM instructions (loaded each session)
├── settings.json              ← permissions, hooks, env
├── agents/                    ← 9 agent system prompts
├── skills/                    ← 16 invokable skills (/team is the entry; routes to /commit, /premortem, /dream, ...)
├── hooks/                     ← 11 lifecycle hooks + validate-arch.sh
├── docs/                      ← protocol references
│   ├── agent-synergy.md       ← CC-2/4/5 single source of truth
│   ├── verdict-protocol.md    ← marker semantics + verdict criteria
│   ├── team-pipelines.md      ← pipeline detection rules
│   ├── team-ultra-review.md   ← Anthropic Code Review pattern verbatim
│   ├── team-challenge-loop.md ← challenge convergence/regression
│   ├── team-anti-patterns.md  ← recovery + convergence limits
│   └── review-exemplars-ts.md ← TypeScript review examples
├── decisions/                 ← plugin-level ADRs (Nygard format)
├── state/                     ← mutable state (JOURNAL.md, STATE.md)
├── tmp/                       ← scratch zone (auto-cleaned by /team)
└── teams/                     ← active multi-agent team configs
```

## What this is NOT

- A framework — no abstractions to inherit from, just configuration
- A starter — opinionated for solo-senior, not for teams or juniors
- A finished product — it iterates. Iter 4 lean is the current state; ADR 0002 documents the rationale + what's deferred to follow-up

## Customization

The plugin is meant to be hacked on. Personal preferences:
- Add agents in `agents/` (frontmatter format: see existing files)
- Add skills in `skills/<name>/SKILL.md` (frontmatter with `description`, `argument-hint`, `agent`)
- Modify hooks in `hooks/` (registered in `settings.json`)
- ADRs in `decisions/` document major changes — append-only, supersede via new ADR

Before any major change: `/discuss` it, then `/premortem` it, then commit.

## License

This is a personal configuration. Use at your own risk. No warranty. The peer-reviewed sources cited in agents/skills/docs belong to their respective authors.
