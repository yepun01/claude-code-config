---
description: Audit auto-memory store — surface stale refs, old entries, thin descriptions. Pure radar, no auto-modify.
---

## Goal

Inspect the user's auto-memory at `~/.claude/projects/<slug>/memory/*.md` and produce a curation report. The report is written to `state/MEMORY-DREAM-{YYYY-MM-DD}.md`. Nothing is modified — review/prune/refresh is manual.

## Workflow

1. Run `~/.claude/hooks/memory-dream.sh`. It prints the report path on stdout.
2. Read the report and surface the top 3 actionable items to the user.
3. If the user accepts an action (delete a stale entry, refresh an old one), apply it via Edit/rm — but only on explicit go.

## Heuristics applied

- **Old entries**: mtime >90 days. Older = higher chance of staleness.
- **Stale file references**: paths in the form `(file:line)` cited inside the memory body that no longer exist on disk. The file may have been renamed/deleted; the memory needs an update or removal.
- **Thin descriptions**: frontmatter `description` <20 chars. Short descriptions degrade retrieval — the memory may not match relevant queries.

## Conflicts (out of scope, manual)

The script does NOT detect contradictory memories (same topic, different conclusions). That requires semantic analysis. If the user asks for it, run a manual sweep with grep on overlapping keywords.

## Cadence

Recommended monthly. Manual invocation only — not wired to any auto-trigger. If `/loop` is set up later (cf. ADR 0012 recurring-monitoring), this skill could be invoked as part of that.
