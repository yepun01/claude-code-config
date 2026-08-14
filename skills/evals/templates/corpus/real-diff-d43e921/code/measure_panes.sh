#!/usr/bin/env bash
# Measure tmux pane count on the claude-swarm socket before spawning a teammate.
# If panes ≥ TEAM_MAX_PANES, the lead queues the spawn (waits for a STATUS: DONE).

set -uo pipefail

TEAM_MAX_PANES="${TEAM_MAX_PANES:-12}"

SWARM_SOCK=$(ls /tmp/tmux-$(id -u)/claude-swarm-* 2>/dev/null | head -1)
if [ -n "$SWARM_SOCK" ]; then
  PANES=$(tmux -S "$SWARM_SOCK" list-panes -a 2>/dev/null | wc -l)
else
  PANES=0
fi

echo "PANES=$PANES THRESHOLD=$TEAM_MAX_PANES"

if [ "$PANES" -ge "$TEAM_MAX_PANES" ]; then
  echo "QUEUE_SPAWN"
  exit 2
fi

exit 0
