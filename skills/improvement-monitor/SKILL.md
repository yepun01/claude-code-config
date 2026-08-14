---
description: Monthly radar — Claude Code changelog deltas since last run, classified relevance vs plugin inventory. Surfaces a single PENDING improvement and notifies; never auto-merges (ADR 0013).
---

## Goal

Per [ADR 0012](../../decisions/0012-recurring-improvement-monitoring.md): produce a 1-page monthly report flagging interesting deltas in Claude Code itself (changelog) that could affect this plugin. Pure radar — read on next session, decide what (if anything) lands in the backlog. **Never** auto-write ADRs, never auto-modify code.

## Workflow

1. Run `~/.claude/hooks/improvement-monitor.sh`. It outputs raw changelog deltas (since last monitored version → current installed version) to stdout. Capture via Bash.

2. **Classify each entry** against the plugin's surface area:
   - `[high]` — touches an axis the plugin actively uses (hooks, agent-teams, MCP, sandboxing, statusline, /effort, plugin distribution)
   - `[mid]` — touches Claude Code surface but plugin partially covers (skills primitives, settings, slash-commands)
   - `[skip]` — irrelevant (IDE-specific fixes, terminal rendering, niche edge cases)

   Reference for "what plugin covers": read `AGENTS.md` + `CLAUDE.md` + `state/IMPROVEMENT-BACKLOG.md` (Now/Next/Later already-tracked items).

3. **Optionally** WebFetch latest 1-3 Anthropic Engineering posts since last run (https://www.anthropic.com/engineering) — scan headlines, fetch full text only if title looks high-relevance.

4. **Write** `state/MONITORING-{YYYY-MM}.md`:
   - Max 30 lines (hard cap).
   - Open with: `Since: <last_version>` + `Current: <current_version>` + `Fetched: <date>`.
   - Section `## Actionable` = the `[high]` items only. Each = 1 line: `- vX.Y.Z — <feature/fix> — already in plugin? <yes/no/partial>`.
   - Section `## Watch` = `[mid]` items, max 5. Same format.
   - Skip the `[skip]` bucket entirely.
   - If `## Actionable` is empty AND `## Watch` is empty → write `_No actionable deltas this period._` and exit.
   - If actionable >5 → add `**Focus warning**: >5 actionable items, pick top 3` at the top.

5. **Surface** the top 3 actionable items in the conversation summary. Do not propose ADRs, do not propose backlog edits. Just say: "If any of these matter, run `/team` to act."

6. **Trigger the PENDING handoff** (per ADR 0013). Run `IMPROVEMENT_MONITOR_WRITE_PENDING=1 ~/.claude/hooks/improvement-monitor.sh --write-pending`. The hook parses the `## Actionable` section just written and, if a `[high]` item exists, writes `state/PENDING-IMPROVEMENT.md` and fires a macOS notification "Improvement ready: <slug>. Run /apply-improvement.". Skip this step if `## Actionable` is empty (hook is idempotent — it will simply log `PENDING_WRITTEN=false` to `cache/cron-improvement-monitor.log`). If `## Actionable` has items but all are dispositioned, the hook instead writes a `# PENDING — none` sentinel (no `Item:` line); `/apply-improvement` treats that as nothing-to-apply and exits clean.

## Heuristics for relevance classification

- "Plugin uses X" anchors: agent-teams, sub-agent permissions, hooks, MCP, statusline, skills, slash commands, settings.json fields, `bypassPermissions`, sandboxing, ADR system, Memory MCP, `/effort`.
- "Plugin doesn't use X" anchors: VSCode extension, JetBrains, IDE-specific, Windows Terminal, vim mode, image paste, terminal rendering, color artifacts, OAuth flows.
- When in doubt → `[mid]` over `[high]`. The point is not to flag everything, only what the user might actually care about.

## Falsifiability gates (per ADR 0012)

- T1: 3 consecutive runs with empty `## Actionable` → drop the skill.
- T2: After 2 backlog cycles, <3 items traceable to monitor outputs → redundant.
- T3: WebFetch budget >2 USD/month or run latency >5min → ROI negative.

## Cadence

Manual invocation supported. For monthly auto-run, the user pairs with `/loop 30d /improvement-monitor` or a cron entry. Skill itself does NOT schedule — that's a separate decision.
