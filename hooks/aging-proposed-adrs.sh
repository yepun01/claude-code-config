#!/usr/bin/env bash
# Emit a compact one-block radar of GLOBAL plugin ADRs (~/.claude/decisions/)
# still in `Proposed` status past a staleness threshold. Pure radar: stdout only.
# Called by session-resume-journal.sh (SessionStart) and post-compact-snapshot.sh.
#
# Status resolution handles the 4 coexisting formats (## Status header with value
# on the next line; inline `Status:` / `**Status**:` / `- **Status** :`) and matches
# only the DECLARED status by prefix, so a prose "Proposed" (e.g. 0016 body) never
# false-positives. 0013 is excluded by design (frozen on purpose — ADR 0013).

set -uo pipefail

DECISIONS="$HOME/.claude/decisions"
THRESHOLD="${ADR_PROPOSED_AGE_DAYS:-14}"
[ -d "$DECISIONS" ] || exit 0

now=$(date +%s)
rows=""
for f in "$DECISIONS"/[0-9]*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .md)
    case "$base" in 0013*) continue ;; esac

    status=$(awk '
        /^#+[[:space:]]*Status[[:space:]]*$/ { gm=1; next }
        gm==1 && NF>0 { print; exit }
        /^[-*[:space:]]*\**Status\**[[:space:]]*:/ {
            sub(/^[-*[:space:]]*\**Status\**[[:space:]]*:[[:space:]]*/, ""); print; exit
        }
    ' "$f")
    case "$status" in
        Proposed*) ;;
        *) continue ;;
    esac
    # A FULLY-superseded ADR carries a dedicated `Superseded by: <ADR …>` field (≠ —);
    # it is settled, skip it. Inline "partially superseded" prose inside the Status does
    # NOT count — those ADRs are still pending and worth flagging (ADR 0016 D-2 records
    # full supersession in the dedicated field, partial amendment stays in prose).
    sb=$(awk -F': *' 'tolower($0) ~ /^superseded by:/ { print $2; exit }' "$f")
    case "$sb" in ''|'—'|'-') ;; *) continue ;; esac

    # Age from the AUTHORED date in the Status line (`Proposed (YYYY-MM-DD)`) when
    # present — a back-pointer edit (sanctioned by ADR 0016 D-2) rewrites the file
    # and resets mtime, which would falsely reset the staleness clock. Fall back to
    # mtime only when the Status carries no parseable date (e.g. 0014 `Status: Proposed`).
    adate=$(printf '%s' "$status" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    basis=""
    if [ -n "$adate" ]; then
        if [ "$(uname)" = "Darwin" ]; then
            basis=$(date -j -f '%Y-%m-%d' "$adate" '+%s' 2>/dev/null || true)
        else
            basis=$(date -d "$adate" '+%s' 2>/dev/null || true)
        fi
    fi
    if [ -z "$basis" ]; then
        if [ "$(uname)" = "Darwin" ]; then
            basis=$(stat -f '%m' "$f" 2>/dev/null || echo "$now")
        else
            basis=$(stat -c '%Y' "$f" 2>/dev/null || echo "$now")
        fi
    fi
    days=$(( (now - basis) / 86400 ))
    [ "$days" -gt "$THRESHOLD" ] || continue

    num="${base%%-*}"
    rows="${rows}${days}\t${num}\n"
done

[ -z "$rows" ] && exit 0

list=$(printf '%b' "$rows" | sort -rn | awk '{ printf "%s (%dj), ", $2, $1 }' | sed 's/, $//')

echo
echo "## ADRs globaux en attente (Proposed > ${THRESHOLD}j — \`/discuss\` ou \`/spec\` pour trancher)"
echo "$list"
echo "_0013 gelé volontairement (exclu). Le plus ancien d'abord._"

exit 0
