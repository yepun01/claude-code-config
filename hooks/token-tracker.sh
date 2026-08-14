#!/usr/bin/env bash
# token-tracker.sh — Hook Stop + CLI report
# Parse les sessions Claude Code (JSONL) et accumule les stats de tokens
# Mode hook: append une ligne au cache a chaque Stop (dedupe write-time par session_id)
# Mode --report: affiche un resume lisible (--json pour sortie machine)
#
# [SOURCE: mission spec] Silencieux par design: ne DOIT jamais crash
# (un hook qui bloque bloquerait Claude Code). Pas de `set -e`, exit 0 systematique.

set -uo pipefail

CACHE_DIR="${HOME}/.claude/cache"
STATS_FILE="${CACHE_DIR}/token-stats.jsonl"
PROJECTS_DIR="${HOME}/.claude/projects"
ERROR_LOG="${CACHE_DIR}/token-tracker.err"

# ---------- helpers ----------

log_err() {
    mkdir -p "$CACHE_DIR" 2>/dev/null || return 0
    printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$ERROR_LOG" 2>/dev/null || true
}

fmt_int() {
    # Format integer with thousands separator using awk (portable vs printf)
    awk -v n="$1" 'BEGIN {
        s = sprintf("%d", n)
        out = ""
        while (length(s) > 3) {
            out = "," substr(s, length(s)-2) out
            s = substr(s, 1, length(s)-3)
        }
        print s out
    }'
}

# [INTUITION] Aucune var d'env CLAUDE_SESSION_ID observee dans quality-gate.sh /
# auto-format.sh — on se base donc sur le payload JSON stdin (convention moderne
# des hooks Claude Code) avec fallback sur le JSONL le plus recent.
#
# Find the transcript JSONL to parse. Priority order:
#   1. stdin JSON with .transcript_path  (Claude Code modern hook payload)
#   2. stdin JSON with .session_id → search projects/ for matching file
#   3. Most recently modified *.jsonl in ~/.claude/projects/*/
find_transcript() {
    local stdin_json="$1"
    local path=""

    if [ -n "$stdin_json" ] && command -v jq &>/dev/null; then
        path=$(printf '%s' "$stdin_json" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
        if [ -n "$path" ] && [ -f "$path" ]; then
            printf '%s' "$path"
            return 0
        fi
        local sid
        sid=$(printf '%s' "$stdin_json" | jq -r '.session_id // empty' 2>/dev/null || echo "")
        if [ -n "$sid" ]; then
            path=$(find "$PROJECTS_DIR" -maxdepth 2 -name "${sid}.jsonl" -type f 2>/dev/null | head -1)
            if [ -n "$path" ] && [ -f "$path" ]; then
                printf '%s' "$path"
                return 0
            fi
        fi
    fi

    # [INTUITION] stat prend des flags differents sur BSD (macOS) et GNU (Linux) —
    # on detecte via uname pour rester portable entre les deux.
    # Fallback: newest jsonl across all project dirs
    if [ -d "$PROJECTS_DIR" ]; then
        if [ "$(uname)" = "Darwin" ]; then
            path=$(find "$PROJECTS_DIR" -maxdepth 2 -name "*.jsonl" -type f -exec stat -f '%m %N' {} \; 2>/dev/null \
                | sort -rn | head -1 | awk '{print $2}')
        else
            path=$(find "$PROJECTS_DIR" -maxdepth 2 -name "*.jsonl" -type f -printf '%T@ %p\n' 2>/dev/null \
                | sort -rn | head -1 | cut -d' ' -f2-)
        fi
        if [ -n "$path" ] && [ -f "$path" ]; then
            printf '%s' "$path"
            return 0
        fi
    fi

    return 1
}

# [OBSERVED: ~/.claude/projects/*/<uuid>.jsonl] Format JSONL confirme :
# les entrees `type == "assistant"` portent `.message.usage` avec input_tokens /
# output_tokens / cache_creation_input_tokens / cache_read_input_tokens, et
# `.message.model` + `.sessionId` + `.timestamp` au niveau racine.
#
# Aggregate token stats for a single transcript JSONL.
# Output (on success): a JSON object ready to append to token-stats.jsonl.
aggregate_transcript() {
    local transcript="$1"
    if [ ! -f "$transcript" ]; then
        return 1
    fi

    # [INTUITION] Aucune colonne "agent_name" n'existe dans les assistant entries
    # observees (isSidechain toujours false sur les sessions inspectees).
    # On derive un slug depuis le dossier projet, et on strip le prefixe
    # `-Users-$USER-` pour NE PAS leaker le chemin home si le cache est partage.
    local project_slug
    project_slug=$(basename "$(dirname "$transcript")" 2>/dev/null || echo "unknown")
    # Strip encoded home path. Example:
    #   -Users-alice--claude       -> claude
    #   -Users-foo-conductor-workspaces-app    -> conductor-workspaces-app
    if [ -n "${USER:-}" ]; then
        project_slug="${project_slug#-Users-${USER}-}"
    fi
    # Strip any residual leading dashes from slash-encoding
    project_slug="${project_slug#-}"
    project_slug="${project_slug#-}"
    [ -z "$project_slug" ] && project_slug="unknown"

    # [SOURCE: changelog 2.1.133] Hooks receive active effort level via
    # $CLAUDE_EFFORT env var. Snapshot at Stop time — if user toggles /effort
    # mid-session this captures the level at session end, not per-message.
    local effort_level="${CLAUDE_EFFORT:-unknown}"

    # Use jq to sum usage across all assistant entries. Session id/model taken
    # from the first assistant entry that carries them.
    jq -cs --arg agent "$project_slug" --arg transcript "$transcript" --arg effort "$effort_level" '
        map(select(.type == "assistant" and .message.usage)) as $msgs
        | if ($msgs | length) == 0 then empty else
            {
                session_id: ($msgs[0].sessionId // "unknown"),
                timestamp:  ($msgs[-1].timestamp // (now | todate)),
                agent:      $agent,
                effort:     $effort,
                model:      ($msgs[0].message.model // "unknown"),
                input_tokens:   ([ $msgs[].message.usage.input_tokens           // 0 ] | add),
                output_tokens:  ([ $msgs[].message.usage.output_tokens          // 0 ] | add),
                cache_creation: ([ $msgs[].message.usage.cache_creation_input_tokens // 0 ] | add),
                cache_read:     ([ $msgs[].message.usage.cache_read_input_tokens     // 0 ] | add)
            }
            | .total = (.input_tokens + .output_tokens + .cache_creation + .cache_read)
          end
    ' "$transcript" 2>/dev/null
}

# ---------- modes ----------

# [INTUITION] Write-time dedupe par session_id : evite la croissance unbounded
# du cache JSONL. Chaque Stop reecrit atomiquement le fichier en supprimant les
# anciennes entrees de la session courante, puis append la nouvelle. Le nombre
# de lignes reste borne au nombre de sessions distinctes (~10-100, pas ~10k).
write_record_dedup() {
    local record="$1"
    local sid
    sid=$(printf '%s' "$record" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")

    local tmpfile="${STATS_FILE}.tmp.$$"

    if [ -f "$STATS_FILE" ] && [ -s "$STATS_FILE" ]; then
        # Keep all records EXCEPT those matching current session_id.
        # Fallback to copy if jq chokes on corrupted lines.
        if ! jq -c --arg sid "$sid" 'select(.session_id != $sid)' "$STATS_FILE" \
                > "$tmpfile" 2>/dev/null; then
            cp "$STATS_FILE" "$tmpfile" 2>/dev/null || : > "$tmpfile"
        fi
    else
        : > "$tmpfile"
    fi

    printf '%s\n' "$record" >> "$tmpfile" 2>/dev/null || {
        rm -f "$tmpfile" 2>/dev/null
        return 1
    }
    mv -f "$tmpfile" "$STATS_FILE" 2>/dev/null || {
        rm -f "$tmpfile" 2>/dev/null
        return 1
    }
    return 0
}

run_hook() {
    mkdir -p "$CACHE_DIR" 2>/dev/null || { log_err "mkdir $CACHE_DIR failed"; return 0; }

    if ! command -v jq &>/dev/null; then
        log_err "jq not found, skipping"
        return 0
    fi

    # Read stdin non-blocking (Claude Code passes JSON; CLI invocation: empty)
    local stdin_json=""
    if [ ! -t 0 ]; then
        stdin_json=$(cat 2>/dev/null || echo "")
    fi

    local transcript
    transcript=$(find_transcript "$stdin_json") || {
        log_err "no transcript found"
        return 0
    }

    local record
    record=$(aggregate_transcript "$transcript") || {
        log_err "aggregate failed for $transcript"
        return 0
    }

    if [ -z "$record" ]; then
        return 0  # transcript had no assistant usage entries yet
    fi

    write_record_dedup "$record" || log_err "write_record_dedup failed"
    return 0
}

# [INTUITION] Safety net: le cache est normalement deja dedupe a l'ecriture
# (write_record_dedup), mais on redudupe au rapport pour survivre aux fichiers
# legacy ou a une edition manuelle qui aurait introduit des doublons.
#
# Dedupe records: keep latest row per session_id (based on file order).
# Outputs a JSON array on stdout.
dedupe_records() {
    if [ ! -f "$STATS_FILE" ] || [ ! -s "$STATS_FILE" ]; then
        echo "[]"
        return 0
    fi
    jq -cs '
        reduce .[] as $r ({}; .[$r.session_id // "unknown"] = $r)
        | [ .[] ]
    ' "$STATS_FILE" 2>/dev/null || echo "[]"
}

run_report() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required for --report" >&2
        return 1
    fi

    local json_mode="$1"
    local records
    records=$(dedupe_records)
    local count
    count=$(printf '%s' "$records" | jq 'length' 2>/dev/null || echo 0)

    if [ "$json_mode" = "1" ]; then
        printf '%s' "$records" | jq '
            if length == 0 then
                {sessions: 0, total: 0, note: "no data yet"}
            else
                {
                    sessions: length,
                    period: { from: (min_by(.timestamp).timestamp), to: (max_by(.timestamp).timestamp) },
                    totals: {
                        input_tokens:   (map(.input_tokens   // 0) | add),
                        output_tokens:  (map(.output_tokens  // 0) | add),
                        cache_creation: (map(.cache_creation // 0) | add),
                        cache_read:     (map(.cache_read     // 0) | add),
                        total:          (map(.total          // 0) | add)
                    },
                    by_model: (
                        group_by(.model)
                        | map({model: .[0].model, total: (map(.total // 0) | add), sessions: length})
                        | sort_by(-.total)
                    ),
                    by_agent: (
                        group_by(.agent)
                        | map({agent: .[0].agent, total: (map(.total // 0) | add), sessions: length})
                        | sort_by(-.total)
                    ),
                    by_effort: (
                        group_by(.effort // "unknown")
                        | map({effort: (.[0].effort // "unknown"), total: (map(.total // 0) | add), sessions: length})
                        | sort_by(-.total)
                    ),
                    top_sessions: (
                        sort_by(-(.total // 0))[:5]
                        | map({session_id, timestamp, agent, model, total})
                    )
                }
            end
        '
        return 0
    fi

    echo "=== Token Stats Report ==="
    if [ "$count" = "0" ]; then
        echo "Aucune donnee dans ${STATS_FILE}"
        echo "(Le hook s'alimentera automatiquement a chaque fin de session.)"
        return 0
    fi

    local period_from period_to
    period_from=$(printf '%s' "$records" | jq -r 'min_by(.timestamp).timestamp' 2>/dev/null || echo "?")
    period_to=$(printf '%s' "$records" | jq -r 'max_by(.timestamp).timestamp' 2>/dev/null || echo "?")
    printf 'Periode : %s -> %s\n' "${period_from:0:10}" "${period_to:0:10}"
    printf 'Sessions: %s\n\n' "$count"

    # Totals
    local tot_in tot_out tot_cc tot_cr tot_all
    tot_in=$(printf  '%s' "$records" | jq '[.[].input_tokens   // 0] | add' 2>/dev/null || echo 0)
    tot_out=$(printf '%s' "$records" | jq '[.[].output_tokens  // 0] | add' 2>/dev/null || echo 0)
    tot_cc=$(printf  '%s' "$records" | jq '[.[].cache_creation // 0] | add' 2>/dev/null || echo 0)
    tot_cr=$(printf  '%s' "$records" | jq '[.[].cache_read     // 0] | add' 2>/dev/null || echo 0)
    tot_all=$(printf '%s' "$records" | jq '[.[].total          // 0] | add' 2>/dev/null || echo 0)

    printf 'Total tokens: %s\n' "$(fmt_int "$tot_all")"
    printf '  Input:        %14s\n' "$(fmt_int "$tot_in")"
    printf '  Output:       %14s\n' "$(fmt_int "$tot_out")"
    printf '  Cache create: %14s\n' "$(fmt_int "$tot_cc")"
    printf '  Cache read:   %14s\n\n' "$(fmt_int "$tot_cr")"

    # By model
    echo "By model:"
    printf '%s' "$records" | jq -r --argjson total "$tot_all" '
        group_by(.model)
        | map({model: .[0].model, total: (map(.total // 0) | add)})
        | sort_by(-.total)
        | .[]
        | "\(.model)\t\(.total)\t\( if $total > 0 then ((.total * 100 / $total) | floor) else 0 end )"
    ' 2>/dev/null | while IFS=$'\t' read -r model total pct; do
        printf '  %s: %s (%s%%)\n' "$model" "$(fmt_int "$total")" "$pct"
    done
    echo ""

    # By agent
    echo "By agent (project context):"
    printf '%s' "$records" | jq -r '
        group_by(.agent)
        | map({agent: .[0].agent, total: (map(.total // 0) | add), sessions: length})
        | sort_by(-.total)
        | .[]
        | "\(.agent)\t\(.sessions)\t\(.total)"
    ' 2>/dev/null | while IFS=$'\t' read -r agent sessions total; do
        printf '  %s [%s sess]: %s\n' "$agent" "$sessions" "$(fmt_int "$total")"
    done
    echo ""

    # By effort level
    echo "By effort level:"
    printf '%s' "$records" | jq -r '
        group_by(.effort // "unknown")
        | map({effort: (.[0].effort // "unknown"), total: (map(.total // 0) | add), sessions: length})
        | sort_by(-.total)
        | .[]
        | "\(.effort)\t\(.sessions)\t\(.total)"
    ' 2>/dev/null | while IFS=$'\t' read -r effort sessions total; do
        printf '  %s [%s sess]: %s\n' "$effort" "$sessions" "$(fmt_int "$total")"
    done
    echo ""

    # Top 5 sessions (use tab separator to survive awk/sed)
    echo "Top 5 sessions (most expensive):"
    printf '%s' "$records" | jq -r '
        sort_by(-(.total // 0))[:5]
        | to_entries[]
        | "\(.key + 1)\t\(.value.timestamp[0:16])\t\(.value.agent)\t\(.value.total)\t\(.value.session_id[0:8])"
    ' 2>/dev/null | while IFS=$'\t' read -r rank ts agent total sid; do
        printf '  %s. %s  %s  %s tok  (%s)\n' \
            "$rank" "$ts" "$agent" "$(fmt_int "$total")" "$sid"
    done
}

# ---------- dispatch ----------

main() {
    if [ "${1:-}" = "--report" ]; then
        local json=0
        [ "${2:-}" = "--json" ] && json=1
        run_report "$json"
        return 0
    fi
    run_hook
    return 0
}

main "$@"
exit 0
