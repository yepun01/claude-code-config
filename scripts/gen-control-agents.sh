#!/usr/bin/env bash
# Generate `<agent>-control.md` for each CC-bearing agent by stripping content
# between `<!-- CC-START id=CC-X -->` and `<!-- CC-END id=CC-X -->` markers AND
# rewriting the `name:` frontmatter field so `subagent_type=<X>-control` resolves
# to the control agent (ADR 0003 §D-3 step 4 spawn contract).
#
# Strip semantics: block markers only — the strip is line-based. Each agent
# wraps its CC content in a dedicated paragraph / subsection where START and
# END live on their own lines. Inline markers (START..END on a single line) are
# NOT supported in this iter — adding them would require a region-based strip
# (perl -0777 / mistletoe) and was rejected as over-engineering for iter-1.
#
# Granularity (current limitation, per ADR 0003 §D-3 H-3):
#   The strip is ALL-OR-NOTHING — depth-counter is agnostic to the CC id, so
#   ANY open marker (CC-2 / CC-4 / CC-5) causes content to be stripped. Per-CC
#   ablation (CC-2 only, CC-4 only, etc., 7 variants) requires a stack-of-ids
#   refactor. Acceptable for the iter-1 toggle which targets ALL CCs together.
#
# Drift control (ADR 0003 §D-3 H-2 caveat):
#   Pre-commit hook regen catches drift on the happy path. `git commit
#   --no-verify`, `git rebase` (default), and cross-repo merges BYPASS the hook.
#   Run `gen-control-agents.sh --check` in CI / SessionStart to close the loop.
#
# Usage:
#   gen-control-agents.sh           regenerate all *-control.md
#   gen-control-agents.sh --check   exit 1 if any *-control.md is stale or
#                                   any source file has unbalanced markers
#
# Reference: ~/.claude/decisions/0003-evaluation-protocol.md §D-3

set -euo pipefail

CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
AGENTS_DIR="$CLAUDE_ROOT/agents"

# 8 CC-bearing agents per ADR 0002 §A. tester is excluded (§B-7: no CC applies).
CC_AGENTS=(
  architect
  developer
  deep-analyzer
  designer
  innovator
  code-reviewer
  security-reviewer
  code-challenger
)

# Pre-flight: balance check + zero-marker warning.
# Returns 0 if balanced, 1 if unbalanced (errors to stderr).
validate_markers() {
  local src="$1"
  local starts ends
  starts=$(grep -c '<!-- CC-START id=CC-' "$src" 2>/dev/null || true)
  ends=$(grep -c '<!-- CC-END id=CC-' "$src" 2>/dev/null || true)
  starts=${starts:-0}
  ends=${ends:-0}
  if [ "$starts" -ne "$ends" ]; then
    echo "ERROR: $src has unbalanced CC markers ($starts START vs $ends END)" >&2
    return 1
  fi
  if [ "$starts" -eq 0 ]; then
    echo "WARN: $src has 0 CC markers; control will be identical to source (modulo name rewrite)" >&2
  fi
  return 0
}

# Strip CC blocks AND rewrite the frontmatter name field.
# Single awk pass with a depth counter. The END clause fails loud if any START
# was not closed (catches the orphan-marker silent-truncation bug). The first
# pass through the frontmatter rewrites `name: <agent>` → `name: <agent>-control`
# (assumes `name:` is the first line after the opening `---`; verified true for
# all 8 current CC-bearing agents).
strip_cc_blocks() {
  local src="$1"
  local agent_name="$2"
  awk -v name="$agent_name" '
    BEGIN { in_fm = 0; fm_done = 0 }
    !fm_done && /^---$/ { in_fm = !in_fm; if (!in_fm) fm_done = 1; print; next }
    !fm_done && in_fm && /^name: / { print "name: " name "-control"; next }
    /<!-- CC-START id=CC-/ { depth++; next }
    /<!-- CC-END id=CC-/   {
      if (depth > 0) depth--
      else { print "ERROR: orphan CC-END before any START" > "/dev/stderr"; exit 1 }
      next
    }
    depth == 0 { print }
    END {
      if (depth != 0) {
        print "ERROR: unbalanced CC markers (final depth=" depth ")" > "/dev/stderr"
        exit 1
      }
    }
  ' "$src"
}

MODE="write"
if [ "${1:-}" = "--check" ]; then
  MODE="check"
fi

drift_found=0
for agent in "${CC_AGENTS[@]}"; do
  src="$AGENTS_DIR/$agent.md"
  dst="$AGENTS_DIR/$agent-control.md"

  [ -f "$src" ] || { echo "MISSING: $src" >&2; exit 1; }

  validate_markers "$src" || exit 1

  generated="$(strip_cc_blocks "$src" "$agent")"

  if [ "$MODE" = "check" ]; then
    if [ ! -f "$dst" ]; then
      echo "DRIFT: $dst does not exist (run gen-control-agents.sh)" >&2
      drift_found=1
      continue
    fi
    if ! diff -q <(printf '%s\n' "$generated") "$dst" >/dev/null 2>&1; then
      echo "DRIFT: $dst diverges from regen of $src" >&2
      drift_found=1
    fi
  else
    printf '%s\n' "$generated" > "$dst"
  fi
done

if [ "$MODE" = "check" ]; then
  exit "$drift_found"
fi
