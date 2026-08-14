#!/usr/bin/env bash
set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
    *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock|*.svg|*.png|*.jpg) exit 0 ;;
    */.claude/tmp/*) exit 0 ;;
esac

METRICS_LOG=".claude/tmp/metrics.jsonl"
log_metric() {
    mkdir -p .claude/tmp
    echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"hook\":\"$1\",\"status\":\"$2\",\"detail\":\"$3\"}" >> "$METRICS_LOG"
}

TO=$(command -v gtimeout || command -v timeout || echo "")
run_formatter() {
    local name="$1"; shift
    local output exit_code
    if [ -n "$TO" ]; then
        output=$("$TO" 10 "$@" 2>&1)
    else
        output=$("$@" 2>&1)
    fi
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_metric "auto-format" "FAIL" "$name failed on $FILE_PATH: $(echo "$output" | head -1)"
    else
        log_metric "auto-format" "PASS" "$name $FILE_PATH"
    fi
}

case "$FILE_PATH" in
    *.ts|*.tsx|*.js|*.jsx|*.css|*.scss|*.html)
        if command -v prettier &>/dev/null; then
            run_formatter "prettier" prettier --write "$FILE_PATH"
        elif [ -f "node_modules/.bin/prettier" ]; then
            run_formatter "prettier" npx prettier --write "$FILE_PATH"
        fi
        ;;
    *.py)
        if command -v ruff &>/dev/null; then
            run_formatter "ruff" ruff format "$FILE_PATH"
        elif command -v black &>/dev/null; then
            run_formatter "black" black -q "$FILE_PATH"
        fi
        ;;
    *.go)
        command -v gofmt &>/dev/null && run_formatter "gofmt" gofmt -w "$FILE_PATH"
        ;;
    *.rs)
        command -v rustfmt &>/dev/null && run_formatter "rustfmt" rustfmt "$FILE_PATH"
        ;;
    *.lua|*.luau)
        command -v stylua &>/dev/null && run_formatter "stylua" stylua "$FILE_PATH"
        ;;
esac

exit 0
