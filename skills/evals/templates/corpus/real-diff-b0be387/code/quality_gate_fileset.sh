#!/usr/bin/env bash
# Build per-language file lists from the working-tree diff for downstream linters.
# Runs as a Stop-hook on every git-modified shell session.

set -uo pipefail

MODIFIED=$(git diff --name-only 2>/dev/null || true)
if [ -z "$MODIFIED" ]; then
    exit 0
fi

mapfile -t JS_FILES < <(echo "$MODIFIED" | grep -E '\.[jt]sx?$' || true)
mapfile -t PY_FILES < <(echo "$MODIFIED" | grep '\.py$' || true)
mapfile -t GO_FILES < <(echo "$MODIFIED" | grep '\.go$' || true)

if [ ${#JS_FILES[@]} -gt 0 ] && command -v npx &>/dev/null; then
    npx eslint --no-error-on-unmatched-pattern -- "${JS_FILES[@]}"
fi
