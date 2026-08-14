#!/usr/bin/env bash
# SessionStart hook (matcher: startup) — display the project journal so the
# user knows where they left off. Reads .claude/state/JOURNAL.md (last 5 entries)
# and outputs to stdout, which Claude Code injects into the session context.

set -uo pipefail

cat >/dev/null

JOURNAL=.claude/state/JOURNAL.md
# ~/.claude is itself the .claude dir — the relative path would resolve to ~/.claude/.claude
[ "$PWD" = "$HOME/.claude" ] && JOURNAL=state/JOURNAL.md
[ -f "$JOURNAL" ] || exit 0

# Extract last 5 entries (an entry starts with "## YYYY-")
ENTRIES=$(awk '
  /^## [0-9]{4}-/ { count++; entries[count] = $0; next }
  count > 0 { entries[count] = entries[count] "\n" $0 }
  END {
    start = (count > 5) ? count - 4 : 1
    for (i = start; i <= count; i++) print entries[i]
  }
' "$JOURNAL")

[ -z "$ENTRIES" ] && exit 0

{
  echo "## Journal — $(basename "$(pwd)")"
  echo
  echo "Last entries (full journal: \`.claude/state/JOURNAL.md\`):"
  echo
  echo "$ENTRIES"
  echo
  echo "_When resuming work, check the most recent \"Next\" line and the linked ADRs/state files for context._"
} | awk 'BEGIN{s=0} {s+=length($0)+1; if(s>3000) exit; print}'

# Auto-improvement surface (ADR 0013) — visible at every session start so
# Focus-Mode-dropped osascript notifs cannot silently lose a [high] item.
PENDING="$HOME/.claude/state/PENDING-IMPROVEMENT.md"
if [ -f "$PENDING" ]; then
  echo
  echo "## PENDING IMPROVEMENT"
  head -3 "$PENDING"
  echo
  echo "_Run \`/apply-improvement\` to triage._"
fi

APPLYING=$(ls "$HOME"/.claude/state/applying/*-applying.md 2>/dev/null | head -1)
if [ -n "$APPLYING" ]; then
  echo
  echo "## IN-PROGRESS IMPROVEMENT"
  echo "Mid-apply marker: \`$APPLYING\`"
  echo "_Inspect with \`git status\` and \`git branch\`; \`rm\` the marker to reset._"
fi

# Aging global ADRs still in Proposed (radar — trigger /discuss before they rot)
[ -x "$HOME/.claude/hooks/aging-proposed-adrs.sh" ] && bash "$HOME/.claude/hooks/aging-proposed-adrs.sh"

exit 0
