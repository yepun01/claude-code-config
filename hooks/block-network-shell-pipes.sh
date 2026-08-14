#!/usr/bin/env bash
# PreToolUse(Bash) hook : tripwire réseau→shell (ADR 0021 D-3a)
# Bloque l'exécution directe de contenu fetché : `curl … | sh`, `bash <(wget …)`,
# `eval "$(curl …)"`. Tripwire, pas barrière — contournable en 2 étapes (download
# puis exécution), même statut que le deny `bash -c` existant. `sh -c "$(curl …)"`
# est déjà couvert par la denylist settings.json.
# exit 2 = bloque avec feedback au modèle

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

if [ -z "$CMD" ]; then
  exit 0
fi

FETCH='(curl|wget|dig|nslookup)'
SHELLS='(bash|sh|zsh|dash|ksh)'
SHELL_PREFIX='(sudo[[:space:]]+)?(/[[:alnum:]/._-]*/)?(env[[:space:]]+)?'

# Pipe réseau→shell, y compris multi-étages (`curl … | base64 -d | sh`).
# Le gap [^;]* ne franchit pas `;` : deux pipelines séparés ne se combinent pas.
if echo "$CMD" | grep -qE "\b${FETCH}\b[^;]*\|&?[[:space:]]*${SHELL_PREFIX}${SHELLS}([[:space:]]|\$|;|\|)"; then
  echo "BLOCK: pipe réseau→shell (ADR 0021 D-3). Télécharge dans un fichier, inspecte-le, puis exécute — jamais en une passe." >&2
  exit 2
fi

# Process substitution : `bash <(curl …)`, `source <(wget …)`
if echo "$CMD" | grep -qE "\b(sudo[[:space:]]+)?(${SHELLS}|source)[[:space:]]+<\([^)]*\b${FETCH}\b"; then
  echo "BLOCK: exécution shell d'une substitution réseau (ADR 0021 D-3). Télécharge, inspecte, puis exécute." >&2
  exit 2
fi

# Command substitution évaluée : `eval "$(curl …)"`
if echo "$CMD" | grep -qE "\beval\b[^;]*\\\$\([[:space:]]*${FETCH}\b"; then
  echo "BLOCK: eval de contenu réseau (ADR 0021 D-3). Télécharge, inspecte, puis exécute." >&2
  exit 2
fi

exit 0
