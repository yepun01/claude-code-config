#!/usr/bin/env bash
set -eu

# Garbage collection teams + tmp orphans
# Usage: team-gc.sh [--dry-run (default) | --force] [--threshold-days N (default 7)]
# Exit: 0 = nothing to clean, 1 = orphans found (dry-run), 2 = cleaned

THRESHOLD_DAYS="${THRESHOLD_DAYS:-7}"
MODE="${1:-}"
TEAMS_DIR="$HOME/.claude/teams"
TMP_DIR="$HOME/.claude/tmp"

old_teams=$(find "$TEAMS_DIR" -maxdepth 1 -mindepth 1 -type d -mtime "+$THRESHOLD_DAYS" 2>/dev/null || true)
old_tmps=$(find "$TMP_DIR" -maxdepth 1 -mindepth 1 -type d -mtime "+$THRESHOLD_DAYS" 2>/dev/null || true)
loose_md=$(find "$TMP_DIR" -maxdepth 1 -name "*.md" 2>/dev/null || true)

dead_socks=""
SOCK_DIR="/tmp/tmux-$(id -u)"
if [ -d "$SOCK_DIR" ]; then
  for sock in "$SOCK_DIR"/claude-swarm-*; do
    [ -S "$sock" ] || continue
    if ! tmux -S "$sock" list-sessions 2>/dev/null | grep -q .; then
      dead_socks="${dead_socks:+$dead_socks
}$sock"
    fi
  done
fi

count_nonempty() { [ -z "$1" ] && echo 0 || echo "$1" | grep -c .; }
count_teams=$(count_nonempty "$old_teams")
count_tmps=$(count_nonempty "$old_tmps")
count_md=$(count_nonempty "$loose_md")
count_socks=$(count_nonempty "$dead_socks")
total=$((count_teams + count_tmps + count_md + count_socks))

[ "$total" -eq 0 ] && { echo "team-gc: clean"; exit 0; }

echo "team-gc: $total orphans (threshold: ${THRESHOLD_DAYS} days)"
[ "$count_teams" -gt 0 ] && { echo "  Teams (${count_teams}):"; echo "$old_teams" | sed 's/^/    /'; }
[ "$count_tmps" -gt 0 ] && { echo "  Tmp dirs (${count_tmps}):"; echo "$old_tmps" | sed 's/^/    /'; }
[ "$count_md" -gt 0 ] && { echo "  Root .md pollution (${count_md}):"; echo "$loose_md" | sed 's/^/    /'; }
[ "$count_socks" -gt 0 ] && { echo "  Dead tmux sockets (${count_socks}):"; echo "$dead_socks" | sed 's/^/    /'; }

if [ "$MODE" = "--force" ]; then
  while IFS= read -r team; do
    [ -n "$team" ] && rm -rf "$team"
  done <<< "$old_teams"
  while IFS= read -r d; do
    [ -n "$d" ] && rm -rf "$d"
  done <<< "$old_tmps"
  while IFS= read -r f; do
    [ -n "$f" ] && rm -f "$f"
  done <<< "$loose_md"
  while IFS= read -r s; do
    [ -n "$s" ] && rm -f "$s"
  done <<< "$dead_socks"
  echo "team-gc: cleaned $total items"
  exit 2
fi

exit 1
