#!/usr/bin/env bash
# PreToolUse hook : bloque Edit/Write sur fichiers sensibles
# Lit le payload JSON via stdin (API moderne Claude Code)
# exit 2 = bloque avec feedback au modèle

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")

if [ -z "$FILE" ]; then
  exit 0
fi

# Exemption zone scratch : .claude/tmp/** est éphémère ; la protection secrets
# n'y a pas de sens (cohérent avec block-pollution-files.sh).
case "$FILE" in
  */.claude/tmp/*|.claude/tmp/*) exit 0 ;;
esac

LOWER_PATH=$(echo "$FILE" | tr '[:upper:]' '[:lower:]')

case "$LOWER_PATH" in
  */.kube/config|*/.kube/*.yaml|*/.kube/*.yml|.kube/*)
    echo "BLOCK: kubeconfig ($FILE)." >&2; exit 2 ;;
  */.gnupg/*|*/.aws/credentials|*/.aws/config|.gnupg/*|.aws/credentials|.aws/config)
    echo "BLOCK: secret dir ($FILE)." >&2; exit 2 ;;
  */.cargo/credentials*|*/.docker/config.json|.cargo/credentials*|.docker/config.json)
    echo "BLOCK: credential store ($FILE)." >&2; exit 2 ;;
  *cookies.sqlite|*key4.db|*logins.json|*msal_token_cache.json|*/hosts.yml)
    echo "BLOCK: browser/cloud credential ($FILE)." >&2; exit 2 ;;
esac

BASENAME=$(basename "$FILE")
LOWER=$(echo "$BASENAME" | tr '[:upper:]' '[:lower:]')

case "$LOWER" in
  .env|.env.*|.envrc|.flaskenv|secrets.env)
    echo "BLOCK: fichier .env protégé ($BASENAME). Utilise des variables d'environnement." >&2
    exit 2 ;;
  *.pem|*.key|*.p12|*.pfx|*.keystore|*.jks|id_rsa|id_ed25519|id_ecdsa|*credentials*)
    echo "BLOCK: secret/keystore ($BASENAME)." >&2
    exit 2 ;;
  *.gpg|*.asc|secring.gpg|pubring.gpg)
    echo "BLOCK: GPG key ($BASENAME)." >&2
    exit 2 ;;
  .netrc|_netrc|.pgpass|.my.cnf)
    echo "BLOCK: auth config ($BASENAME)." >&2
    exit 2 ;;
  authorized_keys|known_hosts)
    echo "BLOCK: SSH host file ($BASENAME)." >&2
    exit 2 ;;
  package-lock.json|yarn.lock|pnpm-lock.yaml|cargo.lock|poetry.lock|uv.lock|bun.lockb|gemfile.lock|composer.lock|go.sum)
    echo "BLOCK: lock file ($BASENAME). Utilise le package manager." >&2
    exit 2 ;;
esac

exit 0
