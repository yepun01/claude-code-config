#!/usr/bin/env bash
# Custom statusline for ~/.claude
# Surfaces : model · context % (color-coded) · cwd basename · active team count · last session cost
# Source schema: https://code.claude.com/docs/en/statusline

input=$(cat)

# Defensive jq: fallback "?" so the statusline never breaks if a field is null
get() { jq -r "$1 // empty" 2>/dev/null <<<"$input"; }

MODEL=$(get '.model.display_name')
[ -z "$MODEL" ] && MODEL=$(get '.model.id')
[ -z "$MODEL" ] && MODEL="?"

DIR=$(get '.workspace.current_dir')
[ -z "$DIR" ] && DIR=$(get '.cwd')
DIR_BASE="${DIR##*/}"
[ -z "$DIR_BASE" ] && DIR_BASE="?"

PCT=$(get '.context_window.used_percentage' | cut -d. -f1)
PCT="${PCT:-0}"

# Color context % (yellow >50, red >80)
if [ "$PCT" -gt 80 ] 2>/dev/null; then
    PCT_FMT=$'\033[31m'"${PCT}%"$'\033[0m'
elif [ "$PCT" -gt 50 ] 2>/dev/null; then
    PCT_FMT=$'\033[33m'"${PCT}%"$'\033[0m'
else
    PCT_FMT="${PCT}%"
fi

# Active teams (count of dirs in ~/.claude/teams/)
TEAMS=$(find "$HOME/.claude/teams" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
TEAM_DISPLAY=""
[ "$TEAMS" -gt 0 ] 2>/dev/null && TEAM_DISPLAY=$'\033[36m'" ▎team($TEAMS)"$'\033[0m'

# Last session cost (from .claude.json projects.<cwd>.lastCost)
COST=""
if [ -f "$HOME/.claude.json" ] && command -v jq &>/dev/null; then
    raw=$(jq -r --arg dir "$DIR" '.projects[$dir].lastCost // 0' "$HOME/.claude.json" 2>/dev/null)
    if [ -n "$raw" ] && [ "$raw" != "null" ] && [ "$raw" != "0" ]; then
        # awk strips trailing zeros, keeps 2 decimals max
        COST=" ▎\$$(awk -v c="$raw" 'BEGIN { printf "%.2f", c }')"
    fi
fi

printf '%s ▎ ctx %s ▎ %s%s%s\n' "$MODEL" "$PCT_FMT" "$DIR_BASE" "$TEAM_DISPLAY" "$COST"
