#!/usr/bin/env bash
# Pre-flight gates A/B/C/D + (case × trial × condition) sequential CLI-subprocess
# spawn loop for /evals run --pilot.
#
# See ~/.claude/decisions/0007-cc5-pilot-runner.md (sub-decisions D-1..D-8).
# Per ADR D-1: gates A/B duplicated from run-pre-pilot.sh — rule of three not yet
# triggered (only 2 callers). Extraction to scripts/lib/pre-flight.sh deferred to
# the 3rd run-mode (e.g. CC-4 pilot) per ADR 0006 Pre-mortem-C.
#
# Default cardinality (HYPOTHESES.md line 106): 13 cases × 2 trials × 2 conditions.

set -euo pipefail

N_CASES=13
N_TRIALS=2
DRY_RUN=0
CASE_FILTER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --n-cases)  N_CASES="$2"; shift 2 ;;
    --n-trials) N_TRIALS="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --case-id)  CASE_FILTER="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ---------- Gate A: HYPOTHESES.md ALL Q1-Q6 RESOLVED (no Q2/Q5 exemption) ----------
[ -f evals/HYPOTHESES.md ] || { echo "ERROR: evals/HYPOTHESES.md not found. Run /evals init first." >&2; exit 1; }

awk '
  function check_prev() {
    if (current_q != "" && !resolved) {
      print "ERROR: " current_q " is not RESOLVED. All of Q1-Q6 must be RESOLVED before /evals run --pilot per ADR 0003 §D-4 (no Q2/Q5 pre-pilot exemption). Edit evals/HYPOTHESES.md (fill the RESOLVED: line with your answer)." > "/dev/stderr"
      bad = 1
    }
  }
  /^### Q[1-6]/ {
    check_prev(); current_q = $2; resolved = 0
    if ($0 ~ /— RESOLVED:/) { t = $0; sub(/.*— RESOLVED:[ \t]*/, "", t); if (t != "" && t != "..." && t !~ /^<.*>$/) resolved = 1 }
    next
  }
  /^\[X\] RESOLVED/ { resolved = 1; next }
  /^\[ \] RESOLVED/ {
    text = $0
    sub(/^\[ \] RESOLVED:[ \t]*/, "", text)
    if (text != "" && text != "..." && text !~ /^<.*>$/ && text !~ /^sigma-?ratio observed = X/ && text !~ /^sigma on finding_count = X/) {
      resolved = 1
    }
    next
  }
  END { check_prev(); exit bad }
' evals/HYPOTHESES.md

# ---------- Gate B: HYPOTHESES.md committed AND working tree matches HEAD ----------
if ! git log --diff-filter=A -- evals/HYPOTHESES.md 2>/dev/null | grep -q .; then
  echo "ERROR: evals/HYPOTHESES.md is not committed to git." >&2
  echo "Pre-registration discipline (ADR 0003 §D-4) requires the file to predate any evals/runs/* artifact." >&2
  echo "Run: git add evals/HYPOTHESES.md && git commit -m 'pre-register evals hypotheses'" >&2
  exit 1
fi

if ! git diff --quiet HEAD -- evals/HYPOTHESES.md 2>/dev/null; then
  echo "ERROR: working tree differs from committed evals/HYPOTHESES.md." >&2
  echo "Pre-registration audit anchor is the committed version; uncommitted edits would silently amend hypotheses post-hoc (ADR 0003 §D-4 / Nosek 2018)." >&2
  echo "Commit your changes (or git checkout HEAD -- evals/HYPOTHESES.md to discard) before running pilot." >&2
  exit 1
fi

# ---------- Gate C: corpus has ≥ N_CASES dirs ----------
CORPUS_DIRS=()
while IFS= read -r d; do CORPUS_DIRS+=("$d"); done < <(ls -d evals/corpus/*/ 2>/dev/null | sort)
CORPUS_COUNT=${#CORPUS_DIRS[@]}
if [ -n "$CASE_FILTER" ]; then
  if [ ! -d "evals/corpus/$CASE_FILTER" ]; then
    echo "ERROR: --case-id $CASE_FILTER not found under evals/corpus/" >&2
    exit 1
  fi
elif [ "$CORPUS_COUNT" -lt "$N_CASES" ]; then
  echo "ERROR: corpus has $CORPUS_COUNT cases, --n-cases $N_CASES requested." >&2
  echo "Either expand evals/corpus/ to ≥$N_CASES cases (per ADR 0003 §D-1 hybrid composition: 8-10 synthetic + 3-5 OWASP + 2 real diffs)" >&2
  echo "OR explicitly override with --n-cases $CORPUS_COUNT (smoke test only — NOT a valid CC-5 pilot per HYPOTHESES.md line 106)." >&2
  exit 1
fi

# ---------- Gate D: gen-control-agents.sh --check (autogen drift) ----------
if ! ~/.claude/scripts/gen-control-agents.sh --check >&2; then
  echo "ERROR: gen-control-agents.sh --check reports DRIFT in *-control.md." >&2
  echo "Run: ~/.claude/scripts/gen-control-agents.sh    (regenerate without --check)" >&2
  echo "Then commit the regenerated files." >&2
  echo "The pilot cannot run with stale controls — the A/B comparison would not isolate" >&2
  echo "the CC blocks (per ADR 0003 §D-3 *Refutable by:* clause line 109)." >&2
  exit 1
fi

echo "Pre-flight gates passed."

# ---------- Setup: timestamps, run dir, captured-once SHAs ----------
ts=$(date -u +%Y%m%dT%H%M%SZ)
RUN_DIR="evals/runs/${ts}-pilot"

if [ "$DRY_RUN" = "0" ]; then
  mkdir -p "$RUN_DIR"
fi

AGENT_SHA_TREATMENT=$(shasum -a 256 ~/.claude/agents/code-reviewer.md | awk '{print $1}')
AGENT_SHA_CONTROL=$(shasum -a 256 ~/.claude/agents/code-reviewer-control.md | awk '{print $1}')
SKILL_SHA=$(shasum -a 256 ~/.claude/skills/evals/SKILL.md | awk '{print $1}')
CLAUDE_MD_SHA=$([ -f CLAUDE.md ] && shasum -a 256 CLAUDE.md | awk '{print $1}' || echo "")

# Build case list — alphabetical sort, take first N_CASES (D-3).
if [ -n "$CASE_FILTER" ]; then
  CASE_LIST=("$CASE_FILTER")
else
  CASE_LIST=()
  i=0
  for d in "${CORPUS_DIRS[@]}"; do
    [ "$i" -ge "$N_CASES" ] && break
    CASE_LIST+=("$(basename "${d%/}")")
    i=$((i + 1))
  done
fi

# 9 red-flag patterns (literal substrings from agents/code-reviewer.md CC-5 table,
# case-insensitive; counted per-occurrence, not per-line).
RED_FLAG_PATTERNS=(
  "LGTM"
  "Looks good to me"
  "Generally well-structured"
  "To be fair"
  "overall design is solid"
  "Could be improved"
  "Consider "
  "still solid"
  "well-structured"
)

count_red_flags() {
  local text="$1"
  local total=0 c
  for pat in "${RED_FLAG_PATTERNS[@]}"; do
    c=$(printf '%s' "$text" | grep -oFi -- "$pat" 2>/dev/null | wc -l | tr -d ' ' || true)
    total=$((total + c))
  done
  printf '%s' "$total"
}

# ---------- Spawn loop: (case × trial × condition) sequential, prompt re-used ----------
PAIRED_INDEX=0
TRIAL_LINE_INDEX=0

for case_id in "${CASE_LIST[@]}"; do
  for trial_n in $(seq 1 "$N_TRIALS"); do
    PAIRED_INDEX=$((PAIRED_INDEX + 1))

    # Compute prompt ONCE per (case, trial) — D-2 prompt-parity invariant.
    PROMPT_BODY=$(cat "evals/corpus/$case_id/prompt.md")
    CODE_ABS_PATH="$(pwd)/evals/corpus/$case_id/code/"
    PROMPT_TEXT="$PROMPT_BODY

The code under review is at: $CODE_ABS_PATH

Emit your full review as your assistant response. Use your usual review
format (## Critical / ## Warnings / ## Suggestions sections with bullet
findings). Do NOT modify any file."
    PROMPT_SHA=$(printf '%s' "$PROMPT_TEXT" | shasum -a 256 | awk '{print $1}')

    for condition in treatment control; do
      if [ "$condition" = "treatment" ]; then
        AGENT_NAME="code-reviewer"
        AGENT_SHA="$AGENT_SHA_TREATMENT"
      else
        AGENT_NAME="code-reviewer-control"
        AGENT_SHA="$AGENT_SHA_CONTROL"
      fi

      if [ "$DRY_RUN" = "1" ]; then
        echo "DRY-RUN $case_id $trial_n $condition"
        continue
      fi

      TRIAL_LINE_INDEX=$((TRIAL_LINE_INDEX + 1))
      START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

      OUTPUT_TEXT=$(claude -p \
        --agent "$AGENT_NAME" \
        --dangerously-skip-permissions \
        --max-budget-usd 1.00 \
        --output-format text \
        "$PROMPT_TEXT" </dev/null 2>"$RUN_DIR/case-$case_id-trial-$trial_n-$condition.stderr") || true
      RC=$?

      if [ "$RC" = "0" ] && [ -n "$OUTPUT_TEXT" ]; then
        STATUS_VAR="DONE"
      else
        STATUS_VAR="BLOCKED"
        OUTPUT_TEXT=""
      fi

      END_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
      LATENCY_MS=$((END_MS - START_MS))

      OUTPUT_LEN_CHARS=$(printf '%s' "$OUTPUT_TEXT" | wc -c | tr -d ' ')
      OUTPUT_LEN_TOKENS=$(printf '%s' "$OUTPUT_TEXT" | wc -w | awk '{printf "%d", $1*1.3}')
      RED_FLAG_COUNT=$(count_red_flags "$OUTPUT_TEXT")

      read -r CRIT HIGH MED LOW INFO <<< "$(printf '%s\n' "$OUTPUT_TEXT" | awk '
        /^## .*[Cc]ritical/  { sec="crit"; next }
        /^## .*[Ww]arning/   { sec="high"; next }
        /^## .*[Ss]uggestion/{ sec="low";  next }
        /^## /               { sec="" }
        /^- / && sec != ""   { c[sec]++ }
        END { printf "%d %d %d %d %d\n", c["crit"]+0, c["high"]+0, 0, c["low"]+0, 0 }
      ')"
      TOTAL=$((CRIT + HIGH + MED + LOW + INFO))

      jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg case "$case_id" \
        --argjson trial "$trial_n" \
        --arg agent "$AGENT_NAME" \
        --arg agent_sha "$AGENT_SHA" \
        --arg prompt_sha "$PROMPT_SHA" \
        --arg prompt "$PROMPT_TEXT" \
        --arg output "$OUTPUT_TEXT" \
        --argjson olen_c "$OUTPUT_LEN_CHARS" \
        --argjson olen_t "$OUTPUT_LEN_TOKENS" \
        --argjson crit "$CRIT" --argjson high "$HIGH" --argjson med "$MED" --argjson low "$LOW" --argjson info "$INFO" \
        --argjson total "$TOTAL" \
        --argjson rfc "$RED_FLAG_COUNT" \
        --arg condition "$condition" \
        --argjson paired_idx "$PAIRED_INDEX" \
        --arg status "$STATUS_VAR" \
        --argjson lat "$LATENCY_MS" \
        --arg cmd_sha "$CLAUDE_MD_SHA" \
        --arg skill_sha "$SKILL_SHA" \
        '{timestamp_iso8601:$ts, case_id:$case, trial_number:$trial, agent_name:$agent, agent_sha256:$agent_sha, prompt_sha256:$prompt_sha, prompt_text:$prompt, output_text:$output, output_length_chars:$olen_c, output_length_tokens:$olen_t, finding_count_by_severity:{critical:$crit,high:$high,medium:$med,low:$low,info:$info}, finding_count_total:$total, red_flag_count:$rfc, condition:$condition, paired_trial_index:$paired_idx, exit_status:$status, latency_ms:$lat, claude_md_sha256:$cmd_sha, skill_version_sha256:$skill_sha}' \
        > "$RUN_DIR/case-$case_id-trial-$trial_n-$condition.json"

      jq -nc \
        --argjson idx "$TRIAL_LINE_INDEX" \
        --arg case "$case_id" \
        --argjson trial "$trial_n" \
        --arg condition "$condition" \
        --argjson paired_idx "$PAIRED_INDEX" \
        --arg status "$STATUS_VAR" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{trial_index:$idx, case_id:$case, trial_n:$trial, condition:$condition, paired_trial_index:$paired_idx, status:$status, timestamp:$ts}' \
        >> "$RUN_DIR/manifest.jsonl"
    done

    # D-2 prompt-parity assertion: both jsonl entries for this paired_trial_index
    # must agree on prompt_sha256. Cheap defensive check (the source variable
    # was identical, but bash quoting bugs could leak).
    if [ "$DRY_RUN" = "0" ]; then
      tsha=$(jq -r '.prompt_sha256' "$RUN_DIR/case-$case_id-trial-$trial_n-treatment.json" 2>/dev/null || echo "")
      csha=$(jq -r '.prompt_sha256' "$RUN_DIR/case-$case_id-trial-$trial_n-control.json" 2>/dev/null || echo "")
      if [ -n "$tsha" ] && [ -n "$csha" ] && [ "$tsha" != "$csha" ]; then
        echo "ERROR: prompt_sha256 mismatch at paired_trial_index=$PAIRED_INDEX (treatment=$tsha control=$csha)." >&2
        echo "Per ADR D-2 prompt-parity invariant, the run is invalidated. Aborting." >&2
        exit 1
      fi
    fi
  done
done

if [ "$DRY_RUN" = "1" ]; then
  exit 0
fi

echo "$RUN_DIR"
echo "Suggested next: /evals report --pilot ${ts}-pilot"
