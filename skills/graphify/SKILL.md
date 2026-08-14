---
description: Per-project Graphify orientation graph lifecycle — init, update, status, off. Builds a local tree-sitter knowledge graph consumed by /team briefs and agents for orientation; never replaces [OBSERVED] verification (ADR 0019).
---

## Goal

Per [ADR 0019](../../decisions/0019-graphify-orientation-graph-integration.md): manage the per-project orientation graph (`graphify-out/`) that `/team` teammates and agents use to orient in a codebase before reading files. Code extraction is 100% local (tree-sitter, no API key). The graph is an **orientation** artifact (`[SOURCE]`) — verification claims always stay `[OBSERVED]` on the working tree.

**NEVER run `graphify claude install`** (ADR 0019 §D-2): the upstream integration rewrites CLAUDE.md and installs a PreToolUse nudge hook that conflicts with the evidence-based protocol. This skill is the only sanctioned integration path.

## Argument parsing

`$ARGUMENTS` = `[init|update|status|off] [path]` (path defaults to `.`).

No argument → auto mode:
- `graphify-out/graph.json` absent → run the **evaluation** then propose `init`
- present → run `status`; if stale, propose `update`

## Subcommands

### init

1. **Preflight**: `command -v graphify || uv tool install graphifyy` (binary is `graphify`; the PyPI package is `graphifyy`, double y). Requires `uv` (present on this machine).
2. **Evaluation gate**: count code files — `git ls-files | grep -cE '\.(py|pyi|js|jsx|ts|tsx|go|rs|java|kt|kts|c|h|cc|cpp|hpp|cs|rb|php|swift|m|mm|scala|sql|sh|bash|zsh|lua|zig|ex|exs|erl|tf|vue|svelte|jl|hs|proto)$'`. If < 200 (ADR 0020), report that the orientation gain is likely marginal (project CLAUDE.md already covers orientation at this size) and confirm via AskUserQuestion before proceeding. ≥ 200 → proceed.
3. **Build**: `graphify update <path>` — initial build and incremental update are the same command; AST-only, no LLM, no key. Report the `N nodes, M edges, K communities` line.
4. **Gitignore**: append `graphify-out/` to the project `.gitignore` if not already there (ADR 0019 §D-5 — solo use, the graph is a derived artifact).
5. **Freshness hooks**: `graphify hook install` — installs post-commit/post-checkout AST-only rebuilds. Appends to existing hooks via a `# graphify-hook-start` marked section (verified non-destructive); skips itself during rebase/merge/cherry-pick; bypass with `GRAPHIFY_SKIP_HOOK=1`.
6. **Report**: paths (`graphify-out/GRAPH_REPORT.md`, `graph.json`, `graph.html`), and remind: `/team` picks the graph up automatically at STEP 0; ad-hoc queries via `graphify query "<question>" --context call --context import` (unfiltered BFS drags in docs/config noise), `graphify explain|affected "<node>"` (needs a unique node label — symbol names, not repeated basenames).

### update

`graphify update <path>`. After a refactor that *deleted* code, the rebuild may have fewer nodes and be refused — rerun with `--force` (or `GRAPHIFY_FORCE=1`). Usually unnecessary: the post-commit hook keeps the graph fresh.

### status

Report, in ≤ 6 lines:
- graph present? (`graphify-out/graph.json`)
- node/edge counts (`python3 -c "import json;g=json.load(open('graphify-out/graph.json'));print(len(g.get('nodes',[])),len(g.get('edges',g.get('links',[])))"` — or read the header of `GRAPH_REPORT.md`)
- stale? (`graph.json` mtime vs `git log -1 --format=%ct`)
- freshness hooks installed? (`graphify hook status`)

### off

`graphify hook uninstall`, then ask whether to also delete `graphify-out/` (`rm -rf graphify-out/`). Leave the `uv` tool installed (other projects may use it).

## Consumption contract (for reference — enforced by agents' common block)

Orientation: `GRAPH_REPORT.md` + `graphify query --context call --context import` → cite as `[SOURCE: graphify-out/graph.json]`, then read only the files the graph points to. Verification (callers, dead code, justifiability): always `[OBSERVED]` via grep/read — the graph is an index, possibly stale, never proof. Known limits (field-tested 2026-06-10 on TheTeacher): community names stay `Community N` placeholders in keyless local mode; `explain`/`affected` fail on repeated basenames (7× `render.tsx`).
