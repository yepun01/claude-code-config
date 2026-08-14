#!/usr/bin/env bash
# Paired Cohen's d_z + percentile-bootstrap IC95 for an A/B evals run dir.
#
# Inputs:
#   eval-stats-paired.sh <runs-dir> [--metric <name>]
#
# Output (stdout, single JSON):
#   {
#     "metric": "...",
#     "n_pairs": N,
#     "mean_treatment": M_t, "mean_control": M_c,
#     "mean_diff": M_d, "sd_diff": S_d,
#     "d_z": M_d / S_d,
#     "ic95_low": L, "ic95_high": H,
#     "leakage_warning": (|d_z| > 1.5),
#     "per_condition": {"treatment": {"mean": M_t, "n": N_t},
#                       "control":   {"mean": M_c, "n": N_c}}
#   }
#
# Math (Lakens 2013 §2.2):
#   diff_i = metric[treatment]_i − metric[control]_i  (joined by paired_trial_index)
#   mean_diff = mean(diff)
#   sd_diff   = sample stddev (n-1) of diff
#   d_z       = mean_diff / sd_diff
#
# IC95 via 1000-resample percentile bootstrap on the diffs[] array
# (Efron-Tibshirani 1993). srand(42) for reproducibility — same input → same CI.
#
# Sign convention: H1 (HYPOTHESES.md line 98) expects treatment < control,
# so `mean_diff < 0` and `d_z < 0` indicate the predicted direction.
#
# Reference: ~/.claude/decisions/0007-cc5-pilot-runner.md §D-5

set -euo pipefail

RUNS_DIR=""
METRIC="red_flag_count"

while [ $# -gt 0 ]; do
  case "$1" in
    --metric) METRIC="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [ -z "$RUNS_DIR" ]; then RUNS_DIR="$1"; shift
      else echo "ERROR: unexpected arg: $1" >&2; exit 1
      fi
      ;;
  esac
done

if [ -z "$RUNS_DIR" ] || [ ! -d "$RUNS_DIR" ]; then
  echo "ERROR: <runs-dir> required and must exist (got: '$RUNS_DIR')" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required but not in PATH." >&2; exit 1; }

PAIRS_FILE=$(mktemp)
trap 'rm -f "$PAIRS_FILE"' EXIT

# Extract (paired_trial_index, condition, metric_value) per case-*.json.
for f in "$RUNS_DIR"/case-*.json; do
  [ -f "$f" ] || continue
  jq -r --arg m "$METRIC" '
    if (.paired_trial_index != null) and (.condition != null) and (has($m))
    then "\(.paired_trial_index)\t\(.condition)\t\(.[$m])"
    else empty
    end
  ' "$f" >> "$PAIRS_FILE"
done

awk -v R=1000 -v metric="$METRIC" '
function isort(arr, n,    i, j, key) {
  for (i = 2; i <= n; i++) {
    key = arr[i]; j = i - 1
    while (j >= 1 && arr[j] > key) { arr[j+1] = arr[j]; j-- }
    arr[j+1] = key
  }
}

BEGIN { FS = "\t"; srand(42) }

{
  pti = $1; cond = $2; v = $3 + 0
  if (cond == "treatment") { tval[pti] = v; tcnt++ }
  else if (cond == "control") { cval[pti] = v; ccnt++ }
  if (!(pti in seen_pti)) { seen_pti[pti] = 1; pti_list[++np] = pti }
}

END {
  ndiff = 0
  for (i = 1; i <= np; i++) {
    pti = pti_list[i]
    if ((pti in tval) && (pti in cval)) {
      ndiff++
      diffs[ndiff] = tval[pti] - cval[pti]
    }
  }

  if (ndiff < 2) {
    printf "{\n  \"metric\": \"%s\",\n  \"n_pairs\": %d,\n  \"error\": \"insufficient pairs (need ≥2)\"\n}\n", metric, ndiff
    exit 0
  }

  sum_t = 0; nt = 0
  for (k in tval) { sum_t += tval[k]; nt++ }
  sum_c = 0; nc = 0
  for (k in cval) { sum_c += cval[k]; nc++ }
  mean_t = sum_t / nt
  mean_c = sum_c / nc

  sum_d = 0
  for (i = 1; i <= ndiff; i++) sum_d += diffs[i]
  mean_diff = sum_d / ndiff

  ss = 0
  for (i = 1; i <= ndiff; i++) ss += (diffs[i] - mean_diff) * (diffs[i] - mean_diff)
  sd_diff = (ndiff > 1) ? sqrt(ss / (ndiff - 1)) : 0
  d_z = (sd_diff > 0) ? mean_diff / sd_diff : 0

  for (b = 1; b <= R; b++) {
    sum_b = 0
    for (j = 1; j <= ndiff; j++) {
      idx = int(rand() * ndiff) + 1
      bs[j] = diffs[idx]
      sum_b += bs[j]
    }
    mb = sum_b / ndiff
    ssb = 0
    for (j = 1; j <= ndiff; j++) ssb += (bs[j] - mb) * (bs[j] - mb)
    sdb = (ndiff > 1) ? sqrt(ssb / (ndiff - 1)) : 0
    boot_d[b] = (sdb > 0) ? mb / sdb : 0
  }
  isort(boot_d, R)
  lo_idx = int(R * 0.025) + 1
  hi_idx = int(R * 0.975)
  if (lo_idx < 1) lo_idx = 1
  if (hi_idx > R) hi_idx = R
  ic_lo = boot_d[lo_idx]
  ic_hi = boot_d[hi_idx]

  abs_dz = (d_z < 0) ? -d_z : d_z
  leakage = (abs_dz > 1.5) ? "true" : "false"

  printf "{\n"
  printf "  \"metric\": \"%s\",\n", metric
  printf "  \"n_pairs\": %d,\n", ndiff
  printf "  \"mean_treatment\": %.6f,\n", mean_t
  printf "  \"mean_control\": %.6f,\n", mean_c
  printf "  \"mean_diff\": %.6f,\n", mean_diff
  printf "  \"sd_diff\": %.6f,\n", sd_diff
  printf "  \"d_z\": %.6f,\n", d_z
  printf "  \"ic95_low\": %.6f,\n", ic_lo
  printf "  \"ic95_high\": %.6f,\n", ic_hi
  printf "  \"leakage_warning\": %s,\n", leakage
  printf "  \"per_condition\": {\"treatment\": {\"mean\": %.6f, \"n\": %d}, \"control\": {\"mean\": %.6f, \"n\": %d}}\n", mean_t, nt, mean_c, nc
  printf "}\n"
}
' "$PAIRS_FILE"
