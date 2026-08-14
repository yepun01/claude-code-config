#!/usr/bin/env bash
# Idempotent scaffolding for evals/ — see ~/.claude/decisions/0006-evals-skill-multifile.md
# Logic extracted from SKILL.md L35-272. Templates copied from ../templates/ (D-2).

set -euo pipefail

TPL_DIR="$(cd "$(dirname "$0")/.." && pwd)/templates"

mkdir_log() {
  local path="$1"
  if [ -d "$path" ]; then
    echo "NO_OP $path"
  else
    mkdir -p "$path"
    echo "CREATED $path"
  fi
}

copy_once() {
  local src="$1" dst="$2"
  if [ -f "$dst" ]; then
    echo "PRESERVED $dst"
  else
    cp "$src" "$dst"
    echo "CREATED $dst"
  fi
}

mkdir_log evals
mkdir_log evals/corpus
mkdir_log evals/runs
mkdir_log evals/reports
mkdir_log evals/corpus/sast-sql-injection
mkdir_log evals/corpus/sast-sql-injection/code
mkdir_log evals/corpus/design-dead-code
mkdir_log evals/corpus/design-dead-code/code
mkdir_log evals/corpus/sycophancy-bait
mkdir_log evals/corpus/sycophancy-bait/code
mkdir_log evals/corpus/sast-command-injection
mkdir_log evals/corpus/sast-command-injection/code
mkdir_log evals/corpus/llm-blind-xss
mkdir_log evals/corpus/llm-blind-xss/code
mkdir_log evals/corpus/llm-blind-path-traversal
mkdir_log evals/corpus/llm-blind-path-traversal/code
mkdir_log evals/corpus/llm-blind-race-condition
mkdir_log evals/corpus/llm-blind-race-condition/code
mkdir_log evals/corpus/llm-blind-respectful-bait
mkdir_log evals/corpus/llm-blind-respectful-bait/code
mkdir_log evals/corpus/owasp-sqli
mkdir_log evals/corpus/owasp-sqli/code
mkdir_log evals/corpus/owasp-cmdi
mkdir_log evals/corpus/owasp-cmdi/code
mkdir_log evals/corpus/owasp-xss
mkdir_log evals/corpus/owasp-xss/code
mkdir_log evals/corpus/real-diff-d43e921
mkdir_log evals/corpus/real-diff-d43e921/code
mkdir_log evals/corpus/real-diff-b0be387
mkdir_log evals/corpus/real-diff-b0be387/code

copy_once "$TPL_DIR/HYPOTHESES.md.tmpl" evals/HYPOTHESES.md
copy_once "$TPL_DIR/RUBRIC.md.tmpl" evals/RUBRIC.md

copy_once "$TPL_DIR/corpus/sast-sql-injection/prompt.md" evals/corpus/sast-sql-injection/prompt.md
copy_once "$TPL_DIR/corpus/sast-sql-injection/code/lookup.py" evals/corpus/sast-sql-injection/code/lookup.py
copy_once "$TPL_DIR/corpus/sast-sql-injection/ground_truth.jsonl" evals/corpus/sast-sql-injection/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/sast-sql-injection/meta.json" evals/corpus/sast-sql-injection/meta.json

copy_once "$TPL_DIR/corpus/design-dead-code/prompt.md" evals/corpus/design-dead-code/prompt.md
copy_once "$TPL_DIR/corpus/design-dead-code/code/cart.ts" evals/corpus/design-dead-code/code/cart.ts
copy_once "$TPL_DIR/corpus/design-dead-code/ground_truth.jsonl" evals/corpus/design-dead-code/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/design-dead-code/meta.json" evals/corpus/design-dead-code/meta.json

copy_once "$TPL_DIR/corpus/sycophancy-bait/prompt.md" evals/corpus/sycophancy-bait/prompt.md
copy_once "$TPL_DIR/corpus/sycophancy-bait/code/auth.js" evals/corpus/sycophancy-bait/code/auth.js
copy_once "$TPL_DIR/corpus/sycophancy-bait/ground_truth.jsonl" evals/corpus/sycophancy-bait/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/sycophancy-bait/meta.json" evals/corpus/sycophancy-bait/meta.json

copy_once "$TPL_DIR/corpus/sast-command-injection/prompt.md" evals/corpus/sast-command-injection/prompt.md
copy_once "$TPL_DIR/corpus/sast-command-injection/code/cmd_runner.py" evals/corpus/sast-command-injection/code/cmd_runner.py
copy_once "$TPL_DIR/corpus/sast-command-injection/ground_truth.jsonl" evals/corpus/sast-command-injection/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/sast-command-injection/meta.json" evals/corpus/sast-command-injection/meta.json

copy_once "$TPL_DIR/corpus/llm-blind-xss/prompt.md" evals/corpus/llm-blind-xss/prompt.md
copy_once "$TPL_DIR/corpus/llm-blind-xss/code/dom_render.ts" evals/corpus/llm-blind-xss/code/dom_render.ts
copy_once "$TPL_DIR/corpus/llm-blind-xss/ground_truth.jsonl" evals/corpus/llm-blind-xss/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/llm-blind-xss/meta.json" evals/corpus/llm-blind-xss/meta.json

copy_once "$TPL_DIR/corpus/llm-blind-path-traversal/prompt.md" evals/corpus/llm-blind-path-traversal/prompt.md
copy_once "$TPL_DIR/corpus/llm-blind-path-traversal/code/report_loader.py" evals/corpus/llm-blind-path-traversal/code/report_loader.py
copy_once "$TPL_DIR/corpus/llm-blind-path-traversal/ground_truth.jsonl" evals/corpus/llm-blind-path-traversal/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/llm-blind-path-traversal/meta.json" evals/corpus/llm-blind-path-traversal/meta.json

copy_once "$TPL_DIR/corpus/llm-blind-race-condition/prompt.md" evals/corpus/llm-blind-race-condition/prompt.md
copy_once "$TPL_DIR/corpus/llm-blind-race-condition/code/session_cache.py" evals/corpus/llm-blind-race-condition/code/session_cache.py
copy_once "$TPL_DIR/corpus/llm-blind-race-condition/ground_truth.jsonl" evals/corpus/llm-blind-race-condition/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/llm-blind-race-condition/meta.json" evals/corpus/llm-blind-race-condition/meta.json

copy_once "$TPL_DIR/corpus/llm-blind-respectful-bait/prompt.md" evals/corpus/llm-blind-respectful-bait/prompt.md
copy_once "$TPL_DIR/corpus/llm-blind-respectful-bait/code/session_helper.js" evals/corpus/llm-blind-respectful-bait/code/session_helper.js
copy_once "$TPL_DIR/corpus/llm-blind-respectful-bait/ground_truth.jsonl" evals/corpus/llm-blind-respectful-bait/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/llm-blind-respectful-bait/meta.json" evals/corpus/llm-blind-respectful-bait/meta.json

copy_once "$TPL_DIR/corpus/owasp-sqli/prompt.md" evals/corpus/owasp-sqli/prompt.md
copy_once "$TPL_DIR/corpus/owasp-sqli/code/BenchmarkTest00008.java" evals/corpus/owasp-sqli/code/BenchmarkTest00008.java
copy_once "$TPL_DIR/corpus/owasp-sqli/ground_truth.jsonl" evals/corpus/owasp-sqli/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/owasp-sqli/meta.json" evals/corpus/owasp-sqli/meta.json

copy_once "$TPL_DIR/corpus/owasp-cmdi/prompt.md" evals/corpus/owasp-cmdi/prompt.md
copy_once "$TPL_DIR/corpus/owasp-cmdi/code/BenchmarkTest00006.java" evals/corpus/owasp-cmdi/code/BenchmarkTest00006.java
copy_once "$TPL_DIR/corpus/owasp-cmdi/ground_truth.jsonl" evals/corpus/owasp-cmdi/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/owasp-cmdi/meta.json" evals/corpus/owasp-cmdi/meta.json

copy_once "$TPL_DIR/corpus/owasp-xss/prompt.md" evals/corpus/owasp-xss/prompt.md
copy_once "$TPL_DIR/corpus/owasp-xss/code/BenchmarkTest00013.java" evals/corpus/owasp-xss/code/BenchmarkTest00013.java
copy_once "$TPL_DIR/corpus/owasp-xss/ground_truth.jsonl" evals/corpus/owasp-xss/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/owasp-xss/meta.json" evals/corpus/owasp-xss/meta.json

copy_once "$TPL_DIR/corpus/real-diff-d43e921/prompt.md" evals/corpus/real-diff-d43e921/prompt.md
copy_once "$TPL_DIR/corpus/real-diff-d43e921/code/measure_panes.sh" evals/corpus/real-diff-d43e921/code/measure_panes.sh
copy_once "$TPL_DIR/corpus/real-diff-d43e921/ground_truth.jsonl" evals/corpus/real-diff-d43e921/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/real-diff-d43e921/meta.json" evals/corpus/real-diff-d43e921/meta.json

copy_once "$TPL_DIR/corpus/real-diff-b0be387/prompt.md" evals/corpus/real-diff-b0be387/prompt.md
copy_once "$TPL_DIR/corpus/real-diff-b0be387/code/quality_gate_fileset.sh" evals/corpus/real-diff-b0be387/code/quality_gate_fileset.sh
copy_once "$TPL_DIR/corpus/real-diff-b0be387/ground_truth.jsonl" evals/corpus/real-diff-b0be387/ground_truth.jsonl
copy_once "$TPL_DIR/corpus/real-diff-b0be387/meta.json" evals/corpus/real-diff-b0be387/meta.json

echo "init complete"

