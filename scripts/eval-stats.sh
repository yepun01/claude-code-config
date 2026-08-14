#!/usr/bin/env bash
# Compute per-case + inter-case statistics for an evals run directory.
#
# Inputs:
#   eval-stats.sh <runs-dir> [--metric <name>]
#
# Output (stdout, single JSON):
#   {
#     "metric": "...",
#     "n_actual": N, "n_expected": N,
#     "per_case": { "<case_id>": {"mean":, "sigma":, "ratio":, "n":, "ci95_low":, "ci95_high":}, ... },
#     "inter_case": {"mean":, "sigma":, "ratio":, "ci95_low":, "ci95_high":} | null,
#     "overall_mean": M,
#     "verdict_input": "ratio_max=R"
#   }
#
# Stats:
#   sigma = sample stddev (n-1 denominator)
#   ratio = sigma / mean (0 if mean == 0)
#   ci95 = 1000-resample percentile bootstrap on the case's data
#          (Efron-Tibshirani 1993, "An Introduction to the Bootstrap").
#          Inter-case bootstrap resamples the per-case means.
#
# Forward compatibility (ADR design D-3, T4):
#   - Trials missing the requested metric are skipped (logged INFO to stderr).
#   - Trials missing claude_md_sha256 are counted and logged INFO to stderr,
#     but never excluded from stats — schema drift on non-essential fields
#     must NOT crash the report (T4 contract).
#
# Reference: ~/.claude/decisions/000N-evals-skill.md §D-4
#
# Reproducibility: bootstrap uses srand(42) for deterministic CIs across reruns
# on the same input.

set -euo pipefail

RUNS_DIR=""
METRIC="finding_count_total"

while [ $# -gt 0 ]; do
  case "$1" in
    --metric) METRIC="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [ -z "$RUNS_DIR" ]; then
        RUNS_DIR="$1"
        shift
      else
        echo "ERROR: unexpected arg: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$RUNS_DIR" ] || [ ! -d "$RUNS_DIR" ]; then
  echo "ERROR: <runs-dir> required and must exist (got: '$RUNS_DIR')" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found in PATH." >&2; exit 1; }

# Determine n_expected from manifest (if present) — ADR design D-2 crash-recovery anchor.
MANIFEST="$RUNS_DIR/manifest.jsonl"
if [ -f "$MANIFEST" ]; then
  N_EXPECTED=$(wc -l < "$MANIFEST" | tr -d ' ')
else
  N_EXPECTED=0
fi

# Extract (case_id <TAB> value) pairs from each trial json. Skip trials where
# the metric is missing or null. Also count trials missing claude_md_sha256
# (forward-compat probe per T4).
PAIRS_FILE=$(mktemp)
trap 'rm -f "$PAIRS_FILE"' EXIT

MISSING_CLAUDE_MD=0
MISSING_METRIC=0
N_FILES=0

for f in "$RUNS_DIR"/case-*.json; do
  [ -f "$f" ] || continue
  N_FILES=$((N_FILES + 1))

  # Forward-compat probe: claude_md_sha256
  has_cmd=$(jq -r 'if (has("claude_md_sha256") and (.claude_md_sha256 != null) and (.claude_md_sha256 != "")) then "1" else "0" end' "$f")
  if [ "$has_cmd" = "0" ]; then
    MISSING_CLAUDE_MD=$((MISSING_CLAUDE_MD + 1))
  fi

  # Pull (case_id, metric value) — flatten finding_count_by_severity.<sev> if requested.
  case "$METRIC" in
    finding_count_by_severity.*)
      sev=${METRIC#finding_count_by_severity.}
      val=$(jq -r --arg s "$sev" '
        if (.finding_count_by_severity != null) and (.finding_count_by_severity[$s] != null)
        then (.finding_count_by_severity[$s] | tostring)
        else "" end
      ' "$f")
      ;;
    *)
      val=$(jq -r --arg m "$METRIC" '
        if has($m) and (.[$m] != null) then (.[$m] | tostring) else "" end
      ' "$f")
      ;;
  esac

  if [ -z "$val" ]; then
    MISSING_METRIC=$((MISSING_METRIC + 1))
    continue
  fi

  case_id=$(jq -r '.case_id // "unknown"' "$f")
  printf '%s\t%s\n' "$case_id" "$val" >> "$PAIRS_FILE"
done

if [ "$MISSING_CLAUDE_MD" -gt 0 ]; then
  echo "INFO: $MISSING_CLAUDE_MD trial(s) missing claude_md_sha256, treated as null" >&2
fi
if [ "$MISSING_METRIC" -gt 0 ]; then
  echo "INFO: $MISSING_METRIC trial(s) missing metric '$METRIC', excluded from stats" >&2
fi

N_ACTUAL=$(wc -l < "$PAIRS_FILE" | tr -d ' ')

if [ "$N_ACTUAL" -eq 0 ]; then
  jq -n --arg m "$METRIC" --argjson ne "$N_EXPECTED" --argjson nf "$N_FILES" \
    '{metric:$m, n_actual:0, n_expected:$ne, n_files_seen:$nf, per_case:{}, inter_case:null, overall_mean:0, verdict_input:"ratio_max=0"}'
  exit 0
fi

# Single awk pass: per-case stats + bootstrap CI (insertion sort, POSIX-portable).
awk -v R=1000 -v metric="$METRIC" -v n_expected="$N_EXPECTED" -v n_actual="$N_ACTUAL" '
function sample_mean(arr, n,    j, idx, sum) {
  sum = 0
  for (j = 1; j <= n; j++) {
    idx = int(rand() * n) + 1
    sum += arr[idx]
  }
  return sum / n
}
function isort(arr, n,    i, j, key) {
  for (i = 2; i <= n; i++) {
    key = arr[i]
    j = i - 1
    while (j >= 1 && arr[j] > key) {
      arr[j+1] = arr[j]
      j--
    }
    arr[j+1] = key
  }
}
function bootstrap_ci(data, n, lo, hi,    i, means, lo_idx, hi_idx) {
  if (n < 2) {
    lo[1] = data[1]; hi[1] = data[1]
    return
  }
  for (i = 1; i <= R; i++) {
    means[i] = sample_mean(data, n)
  }
  isort(means, R)
  lo_idx = int(R * 0.025) + 1
  hi_idx = int(R * 0.975)
  if (lo_idx < 1) lo_idx = 1
  if (hi_idx > R) hi_idx = R
  lo[1] = means[lo_idx]
  hi[1] = means[hi_idx]
}
function variance_pop(data, n, mean,    i, ss) {
  ss = 0
  for (i = 1; i <= n; i++) ss += (data[i] - mean) * (data[i] - mean)
  return ss
}

BEGIN {
  FS = "\t"
  srand(42)
  ratio_max = 0
  ncases = 0
}

{
  case_id = $1
  v = $2 + 0
  if (!(case_id in case_seen)) {
    case_seen[case_id] = 1
    ncases++
    case_order[ncases] = case_id
  }
  cn = ++count[case_id]
  data[case_id, cn] = v
  all_n++
  all_sum += v
}

END {
  printf "{\n"
  printf "  \"metric\": \"%s\",\n", metric
  printf "  \"n_actual\": %d,\n", n_actual
  printf "  \"n_expected\": %d,\n", n_expected
  printf "  \"per_case\": {"

  first = 1
  cm_n = 0
  for (k = 1; k <= ncases; k++) {
    c = case_order[k]
    n = count[c]
    sum = 0
    for (i = 1; i <= n; i++) {
      arr[i] = data[c, i]
      sum += arr[i]
    }
    mean = sum / n
    if (n > 1) sigma = sqrt(variance_pop(arr, n, mean) / (n - 1))
    else sigma = 0
    ratio = (mean != 0) ? sigma / mean : 0
    if (ratio > ratio_max) ratio_max = ratio

    bootstrap_ci(arr, n, lo, hi)
    ci_lo = lo[1]; ci_hi = hi[1]

    cm_n++
    case_means[cm_n] = mean

    if (!first) printf ","
    printf "\n    \"%s\": {\"mean\": %.6f, \"sigma\": %.6f, \"ratio\": %.6f, \"n\": %d, \"ci95_low\": %.6f, \"ci95_high\": %.6f}", c, mean, sigma, ratio, n, ci_lo, ci_hi
    first = 0
  }
  printf "\n  },\n"

  if (cm_n >= 2) {
    sum = 0
    for (i = 1; i <= cm_n; i++) sum += case_means[i]
    inter_mean = sum / cm_n
    inter_sigma = sqrt(variance_pop(case_means, cm_n, inter_mean) / (cm_n - 1))
    inter_ratio = (inter_mean != 0) ? inter_sigma / inter_mean : 0
    bootstrap_ci(case_means, cm_n, lo, hi)
    printf "  \"inter_case\": {\"mean\": %.6f, \"sigma\": %.6f, \"ratio\": %.6f, \"ci95_low\": %.6f, \"ci95_high\": %.6f},\n", inter_mean, inter_sigma, inter_ratio, lo[1], hi[1]
  } else {
    printf "  \"inter_case\": null,\n"
  }

  overall_mean = (all_n > 0) ? all_sum / all_n : 0
  printf "  \"overall_mean\": %.6f,\n", overall_mean
  printf "  \"verdict_input\": \"ratio_max=%.6f\"\n", ratio_max
  printf "}\n"
}
' "$PAIRS_FILE"
