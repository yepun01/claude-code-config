#!/usr/bin/env bash
# Pre-commit: regenerate `agents/*-control.md` whenever a CC-bearing agent file
# is staged. Keeps treatment/control pair drift-free per ADR 0003 §D-3.
#
# Bypass scenarios (drift = 0 modulo the standard git bypass paths):
#   - `git commit --no-verify` — skips ALL hooks by design
#   - `git rebase` (default, non-interactive) — does NOT run pre-commit per
#     `man githooks`; only `pre-rebase` and `applypatch-msg` (am-based) fire
#   - `git rebase -i` reword/edit on already-committed objects — pre-commit
#     may or may not fire depending on the action
#   - Cross-repo merges with divergent agents — controls regen locally only
#     on the next non-bypassed commit
#
# Manual audit: `bash ~/.claude/scripts/gen-control-agents.sh --check` exits
# non-zero on drift. Run after a bypassed commit or as a SessionStart sanity.
#
# Usage (from .git/hooks/pre-commit):
#   ~/.claude/hooks/regen-control-agents.sh

set -euo pipefail

CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GEN_SCRIPT="$CLAUDE_ROOT/scripts/gen-control-agents.sh"

# Only act when the staged set touches an agent (not its control twin).
staged_agents=$(git diff --cached --name-only --diff-filter=ACM \
  | grep -E '^agents/[^/]+\.md$' \
  | grep -v -- '-control\.md$' || true)

[ -z "$staged_agents" ] && exit 0

if [ ! -x "$GEN_SCRIPT" ]; then
  echo "regen-control-agents: $GEN_SCRIPT missing or not executable" >&2
  exit 1
fi

"$GEN_SCRIPT"

# Stage the regenerated controls so the commit is atomic.
git add agents/*-control.md
