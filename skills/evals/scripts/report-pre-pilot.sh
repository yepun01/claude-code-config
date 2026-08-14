#!/usr/bin/env bash
# Pre-pilot report generator (D-8 fallback metric, escalation verdict).
# See ~/.claude/decisions/0006-evals-skill-multifile.md (split from SKILL.md L490-577).
# Arg: $1 = run timestamp (YYYYMMDDTHHMMSSZ) or run dir basename. Empty = latest run.

set -euo pipefail

TS_ARG="${1:-}"
if [ -n "$TS_ARG" ]; then
  RUN_DIR="evals/runs/$TS_ARG"
else
  RUN_DIR=$(ls -1d evals/runs/*/ 2>/dev/null | sort | tail -1 | sed 's:/*$::')
fi
[ -d "$RUN_DIR" ] || { echo "ERROR: no run directory found." >&2; exit 1; }

MANIFEST="$RUN_DIR/manifest.jsonl"
[ -f "$MANIFEST" ] || { echo "ERROR: $RUN_DIR/manifest.jsonl missing." >&2; exit 1; }

N_EXPECTED=15
N_ACTUAL=$(wc -l < "$MANIFEST" | tr -d ' ')

if [ "$N_ACTUAL" -ne "$N_EXPECTED" ]; then
  echo "ERROR: incomplete run; resume not supported in iter-1; delete $RUN_DIR/ and rerun." >&2
  echo "  manifest n_actual=$N_ACTUAL n_expected=$N_EXPECTED" >&2
  exit 1
fi

PRIMARY=$(~/.claude/scripts/eval-stats.sh "$RUN_DIR" --metric finding_count_total)
PRIMARY_MEAN=$(printf '%s' "$PRIMARY" | jq -r '.overall_mean')

USED_METRIC="finding_count_total"
USED_PAYLOAD="$PRIMARY"
WARN=""
SHOULD_FALLBACK=$(awk -v m="$PRIMARY_MEAN" 'BEGIN { print (m < 2) ? "1" : "0" }')
if [ "$SHOULD_FALLBACK" = "1" ]; then
  USED_METRIC="output_length_chars"
  USED_PAYLOAD=$(~/.claude/scripts/eval-stats.sh "$RUN_DIR" --metric output_length_chars)
  WARN="WARNING: primary metric (finding_count_total) mean = $PRIMARY_MEAN < 2 — falling back to $USED_METRIC. See ADR 0003 §D-5 / design ADR D-8."
  echo "$WARN" >&2
fi

RATIO_MAX=$(printf '%s' "$USED_PAYLOAD" | jq -r '[.per_case | to_entries[].value.ratio] | max')
ESCALATE=$(awk -v r="$RATIO_MAX" 'BEGIN { print (r > 0.25) ? "YES" : "NO" }')

REPORT_PATH="evals/reports/pre-pilot-$(basename "$RUN_DIR").md"
mkdir -p evals/reports

{
  echo "# Pre-pilot report — $(basename "$RUN_DIR")"
  echo
  echo "**Run dir**: \`$RUN_DIR\`"
  echo "**n_actual / n_expected**: $N_ACTUAL / $N_EXPECTED"
  echo "**Verdict metric**: \`$USED_METRIC\`"
  if [ -n "$WARN" ]; then
    echo
    echo "> $WARN"
  fi
  echo
  echo "## Stats payload (verdict metric)"
  echo
  echo '```json'
  printf '%s\n' "$USED_PAYLOAD" | jq .
  echo '```'
  echo
  echo "## Stats payload (primary metric)"
  echo
  echo '```json'
  printf '%s\n' "$PRIMARY" | jq .
  echo '```'
  echo
  echo "## Verdict"
  echo
  echo "- ratio_max = $RATIO_MAX"
  echo "- threshold = 0.25 (per ADR 0003 §D-5: \"if test-retest variance is >25% of mean, escalate to n=5+\")"
  echo "- escalate N for CC-5 = **$ESCALATE**"
  echo
  echo "## HYPOTHESES.md update"
  echo
  echo "Edit \`evals/HYPOTHESES.md\` to RESOLVE Q5 with the observed sigma-ratio, and"
  echo "Q2 with the resulting N escalation. Commit the update — that locks the pre-pilot"
  echo "answer per ADR 0003 §D-4."
  echo
  echo "## Notes"
  echo
  echo "- Stubs are inline synthetic; recommend re-running on real corpus when available (per Natella et al. 2013 + ADR 0003 §D-1)."
} > "$REPORT_PATH"

echo "WROTE $REPORT_PATH"

