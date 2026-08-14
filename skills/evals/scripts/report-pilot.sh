#!/usr/bin/env bash
# CC-5 pilot report generator: paired Cohen's d_z + IC95 bootstrap + ADR 0003 §D-2
# verdict (PASS / SUPPRESS / UNDETERMINED) + leakage override (AUDIT-CORPUS).
#
# See ~/.claude/decisions/0007-cc5-pilot-runner.md §D-5/D-7.
#
# Arg: $1 = run timestamp (YYYYMMDDTHHMMSSZ-pilot or just YYYYMMDDTHHMMSSZ).
#      Empty = latest evals/runs/*-pilot/ dir.

set -euo pipefail

TS_ARG="${1:-}"
if [ -n "$TS_ARG" ]; then
  case "$TS_ARG" in
    *-pilot) RUN_DIR="evals/runs/$TS_ARG" ;;
    *)       RUN_DIR="evals/runs/${TS_ARG}-pilot" ;;
  esac
else
  RUN_DIR=$(ls -1d evals/runs/*-pilot/ 2>/dev/null | sort | tail -1 | sed 's:/*$::')
fi
[ -n "${RUN_DIR:-}" ] && [ -d "$RUN_DIR" ] || { echo "ERROR: no pilot run dir found." >&2; exit 1; }

MANIFEST="$RUN_DIR/manifest.jsonl"
[ -f "$MANIFEST" ] || { echo "ERROR: $RUN_DIR/manifest.jsonl missing." >&2; exit 1; }

N_ACTUAL=$(wc -l < "$MANIFEST" | tr -d ' ')
N_PAIRS_EXPECTED=$(jq -r '.paired_trial_index' "$MANIFEST" | sort -un | wc -l | tr -d ' ')
N_EXPECTED=$((N_PAIRS_EXPECTED * 2))

if [ "$N_ACTUAL" -ne "$N_EXPECTED" ]; then
  echo "ERROR: incomplete run; resume not supported in iter-1; delete $RUN_DIR/ and rerun." >&2
  echo "  manifest n_actual=$N_ACTUAL n_expected=$N_EXPECTED" >&2
  exit 1
fi

STATS=$(~/.claude/scripts/eval-stats-paired.sh "$RUN_DIR" --metric red_flag_count)

if [ "$(printf '%s' "$STATS" | jq -r 'has("error")')" = "true" ]; then
  ERR=$(printf '%s' "$STATS" | jq -r '.error')
  echo "ERROR: paired stats returned error: $ERR" >&2
  echo "  $RUN_DIR may be a smoke-test (n_pairs < 2); a real pilot needs ≥ 13×2 = 26 pairs." >&2
  exit 1
fi

D_Z=$(printf '%s' "$STATS" | jq -r '.d_z')
IC95_LOW=$(printf '%s' "$STATS" | jq -r '.ic95_low')
IC95_HIGH=$(printf '%s' "$STATS" | jq -r '.ic95_high')
N_PAIRS=$(printf '%s' "$STATS" | jq -r '.n_pairs')
LEAKAGE=$(printf '%s' "$STATS" | jq -r '.leakage_warning')

# Verdict per ADR 0003 §D-2 (sign-aware: H1 expects d_z ≤ −0.8).
# Leakage override (ADR 0003 line 161) takes precedence over PASS / SUPPRESS / UNDETERMINED.
if [ "$LEAKAGE" = "true" ]; then
  VERDICT="AUDIT-CORPUS"
  RATIONALE="|d_z|=$D_Z exceeds the 1.5 leakage threshold. Audit corpus generation prompts BEFORE accepting any verdict (per ADR 0003 line 161)."
else
  PASS=$(awk -v d="$D_Z" -v hi="$IC95_HIGH" 'BEGIN { print (d <= -0.8 && hi < 0) ? "1" : "0" }')
  SUPPRESS=$(awk -v d="$D_Z" -v lo="$IC95_LOW" -v hi="$IC95_HIGH" 'BEGIN {
    abs_d  = (d  < 0) ? -d  : d
    abs_lo = (lo < 0) ? -lo : lo
    abs_hi = (hi < 0) ? -hi : hi
    abs_max = (abs_lo > abs_hi) ? abs_lo : abs_hi
    print (abs_d < 0.5 && abs_max < 0.5) ? "1" : "0"
  }')
  if [ "$PASS" = "1" ]; then
    VERDICT="PASS"
    RATIONALE="d_z=$D_Z ≤ −0.8, IC95=[$IC95_LOW, $IC95_HIGH] excludes 0. CC-5 reduces red-flag count substantively. Advance to next CC."
  elif [ "$SUPPRESS" = "1" ]; then
    VERDICT="SUPPRESS"
    RATIONALE="|d_z|=$D_Z < 0.5, |IC95| entirely <0.5. CC-5 effect too small to retain. Remove within 30 days per ADR 0003 §D-4."
  else
    VERDICT="UNDETERMINED"
    RATIONALE="d_z=$D_Z, IC95=[$IC95_LOW, $IC95_HIGH] — IC95 spans the |d|=0.5 threshold. Escalate budget if stake warrants; do not auto-suppress."
  fi
fi

TS_ONLY=$(basename "$RUN_DIR" | sed 's/-pilot$//')
REPORT_PATH="evals/reports/pilot-$TS_ONLY.md"
mkdir -p evals/reports

# Per-case red-flag means table (treatment vs control, mean over trials).
PER_CASE_TBL=$(jq -s -r '
  group_by(.case_id) | map(
    .[0].case_id as $cid
    | ([.[] | select(.condition=="treatment") | .red_flag_count] | (add // 0) / (length // 1)) as $tm
    | ([.[] | select(.condition=="control")   | .red_flag_count] | (add // 0) / (length // 1)) as $cm
    | "| " + $cid + " | " + ($tm|tostring) + " | " + ($cm|tostring) + " | " + (($tm - $cm)|tostring) + " |"
  ) | .[]
' "$RUN_DIR"/case-*.json 2>/dev/null || echo "")

{
  echo "# CC-5 pilot report — $TS_ONLY"
  echo
  echo "## Verdict"
  echo
  echo "**$VERDICT** — $RATIONALE"
  if [ "$LEAKAGE" = "true" ]; then
    echo
    echo "> Per ADR 0003 line 161 (verbatim): \"If d>1.5 observed, pause and audit corpus"
    echo "> generation prompts for leakage.\" The corpus authoring may have inadvertently"
    echo "> encoded CC-5's exact phrasing patterns as ground-truth defects, inflating the effect."
  fi
  echo
  echo "## Run summary"
  echo
  echo "- **Run dir**: \`$RUN_DIR\`"
  echo "- **n_actual / n_expected**: $N_ACTUAL / $N_EXPECTED"
  echo "- **n_pairs**: $N_PAIRS"
  echo
  echo "## Paired-d statistics (primary metric: \`red_flag_count\`)"
  echo
  echo '```json'
  printf '%s\n' "$STATS" | jq .
  echo '```'
  echo
  if [ -n "$PER_CASE_TBL" ]; then
    echo "## Per-case red-flag means (treatment vs control)"
    echo
    echo "| case_id | mean(treatment) | mean(control) | mean_diff |"
    echo "|---|---|---|---|"
    echo "$PER_CASE_TBL"
    echo
  fi
  echo "## HYPOTHESES.md update prompt"
  echo
  echo "Per ADR 0003 §D-4 audit-anchor discipline, append an entry to"
  echo "\`evals/HYPOTHESES.md\`'s amendments-log section referencing:"
  echo
  echo "- Run: \`$RUN_DIR\`"
  echo "- Report: \`$REPORT_PATH\`"
  echo "- Verdict: **$VERDICT**"
  echo
  echo "Then commit the update — that locks the pilot answer."
} > "$REPORT_PATH"

echo "WROTE $REPORT_PATH"
