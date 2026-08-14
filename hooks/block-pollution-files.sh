#!/usr/bin/env bash
# PreToolUse hook : bloque fichiers pollution (NOTES.md root, _v2, .bak, old/, etc.)
# exit 2 = bloque avec feedback au modèle

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
[ -z "$FILE" ] && exit 0

# Allowlist: agents/*-control.md is autogen output of A/B toggle (ADR 0003 §D-3).
# Enumerated explicitly so a future suffix-collision (e.g., agents/foo_v2-control.md)
# falls through to the version-suffix block below. Adding a new CC-bearing agent
# requires updating this list — failure-mode is human-visible (autogen blocked).
BASENAME_PEEK=$(basename "$FILE")
case "$BASENAME_PEEK" in
  architect-control.md|code-challenger-control.md|code-reviewer-control.md|\
  deep-analyzer-control.md|designer-control.md|developer-control.md|\
  innovator-control.md|security-reviewer-control.md)
    exit 0 ;;
esac

if echo "$FILE" | grep -qE '(^|/)\.claude/tmp/[^/]+\.md$'; then
  echo "BLOCK: .md à la racine de .claude/tmp/ interdit (pollution sub-agents)." >&2
  echo "  Écris dans .claude/tmp/{team-name}/*.md à la place." >&2
  exit 2
fi

case "$FILE" in
  */.claude/tmp/*) exit 0 ;;
esac

[ -f "$FILE" ] && exit 0

BASENAME=$(basename "$FILE")
LOWER=$(echo "$BASENAME" | tr '[:upper:]' '[:lower:]')

case "$LOWER" in
  *_v[2-9].*|*_v[2-9]-*|*_new.*|*_new-*|*_old.*|*_old-*|*_copy.*|*_copy-*|*_backup.*|*_backup-*|*_final.*|*_final-*)
    echo "BLOCK: suffixe de version dans nom ($BASENAME). Édite l'original ou rename-le, ne duplique pas." >&2
    exit 2 ;;
esac

case "$LOWER" in
  *.bak|*.orig|*.backup|*.backup.*)
    echo "BLOCK: extension backup ($BASENAME). Utilise git pour l'historique." >&2
    exit 2 ;;
esac

REAL_FILE=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$FILE" 2>/dev/null || echo "$FILE")

DIR=$(dirname "$REAL_FILE")
while [ ! -d "$DIR" ] && [ "$DIR" != "/" ]; do
  DIR=$(dirname "$DIR")
done

ROOT=$(cd "$DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "")
[ -z "$ROOT" ] && exit 0

REAL_DIR=$(dirname "$REAL_FILE")

if [ "$REAL_DIR" = "$ROOT" ]; then
  case "$LOWER" in
    notes.md|plan.md|todo.md|decisions.md|analysis.md|summary.md|research.md|scratch.md|changes.md)
      echo "BLOCK: markdown parasite à la racine ($BASENAME). Mets-le dans docs/ ou édite un fichier existant." >&2
      exit 2 ;;
  esac
fi

for BAD in old backup archive; do
  if [ "$REAL_DIR" = "$ROOT/$BAD" ] || [[ "$REAL_DIR" == "$ROOT/$BAD/"* ]]; then
    echo "BLOCK: dossier parasite $BAD/ à la racine du repo. Utilise git pour l'archivage." >&2
    exit 2
  fi
done

exit 0
