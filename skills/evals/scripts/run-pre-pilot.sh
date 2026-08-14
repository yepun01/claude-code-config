#!/usr/bin/env bash
# Pre-flight gates + 3×5 sequential CLI-subprocess spawn loop for /evals run --pre-pilot.
# See ~/.claude/decisions/0006-evals-skill-multifile.md (split from SKILL.md L284-477).
# Pre-flight gates (Gates A, B) MUST be the FIRST commands — before any mkdir / RUN_DIR (T3).

set -euo pipefail

# ---------- Gate A: HYPOTHESES.md non-pre-pilot questions RESOLVED ----------
[ -f evals/HYPOTHESES.md ] || { echo "ERROR: evals/HYPOTHESES.md not found. Run /evals init first." >&2; exit 1; }

awk '
  function check_prev() {
    if (current_q != "" && current_q != "Q2" && current_q != "Q5" && !resolved) {
      print "ERROR: " current_q " is not RESOLVED. Q1, Q3, Q4, Q6 must be RESOLVED before /evals run --pre-pilot per ADR 0003 §D-4. Edit evals/HYPOTHESES.md (fill the RESOLVED: line with your answer)." > "/dev/stderr"
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
  echo "Commit your changes (or git checkout HEAD -- evals/HYPOTHESES.md to discard) before running pre-pilot." >&2
  exit 1
fi

echo "Pre-flight gates passed."

# ---------- Spawn loop (15 sequential trials, per D-2) ----------
ts=$(date -u +%Y%m%dT%H%M%SZ)
RUN_DIR="evals/runs/$ts"
mkdir -p "$RUN_DIR"

AGENT_SHA=$(shasum -a 256 ~/.claude/agents/code-reviewer-control.md | awk '{print $1}')
SKILL_SHA=$(shasum -a 256 ~/.claude/skills/evals/SKILL.md | awk '{print $1}')
CLAUDE_MD_SHA=$([ -f CLAUDE.md ] && shasum -a 256 CLAUDE.md | awk '{print $1}' || echo "")

TRIAL_INDEX=0

for case_id in sast-sql-injection design-dead-code sycophancy-bait; do
  for trial_n in 1 2 3 4 5; do
    TRIAL_INDEX=$((TRIAL_INDEX + 1))

    PROMPT_BODY=$(cat "evals/corpus/$case_id/prompt.md")
    CODE_ABS_PATH="$(pwd)/evals/corpus/$case_id/code/"
    PROMPT_TEXT="$PROMPT_BODY

The code under review is at: $CODE_ABS_PATH

Emit your full review as your assistant response. Use your usual review
format (## Critical / ## Warnings / ## Suggestions sections with bullet
findings). Do NOT modify any file."
    PROMPT_SHA=$(printf '%s' "$PROMPT_TEXT" | shasum -a 256 | awk '{print $1}')

    START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

    OUTPUT_TEXT=$(claude -p \
      --agent code-reviewer-control \
      --dangerously-skip-permissions \
      --max-budget-usd 1.00 \
      --output-format text \
      "$PROMPT_TEXT" </dev/null 2>"$RUN_DIR/case-$case_id-trial-$trial_n.stderr") || true
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
      --arg agent "code-reviewer-control" \
      --arg agent_sha "$AGENT_SHA" \
      --arg prompt_sha "$PROMPT_SHA" \
      --arg prompt "$PROMPT_TEXT" \
      --arg output "$OUTPUT_TEXT" \
      --argjson olen_c "$OUTPUT_LEN_CHARS" \
      --argjson olen_t "$OUTPUT_LEN_TOKENS" \
      --argjson crit "$CRIT" --argjson high "$HIGH" --argjson med "$MED" --argjson low "$LOW" --argjson info "$INFO" \
      --argjson total "$TOTAL" \
      --arg status "$STATUS_VAR" \
      --argjson lat "$LATENCY_MS" \
      --arg cmd_sha "$CLAUDE_MD_SHA" \
      --arg skill_sha "$SKILL_SHA" \
      '{timestamp_iso8601:$ts, case_id:$case, trial_number:$trial, agent_name:$agent, agent_sha256:$agent_sha, prompt_sha256:$prompt_sha, prompt_text:$prompt, output_text:$output, output_length_chars:$olen_c, output_length_tokens:$olen_t, finding_count_by_severity:{critical:$crit,high:$high,medium:$med,low:$low,info:$info}, finding_count_total:$total, exit_status:$status, latency_ms:$lat, claude_md_sha256:$cmd_sha, skill_version_sha256:$skill_sha}' \
      > "$RUN_DIR/case-$case_id-trial-$trial_n.json"

    jq -nc \
      --argjson idx "$TRIAL_INDEX" \
      --arg case "$case_id" \
      --argjson trial "$trial_n" \
      --arg status "$STATUS_VAR" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{trial_index:$idx, case_id:$case, trial_n:$trial, status:$status, timestamp:$ts}' \
      >> "$RUN_DIR/manifest.jsonl"
  done
done

echo "$RUN_DIR"
echo "Suggested next: /evals report --pre-pilot $ts"

