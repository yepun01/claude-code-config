#!/usr/bin/env bash
# validate-arch.sh — Synergy contract for architect → dev/tester handoff.
#
# Validates that arch.md contains the falsification handoff section AND
# non-trivial content. Called by /team after the architect's arch.md is
# written, and as a precondition for the developer/tester briefs.
#
# Usage:
#   validate-arch.sh <arch.md path>
#   validate-arch.sh "" <team-name>     # falls back to .claude/tmp/{team}/arch.md
#
# Exit 0 = valid (arch.md contains the falsification section with >=3 tests).
# Exit 2 = block with feedback (architect must fix before dev/tester proceed).
#
# Side effect (on success): writes the parsed test list to <arch.md>.tests.txt
# for downstream consumption by developer/tester briefs.
#
# Reference: ~/.claude/docs/agent-synergy.md (CC-2 pre-mortem ↔ tests-first
# handoff). 3-bullet minimum is an [ENGINEERING] threshold, calibrated against
# typical /team task complexity (1 bullet = trivial, 5+ would be over-spec).

set -e

arch="${1:-.claude/tmp/$2/arch.md}"

if [ -z "$arch" ]; then
  echo "VALIDATE-ARCH: usage: $0 <arch.md path> | $0 \"\" <team-name>"
  exit 2
fi

if [ ! -f "$arch" ]; then
  echo "VALIDATE-ARCH: file not found ($arch)"
  exit 2
fi

# Section presence — exact heading match (preserves architect's intent)
if ! grep -qF "## Tests that would invalidate this design" "$arch"; then
  echo "VALIDATE-ARCH: missing '## Tests that would invalidate this design' section in $arch"
  echo "  This section is the falsification handoff to dev/tester."
  echo "  Architect must include >=3 falsifying tests, each naming"
  echo "  a (component, trigger condition, measurable signal)."
  exit 2
fi

# Section content: count list bullets between the section heading and the next ## heading
test_count=$(awk '
  /^## Tests that would invalidate this design$/ { flag=1; next }
  /^## / { flag=0 }
  flag && /^[[:space:]]*[-*]/ { count++ }
  END { print count+0 }
' "$arch")

if [ "$test_count" -lt 3 ]; then
  echo "VALIDATE-ARCH: <3 test bullets in '## Tests that would invalidate this design' (got $test_count) in $arch"
  echo "  Architect must list >=3 falsifying tests for dev/tester to consume."
  exit 2
fi

# Extract the section content for downstream consumption (developer/tester briefs)
output="${arch%.md}.tests.txt"
awk '
  /^## Tests that would invalidate this design$/ { flag=1; next }
  /^## / { flag=0 }
  flag { print }
' "$arch" > "$output"

echo "VALIDATE-ARCH: OK ($test_count tests in $arch); extracted to $output"
exit 0
