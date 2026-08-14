#!/usr/bin/env bash
set -uo pipefail

if [ -z "${QUALITY_GATE_RUNNING:-}" ]; then
    export QUALITY_GATE_RUNNING=1
    if command -v gtimeout &>/dev/null; then
        gtimeout 30 "$0" "$@"; ret=$?
    elif command -v timeout &>/dev/null; then
        timeout 30 "$0" "$@"; ret=$?
    else
        "$0" "$@"; ret=$?
    fi
    [ $ret -eq 124 ] && exit 0
    exit $ret
fi

MODIFIED=$(git diff HEAD --name-only 2>/dev/null || true)
if [ -z "$MODIFIED" ]; then
    exit 0
fi

JS_FILES=()
while IFS= read -r f; do [ -n "$f" ] && JS_FILES+=("$f"); done < <(echo "$MODIFIED" | grep -E '\.[jt]sx?$' || true)
PY_FILES=()
while IFS= read -r f; do [ -n "$f" ] && PY_FILES+=("$f"); done < <(echo "$MODIFIED" | grep '\.py$' || true)
GO_FILES=()
while IFS= read -r f; do [ -n "$f" ] && GO_FILES+=("$f"); done < <(echo "$MODIFIED" | grep '\.go$' || true)

# --- Metrics logging ---
METRICS_LOG=".claude/tmp/metrics.jsonl"
log_metric() {
    mkdir -p .claude/tmp
    echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"hook\":\"$1\",\"status\":\"$2\",\"detail\":\"$3\"}" >> "$METRICS_LOG"
}

# --- Cleanup old .claude/tmp/ files (> 7 days) ---
if [ -d ".claude/tmp" ]; then
    find .claude/tmp -type f -mtime +7 -not -name "metrics.jsonl" -delete 2>/dev/null
fi

ERRORS=""

if [ ${#JS_FILES[@]} -gt 0 ] && command -v npx &>/dev/null; then
    if [ -f "eslint.config.js" ] || [ -f "eslint.config.mjs" ] || [ -f "eslint.config.cjs" ] || [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ] || [ -f ".eslintrc.yml" ]; then
        if ! LINT_OUT=$(npx eslint --no-error-on-unmatched-pattern -- "${JS_FILES[@]}" 2>&1); then
            ERRORS="${ERRORS}\n## Lint errors (eslint)\n${LINT_OUT}\n"
        fi
    fi
fi

if [ ${#PY_FILES[@]} -gt 0 ]; then
    if command -v ruff &>/dev/null; then
        if ! LINT_OUT=$(ruff check -- "${PY_FILES[@]}" 2>&1); then
            ERRORS="${ERRORS}\n## Lint errors (ruff)\n${LINT_OUT}\n"
        fi
    elif command -v flake8 &>/dev/null; then
        if ! LINT_OUT=$(flake8 -- "${PY_FILES[@]}" 2>&1); then
            ERRORS="${ERRORS}\n## Lint errors (flake8)\n${LINT_OUT}\n"
        fi
    fi
fi

if [ ${#GO_FILES[@]} -gt 0 ] && command -v go &>/dev/null; then
    if ! LINT_OUT=$(go vet ./... 2>&1); then
        ERRORS="${ERRORS}\n## Lint errors (go vet)\n${LINT_OUT}\n"
    fi
fi

# --- 2. Secrets scan sur le diff ---
# Lignes ajoutees seulement : une cle correctement SUPPRIMEE reste dans `git diff
# HEAD` jusqu'au commit, rendant la gate insatisfiable (aucune edition ne l'eteint).
DIFF_CONTENT=$(git diff HEAD -U0 2>/dev/null | grep -E "^\+" | grep -v "^+++")
SECRET_SCAN=""

# Pattern 1 : Secrets avec quotes
SCAN1=$(echo "$DIFF_CONTENT" | grep -iE "(password|secret|api[_-]?key|token|private[_-]?key|aws_access|aws_secret)\s*[:=]\s*['\"][^'\"]{8,}" | grep -v test | grep -v example | grep -v mock | grep -v fake | head -5)

# Pattern 2 : Secrets sans quotes (valeur apres = sans espace)
# [[:space:]] et non \s dans le bracket : BSD grep traite \s en bracket comme litteral
# Exclusions code-vs-secret : RHS commencant comme appel/index (getToken(, os.environ[)
# et RHS = chaine d'identifiants pur-alpha a 1-2 points (settings.apiKey,
# config.database.password). Borne {1,2} : 0 point = passphrase mot-nu flaggee,
# 3+ points = passphrase Diceware flaggee (les acces propriete font 2-3 segments).
# FP 2026-07-03 (ColorToken viz) : optional chaining `?.` = lecture de propriete, jamais
# un litteral secret ; `= z.infer<` = derivation de type Zod. Exclusions ciblees.
SCAN2=$(echo "$DIFF_CONTENT" | grep -iE "(password|secret|api[_-]?key|token|private[_-]?key|aws_access|aws_secret)\s*=\s*[^'\"[:space:]]{8,}" | grep -v test | grep -v example | grep -v mock | grep -v fake | grep -v '\$' | grep -v '{' | grep -vE "=\s*[A-Za-z_][A-Za-z0-9_.]*[([]" | grep -vE "=\s*[A-Za-z_]+(\.[A-Za-z_]+){1,2}[;,]?\s*$" | grep -v '?\.' | grep -vE "=\s*z\.infer<" | head -5)

# Pattern 3 : Prefixes connus (independant du nom de variable)
SCAN3=$(echo "$DIFF_CONTENT" | grep -oE "(ghp_[a-zA-Z0-9]{36}|sk-[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16}|-----BEGIN (RSA |EC )?PRIVATE KEY)" | head -5)

SECRET_SCAN="${SCAN1}${SCAN2}${SCAN3}"
if [ -n "$SECRET_SCAN" ]; then
    ERRORS="${ERRORS}\n## SECRETS DETECTES\n${SECRET_SCAN}\n\nSupprime ces secrets avant de continuer.\n"
fi

# --- Resultat ---
if [ -n "$ERRORS" ]; then
    # Never persist matched secret material: the detail line would be the secret itself
    if [ -n "$SECRET_SCAN" ]; then
        log_metric "quality-gate" "FAIL" "secrets detected (content withheld)"
    else
        log_metric "quality-gate" "FAIL" "$(echo "$ERRORS" | head -1 | tr -d '\n')"
    fi
    echo -e "QUALITY GATE FAILED\n${ERRORS}\nCorrige ces problemes avant de continuer."
    exit 2
fi

log_metric "quality-gate" "PASS" ""
exit 0
