#!/usr/bin/env bash
set -uo pipefail

cat >/dev/null

GIT=$(command -v git || true)
[ -z "$GIT" ] && exit 0
"$GIT" rev-parse --git-dir >/dev/null 2>&1 || exit 0

TO=$(command -v gtimeout || command -v timeout || echo "")
g() {
  if [ -n "$TO" ]; then "$TO" 2 "$@" 2>/dev/null || true
  else "$@" 2>/dev/null || true
  fi
}

{
  echo "## Post-compact snapshot — $(date '+%H:%M') — $(pwd)"
  echo
  echo "### Git"
  echo "- branch: $(g "$GIT" symbolic-ref --short HEAD || echo detached)"
  echo "- recent:"
  g "$GIT" log --oneline -3 | sed 's/^/  /'
  STAT=$(g "$GIT" diff --stat HEAD | head -15)
  [ -n "$STAT" ] && { echo "- diff stat:"; echo "$STAT" | sed 's/^/  /'; }
  ST=$(g "$GIT" status -s | head -15)
  [ -n "$ST" ] && { echo "- uncommitted:"; echo "$ST" | sed 's/^/  /'; }

  if [ -d .claude/tmp ]; then
    ART=$(find .claude/tmp -maxdepth 3 -type f 2>/dev/null | head -30)
    if [ -n "$ART" ]; then
      echo
      echo "### Team artefacts"
      echo "$ART" | sed 's/^/- /'
    fi
  fi

  if [ -d .claude/decisions ]; then
    ADRS=$(ls .claude/decisions/*.md 2>/dev/null | head -20)
    if [ -n "$ADRS" ]; then
      echo
      echo "### ADRs actifs"
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        title=$(head -1 "$f" 2>/dev/null | sed 's/^#[[:space:]]*//')
        echo "- $f: $title"
      done <<< "$ADRS"
    fi
  fi
} | awk 'BEGIN{s=0} {s+=length($0)+1; if(s>2000) exit; print}'

# Aging global ADRs still in Proposed (radar) — outside the 2000-char cap so it is never truncated away
[ -x "$HOME/.claude/hooks/aging-proposed-adrs.sh" ] && bash "$HOME/.claude/hooks/aging-proposed-adrs.sh"

exit 0
