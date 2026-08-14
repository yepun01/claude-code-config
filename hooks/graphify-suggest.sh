#!/usr/bin/env bash
# SessionStart hook (matcher: startup) — evaluate whether the current project
# warrants a Graphify orientation graph (ADR 0019). Suggests `/graphify init`
# on large code-heavy repos without a graph, or `/graphify update` when the
# graph is stale and the freshness git hooks are missing. Silent otherwise.

set -uo pipefail

cat >/dev/null

[ "${GRAPHIFY_SUGGEST_DISABLE:-0}" = "1" ] && exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0

GRAPH="graphify-out/graph.json"

if [ -f "$GRAPH" ]; then
  # Freshness hooks keep the graph current — nothing to say.
  grep -q "graphify-hook-start" "$GIT_DIR/hooks/post-commit" 2>/dev/null && exit 0
  LAST_COMMIT=$(git log -1 --format=%ct 2>/dev/null) || exit 0
  GRAPH_MTIME=$(stat -f %m "$GRAPH" 2>/dev/null) || exit 0
  if [ "$GRAPH_MTIME" -lt "$LAST_COMMIT" ]; then
    echo "## Graphify"
    echo "Graphe d'orientation présent mais périmé (commits plus récents que \`$GRAPH\`) et hooks de fraîcheur absents. \`/graphify update\` pour le rafraîchir (AST local, secondes) — ADR 0019."
  fi
  exit 0
fi

CODE_COUNT=$(git ls-files 2>/dev/null | grep -cE '\.(py|pyi|js|jsx|ts|tsx|go|rs|java|kt|kts|c|h|cc|cpp|hpp|cs|rb|php|swift|m|mm|scala|sql|sh|bash|zsh|lua|zig|ex|exs|erl|tf|vue|svelte|jl|hs|proto)$') || exit 0

if [ "$CODE_COUNT" -ge 200 ]; then
  echo "## Graphify"
  echo "Ce projet compte $CODE_COUNT fichiers de code et n'a pas de graphe d'orientation. \`/graphify init\` pour en générer un (tree-sitter local, sans clé API) — les agents /team s'en serviront pour s'orienter (ADR 0019)."
fi

exit 0
