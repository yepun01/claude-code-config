#!/usr/bin/env bash
# PreToolUse(SendMessage) — enforce lead-only routing + 200-word brevity rule.
# exit 2 = block with feedback to the model.

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL_NAME" = "SendMessage" ] || exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TO=$(echo "$INPUT" | jq -r '.tool_input.to // empty' 2>/dev/null)
MESSAGE=$(echo "$INPUT" | jq -r '.tool_input.message // empty' 2>/dev/null)

# Skip JSON protocol messages (shutdown_request, shutdown_response, plan_approval_*)
if echo "$MESSAGE" | jq -e '.type' >/dev/null 2>&1; then
  exit 0
fi

# Brevity rule (applies to everyone): target ≤200, soft-warn 201-300, hard-block >300.
# The 201-300 grace zone avoids losing info on trivial 4-50-word overages while still
# nudging the agent toward the file-path delivery pattern.
WORD_COUNT=$(echo "$MESSAGE" | wc -w | tr -d ' ')
if [ "$WORD_COUNT" -gt 300 ]; then
  echo "BLOCK: SendMessage payload is $WORD_COUNT words (hard cap 300, target ≤200)." >&2
  echo "  Long content (briefs, reports, fix lists) MUST go to a file in ~/.claude/tmp/{team}/ — SendMessage references the PATH only." >&2
  echo "  Format expected: STATUS: <performative> + 1-sentence summary + path." >&2
  exit 2
elif [ "$WORD_COUNT" -gt 200 ]; then
  echo "WARN: SendMessage payload is $WORD_COUNT words (target ≤200, hard cap 300). Accepted; next time consider trimming or moving content to a file path." >&2
  # fall through, exit 0 below
fi

# Routing rule: only teammates restricted (lead can route to anyone)
IS_LEAD="false"
for cfg in "$HOME"/.claude/teams/*/config.json; do
  [ -f "$cfg" ] || continue
  LEAD_SESSION=$(jq -r '.leadSessionId // empty' "$cfg" 2>/dev/null)
  if [ -n "$SESSION_ID" ] && [ "$LEAD_SESSION" = "$SESSION_ID" ]; then
    IS_LEAD="true"
    break
  fi
done

if [ "$IS_LEAD" = "false" ] && [ "$TO" != "team-lead" ]; then
  echo "BLOCK: peer-to-peer SendMessage not permitted. Route through 'team-lead' instead." >&2
  echo "  Current 'to': '$TO' — change to 'team-lead'." >&2
  exit 2
fi

exit 0
