# AGENTS.md

Cross-tool conventions for any AI agent (Claude, Codex, Cursor, Copilot, Devin, Windsurf, Amp, …) working in this repo. The Claude-specific extensions (skills, hooks, MCP, plugin philosophy) live in `CLAUDE.md`.

## No branding

- Never add "Generated with X" or attribution footers in commits, PRs, issues, READMEs, or code comments.
- Commit messages and PR descriptions contain only the substance.

## Clarify before coding

- State hypotheses explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — do not choose silently.
- If a simpler approach exists, say so. Push back on the request when justified.
- The senior rule: *"would a senior engineer say this is overcomplicated?"* — if yes, simplify.

## Surgical changes

Touch only what the request demands.
- Do not improve adjacent code, comments, or formatting that is not in scope.
- Do not refactor what is not broken. Match the existing style.
- If you notice unrelated dead code, mention it — do not delete it.
- Every modified line must connect directly to the user's request.

### Scope expansion check

If your fix or implementation **removes, deletes, replaces, or disables** an existing feature, function, file, route, command, UI element, or user-visible behavior that was **not explicitly named in the request** — STOP and confirm with the user before applying. The user's authorization covers what they asked for, not the elimination of behaviors that happen to be related.

## Folder cleanliness

The directory tree must be limpid. Forbidden:
- Parasitic markdown at root (`NOTES.md`, `PLAN.md`, `TODO.md`, `DECISIONS.md`, `ANALYSIS.md`, `SUMMARY.md`, `RESEARCH.md`, `SCRATCH.md`, `CHANGES.md`). Real notes go to `docs/`.
- Version suffixes in filenames (`_v2`, `_new`, `_old`, `_copy`, `_backup`, `_final`). Edit the original or rename.
- Backup extensions (`.bak`, `.orig`, `.backup`). Git provides history.
- Root folders `old/`, `backup/`, `archive/`.
- Edit existing files instead of duplicating them.

Authorized scratch zone: `.claude/tmp/` only.

## "Prose" code

- **Zero comments by default.** A comment only if the WHY is non-obvious (hidden invariant, documented workaround, surprising behavior). Don't explain WHAT (well-named identifiers do that).
- No fallback for impossible scenarios. Trust internal code.
- No validation outside system boundaries (user input, external APIs).
- No premature abstraction. 3 similar lines beat a bad factoring.
- No compatibility flags or `// removed` comments. Delete cleanly.

## Justifiability rule (review-enforced)

Every new file or exported symbol must have ≥1 caller in the diff or in the existing code. Reviewers must grep for callers empirically before approving — `[OBSERVED]` evidence required. Zero callers = orphan code = block.

## Architectural decisions live in ADRs

- Format: Nygard ADR (Context / Decision / Consequences) at `.claude/decisions/NNNN-<slug>.md`.
- **Append-only.** Never modify an existing ADR. To change your mind, create a new ADR with `Status: Supersedes NNNN`.
- Mutable state goes to `.claude/state/` (`STATE.md`, `ROADMAP.md`, `JOURNAL.md`).

## Autonomy

Once the user invokes a command, this is consent for its nominal function. Do not re-ask approval for:
- Writing files in the requested scope
- Iterating fixes after a review verdict
- Providing missing context to a sub-agent

Ask only for: true ambiguity, major architecture decisions without evidence, destructive actions out of scope, unrecoverable blockages.

If a decision can be settled by an autonomous senior without consulting the client, settle it.
