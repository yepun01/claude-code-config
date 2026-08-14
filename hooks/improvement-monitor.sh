#!/usr/bin/env bash
# improvement-monitor.sh — fetch Claude Code changelog deltas since last
# monitoring run. Per ADR 0012: pure radar. Output = raw delta entries to
# stdout. The skill /improvement-monitor wraps this and classifies relevance,
# writing state/MONITORING-YYYY-MM.md.
#
# Extension (ADR 0013): after MONITORING is written, this hook can also parse
# the latest MONITORING-*.md, extract the top `[high]` item from `## Actionable`,
# write state/PENDING-IMPROVEMENT.md, and trigger an osascript notification.
# This side-effect path is gated by the `--write-pending` flag OR the env var
# `IMPROVEMENT_MONITOR_WRITE_PENDING=1` (cron path: stdout + pending after).
#
# Bootstrap: if no prior MONITORING file, return last ~250 lines of changelog
# (roughly 5-10 versions) so the first run isn't empty.

set -uo pipefail

STATE_DIR="$HOME/.claude/state"
CACHE_DIR="$HOME/.claude/cache"
mkdir -p "$STATE_DIR" "$CACHE_DIR"

CHANGELOG_URL="${CHANGELOG_URL:-https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md}"
CACHE="$CACHE_DIR/cc-changelog.md"
CRON_LOG="$CACHE_DIR/cron-improvement-monitor.log"

# Pin the binary to the crontab invariant ($HOME/.local/bin/claude), not PATH:
# a stale homebrew shim earlier in a divergent cron/login PATH would report the
# wrong version and corrupt the delta range. Fall back to PATH only if unpinnable.
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
[ -x "$CLAUDE_BIN" ] || CLAUDE_BIN="$(command -v claude || true)"

MODE="fetch"
for arg in "$@"; do
    case "$arg" in
        --write-pending) MODE="write-pending" ;;
    esac
done

log_heartbeat() {
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$CRON_LOG"
}

# Shipped detection: any word (>=5 chars) of the feature field — the text
# between the first two em-dashes — matching a recent commit subject means
# the item already landed in the repo. Known limit: a generic token
# ("configs") can false-positive against an unrelated commit; bounded by
# the 20-commit window and the min token length.
item_shipped() {
    local item="$1" gitlog="$2" feature token
    feature=$(printf '%s' "$item" | awk -F '—' '{print $2}' \
        | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._/-' ' ')
    for token in $feature; do
        [ "${#token}" -lt 5 ] && continue
        case "$gitlog" in *"$token"*) return 0 ;; esac
    done
    return 1
}

# Parse the latest MONITORING-YYYY-MM.md, pick the first surviving actionable
# item, write PENDING-IMPROVEMENT.md + osascript. Items are aggregated from
# ALL Actionable sections (H2 `## Actionable` or H3 addendum
# `### Actionable (nouveau cycle)`), then filtered:
#   - a section followed by a `_Disposition` footnote (before the next
#     Actionable heading) is settled by an ADR — skipped wholesale;
#   - `already in plugin? n/a` items are upstream bugfixes, nothing to apply;
#   - items whose feature keywords match `git log -20` already shipped.
# If items exist but none survives, write an explicit "no actionable" PENDING
# (no osascript). If no item at all, leave PENDING untouched (overwrite-only
# semantics — stale PENDING stays until next cycle or /apply-improvement).
#
# [OBSERVED hooks/improvement-monitor.sh] Parses MONITORING.md (LLM-classified)
# rather than re-invoking LLM — deterministic, cron-safe. ADR 0013 §D3 amended.
# Classification is delegated to the skill /improvement-monitor (which writes
# MONITORING.md in a Claude session), not to the hook directly.
generate_pending() {
    local latest
    latest=$(ls -1 "$STATE_DIR"/MONITORING-*.md 2>/dev/null | sort | tail -1)
    if [ -z "$latest" ] || [ ! -f "$latest" ]; then
        log_heartbeat "PENDING_WRITTEN=false reason=no-monitoring-file"
        return 0
    fi

    # Item format accepted: `- v2.1.121 — …`, `- **2.1.121** — …`, or
    # `- 2.1.121 — …` — the LLM-rendered MONITORING file uses markdown-bold
    # while the spec wrote `v<semver>`; widen rather than enforce.
    local items
    items=$(awk '
        /^##+[[:space:]]+Actionable/ { section++; in_items=1; next }
        /^#/ { in_items=0 }
        in_items && /^- (\*\*)?v?[0-9]+\.[0-9]+\.[0-9]+/ { n++; line[n]=$0; sec[n]=section }
        /^_Disposition/ && section { disposed[section]=1 }
        END { for (i=1; i<=n; i++) print (disposed[sec[i]] ? "disposed" : "live") "\t" line[i] }
    ' "$latest")

    local gitlog
    gitlog=$(git -C "$HOME/.claude" log --oneline -20 2>/dev/null | tr '[:upper:]' '[:lower:]')

    local total=0 top_item="" state line
    while IFS=$'\t' read -r state line; do
        [ -z "$line" ] && continue
        total=$((total + 1))
        [ "$state" = "disposed" ] && continue
        printf '%s' "$line" | grep -q 'already in plugin? n/a' && continue
        [ -n "$top_item" ] && continue
        item_shipped "$line" "$gitlog" && continue
        top_item="$line"
    done <<EOF
$items
EOF

    local filter_note="Filter: skipped sections settled by a _Disposition footnote, 'already in plugin? n/a' items, and items whose keywords match git log -20 (shipped)"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local pending="$STATE_DIR/PENDING-IMPROVEMENT.md"

    if [ "$total" -eq 0 ]; then
        log_heartbeat "PENDING_WRITTEN=false reason=no-high-actionable monitoring=$(basename "$latest")"
        return 0
    fi

    if [ -z "$top_item" ]; then
        local adr_ref="les commits récents"
        local adr_path
        adr_path=$(ls -1 "$HOME/.claude/decisions/"[0-9]*disposition*.md 2>/dev/null | sort | tail -1)
        [ -n "$adr_path" ] && adr_ref="[$(basename "$adr_path" .md)](../decisions/$(basename "$adr_path")) et les commits récents"
        cat > "$pending" <<EOF
# PENDING — none
Generated: $now
Pas d'amélioration actionnable cette session — $total items dans state/$(basename "$latest") tous dispositionnés ou shippés. Voir $adr_ref.
$filter_note
EOF
        log_heartbeat "PENDING_WRITTEN=true slug=none-all-disposed monitoring=$(basename "$latest") total=$total"
        return 0
    fi

    # Slug = the field between the first two em-dashes, kebab-cased.
    # Format expected: `- vX.Y.Z — <feature> — already in plugin? <yes|no|partial>`
    local feature
    feature=$(printf '%s' "$top_item" | awk -F '—' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    local slug
    slug=$(printf '%s' "$feature" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')
    [ -z "$slug" ] && slug="improvement"

    local source_line
    source_line=$(grep -n -F -- "$top_item" "$latest" | head -1 | cut -d: -f1)

    cat > "$pending" <<EOF
# PENDING — $slug
Source: state/$(basename "$latest") line ${source_line:-?}
Generated: $now
Item: $top_item
Rationale: top-1 actionable from monthly radar
$filter_note
EOF

    osascript -e "display notification \"Improvement ready: $slug. Run /apply-improvement.\" with title \"Claude plugin\"" >/dev/null 2>&1 || true

    log_heartbeat "PENDING_WRITTEN=true slug=$slug monitoring=$(basename "$latest")"
}

# `--write-pending` mode: skip the changelog fetch entirely and only run the
# pending generation. Used by /improvement-monitor skill step 5 after writing
# MONITORING.md, and by tests/e2e-improvement.sh.
if [ "$MODE" = "write-pending" ]; then
    generate_pending
    exit 0
fi

LATEST_MONITOR=$(ls -1 "$STATE_DIR"/MONITORING-*.md 2>/dev/null | sort | tail -1)
LAST_VERSION=""
if [ -n "$LATEST_MONITOR" ]; then
    LAST_VERSION=$(grep -m1 -oE 'Since: [0-9]+\.[0-9]+\.[0-9]+' "$LATEST_MONITOR" 2>/dev/null | awk '{print $2}')
    if [ -z "$LAST_VERSION" ]; then
        LAST_VERSION=$(grep -m1 -oE 'Current: [0-9]+\.[0-9]+\.[0-9]+' "$LATEST_MONITOR" 2>/dev/null | awk '{print $2}')
    fi
fi

CURRENT_VERSION=$("$CLAUDE_BIN" --version 2>/dev/null | awk '{print $1}')
if [ -z "$CURRENT_VERSION" ]; then
    echo "ERROR: claude --version failed (binary: ${CLAUDE_BIN:-<none>})" >&2
    exit 1
fi

# CURRENT < LAST means the detected binary is OLDER than the last monitored run —
# a PATH/version regression, not a real delta. Warn loudly rather than emit a
# bogus (often whole-file) changelog range below.
if [ -n "$LAST_VERSION" ] && [ "$LAST_VERSION" != "$CURRENT_VERSION" ] && \
   [ "$(printf '%s\n%s\n' "$LAST_VERSION" "$CURRENT_VERSION" | sort -V | tail -1)" = "$LAST_VERSION" ]; then
    echo "WARNING: detected claude $CURRENT_VERSION (via $CLAUDE_BIN) is OLDER than last-monitored $LAST_VERSION — check PATH/binary pin" >&2
fi

if ! curl -sf -o "$CACHE.tmp" "$CHANGELOG_URL"; then
    echo "ERROR: changelog fetch failed from $CHANGELOG_URL" >&2
    rm -f "$CACHE.tmp"
    exit 1
fi
mv "$CACHE.tmp" "$CACHE"

echo "# Claude Code changelog delta"
echo "# Since: ${LAST_VERSION:-bootstrap}"
echo "# Current: $CURRENT_VERSION"
echo "# Fetched: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "---"
echo

if [ -z "$LAST_VERSION" ]; then
    head -250 "$CACHE"
elif grep -q "^## $LAST_VERSION$" "$CACHE"; then
    sed "/^## $LAST_VERSION$/q" "$CACHE" | sed '$d'
else
    # LAST_VERSION absent from the changelog → the unguarded sed would dump the
    # WHOLE file (no `q` match). Declare the gap and fall back to a bounded head.
    echo "# WARNING: last-monitored version $LAST_VERSION not found in changelog — range undeterminable, showing last 250 lines as fallback"
    echo
    head -250 "$CACHE"
fi

# Cron path: when the env var is set, also run pending generation after
# emitting stdout (the skill will have written MONITORING.md by then).
if [ "${IMPROVEMENT_MONITOR_WRITE_PENDING:-0}" = "1" ]; then
    generate_pending
fi
