#!/usr/bin/env bash
# Memory dreaming — audit the auto-memory store, surface curation candidates.
# Pure radar: no auto-modify, no destructive action. Output a markdown report
# at state/MEMORY-DREAM-{YYYY-MM-DD}.md. Skill /dream wraps this.
#
# Heuristics (per IMPROVEMENT-BACKLOG X3):
#   - Stale file:line refs: cited paths that no longer exist on disk
#   - Old entries: mtime >90 days
#   - Suspicious type drift: feedback memories aging without re-validation
#
# Target store: ~/.claude/projects/<slug>/memory/*.md (auto-memory). The MCP
# knowledge-graph (~/.claude/memory/knowledge-graph.jsonl) is barely used
# (2 entities at last audit) and not the primary curation target.

set -uo pipefail

MEMORY_DIR="${MEMORY_DIR:-$HOME/.claude/projects/$(pwd | sed 's|[/.]|-|g')/memory}"
STATE_DIR="$HOME/.claude/state"
DATE=$(date '+%Y-%m-%d')
REPORT="$STATE_DIR/MEMORY-DREAM-$DATE.md"

[ -d "$MEMORY_DIR" ] || { echo "memory dir not found: $MEMORY_DIR" >&2; exit 1; }
mkdir -p "$STATE_DIR"

stale_refs=()
old_entries=()
empty_descriptions=()

now=$(date +%s)
threshold_days=90
threshold_secs=$((threshold_days * 86400))

while IFS= read -r f; do
    base=$(basename "$f")
    [ "$base" = "MEMORY.md" ] && continue

    if [ "$(uname)" = "Darwin" ]; then
        mtime=$(stat -f '%m' "$f" 2>/dev/null || echo 0)
    else
        mtime=$(stat -c '%Y' "$f" 2>/dev/null || echo 0)
    fi
    age_secs=$((now - mtime))

    if [ "$age_secs" -gt "$threshold_secs" ]; then
        days=$((age_secs / 86400))
        old_entries+=("$base ($days days)")
    fi

    desc=$(awk '/^description:/ { sub(/^description:[[:space:]]*/,""); print; exit }' "$f" 2>/dev/null)
    if [ -z "$desc" ] || [ ${#desc} -lt 20 ]; then
        empty_descriptions+=("$base (description: '${desc:-<empty>}')")
    fi

    while IFS= read -r ref; do
        path=$(printf '%s' "$ref" | sed -E 's|^.*\(([^)]+:[0-9]+(-[0-9]+)?)\).*|\1|; s|:[0-9]+(-[0-9]+)?$||')
        path="${path//\~/$HOME}"
        if [ -n "$path" ] && [[ "$path" == /* || "$path" == ~* ]]; then
            [ -e "$path" ] || stale_refs+=("$base → $path")
        fi
    done < <(grep -oE '\([^)]+:[0-9]+(-[0-9]+)?\)' "$f" 2>/dev/null | head -5)

done < <(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null)

total_count=$(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" ! -name MEMORY.md -type f 2>/dev/null | wc -l | tr -d ' ')

{
    echo "# Memory dream report — $DATE"
    echo
    echo "Source: \`$MEMORY_DIR\` ($total_count entries scanned, MEMORY.md index excluded)."
    echo
    echo "## Old entries (>$threshold_days days since mtime)"
    echo
    if [ ${#old_entries[@]} -eq 0 ]; then
        echo "_None._"
    else
        for entry in "${old_entries[@]}"; do echo "- $entry"; done
    fi
    echo
    echo "## Stale file references (path no longer exists)"
    echo
    if [ ${#stale_refs[@]} -eq 0 ]; then
        echo "_None._"
    else
        for entry in "${stale_refs[@]}"; do echo "- $entry"; done
    fi
    echo
    echo "## Thin descriptions (<20 chars, may need rewrite for retrieval)"
    echo
    if [ ${#empty_descriptions[@]} -eq 0 ]; then
        echo "_None._"
    else
        for entry in "${empty_descriptions[@]}"; do echo "- $entry"; done
    fi
    echo
    echo "---"
    echo
    echo "_Pure radar: nothing was modified. Review and prune/refresh manually._"
} > "$REPORT"

echo "$REPORT"
