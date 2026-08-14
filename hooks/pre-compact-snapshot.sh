#!/usr/bin/env bash
# Forensic log of compaction events. Append a one-line JSON record per compaction
# to ~/.claude/cache/compact-events.jsonl. Read with `jq .` for analysis.
#
# Why: post-compact-snapshot.sh injects state AFTER compaction; this captures the
# event itself (timestamp, cwd, git HEAD, active teams). Lets us answer "when did
# compactions happen and what was the disk state" without parsing transcripts.
#
# Source: feedback_platform_claims memory 2026-04-17 — verify platform behavior
# before assuming compaction preserves anything.

set -uo pipefail

cat >/dev/null  # consume hook stdin payload, no processing needed

LOG="$HOME/.claude/cache/compact-events.jsonl"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0

command -v jq &>/dev/null || exit 0

GIT=$(command -v git || true)
HEAD=""
BRANCH=""
if [ -n "$GIT" ] && "$GIT" rev-parse --git-dir >/dev/null 2>&1; then
    HEAD=$("$GIT" rev-parse --short HEAD 2>/dev/null || true)
    BRANCH=$("$GIT" symbolic-ref --short HEAD 2>/dev/null || true)
fi

TEAMS=$(find "$HOME/.claude/teams" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg event "pre_compact" \
    --arg cwd "$PWD" \
    --arg head "$HEAD" \
    --arg branch "$BRANCH" \
    --arg teams "$TEAMS" \
    '{ts: $ts, event: $event, cwd: $cwd, head: $head, branch: $branch, teams: ($teams|tonumber)}' \
    >> "$LOG" 2>/dev/null || true

exit 0
