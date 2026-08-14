#!/usr/bin/env bash
set -uo pipefail

if [ -z "${DETECT_CONTEXT_RUNNING:-}" ]; then
    export DETECT_CONTEXT_RUNNING=1
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

CONTEXT_FILE=".claude/tmp/project-context.md"

# Cache: skip si le fichier existe et a moins de 5 minutes
if [ -f "$CONTEXT_FILE" ]; then
    if [ "$(find "$CONTEXT_FILE" -mmin -5 2>/dev/null)" ]; then
        exit 0
    fi
fi

mkdir -p .claude/tmp 2>/dev/null

STACK="Unknown"
FRAMEWORK=""
PACKAGE_MANAGER=""
TEST_RUNNER=""
LINTER=""
FORMATTER=""

# --- Node.js / TypeScript ---
if [ -f "package.json" ]; then
    STACK="JavaScript"
    [ -f "tsconfig.json" ] && STACK="TypeScript"

    # Framework (dependencies only, not devDependencies)
    if command -v jq &>/dev/null; then
        FRAMEWORK=$(jq -r '[.dependencies // {} | keys[] | select(test("^(react|next|vue|nuxt|angular|svelte|express|hono|fastify|nestjs|remix|astro)$"))] | join(", ")' package.json 2>/dev/null)
    else
        FRAMEWORK=$(cat package.json 2>/dev/null | grep -oE '"(react|next|vue|nuxt|angular|svelte|express|hono|fastify|nestjs|remix|astro)"' | tr -d '"' | sort -u | tr '\n' ', ' | sed 's/,$//')
    fi

    # Package manager
    if [ -f "pnpm-lock.yaml" ]; then PACKAGE_MANAGER="pnpm"
    elif [ -f "yarn.lock" ]; then PACKAGE_MANAGER="yarn"
    elif [ -f "bun.lockb" ]; then PACKAGE_MANAGER="bun"
    else PACKAGE_MANAGER="npm"
    fi

    # Test runner
    if grep -q '"vitest"' package.json 2>/dev/null; then TEST_RUNNER="vitest"
    elif grep -q '"jest"' package.json 2>/dev/null; then TEST_RUNNER="jest"
    elif grep -q '"mocha"' package.json 2>/dev/null; then TEST_RUNNER="mocha"
    fi

    # Linter
    if [ -f "eslint.config.js" ] || [ -f "eslint.config.mjs" ] || [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ] || grep -q '"eslint"' package.json 2>/dev/null; then
        LINTER="eslint"
    fi
    if [ -f "biome.json" ]; then LINTER="biome"; fi

    # Formatter
    if [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ] || [ -f "prettier.config.js" ] || grep -q '"prettier"' package.json 2>/dev/null; then
        FORMATTER="prettier"
    fi
    if [ -f "biome.json" ]; then FORMATTER="biome"; fi
fi

# --- Python ---
if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    [ "$STACK" = "Unknown" ] && STACK="Python"

    # Framework
    PY_FW=""
    for f in requirements.txt pyproject.toml setup.py; do
        if [ -f "$f" ]; then
            grep -qi "fastapi" "$f" 2>/dev/null && PY_FW="${PY_FW:+$PY_FW, }FastAPI"
            grep -qi "django" "$f" 2>/dev/null && PY_FW="${PY_FW:+$PY_FW, }Django"
            grep -qi "flask" "$f" 2>/dev/null && PY_FW="${PY_FW:+$PY_FW, }Flask"
        fi
    done
    [ -n "$PY_FW" ] && FRAMEWORK="$PY_FW"

    # Package manager
    if [ -f "poetry.lock" ]; then PACKAGE_MANAGER="poetry"
    elif [ -f "Pipfile.lock" ]; then PACKAGE_MANAGER="pipenv"
    elif [ -f "uv.lock" ]; then PACKAGE_MANAGER="uv"
    else PACKAGE_MANAGER="pip"
    fi

    [ -z "$TEST_RUNNER" ] && TEST_RUNNER="pytest"
    [ -z "$LINTER" ] && { command -v ruff &>/dev/null && LINTER="ruff" || LINTER="flake8"; }
    [ -z "$FORMATTER" ] && { command -v ruff &>/dev/null && FORMATTER="ruff format" || FORMATTER="black"; }
fi

# --- Go ---
if [ -f "go.mod" ]; then
    [ "$STACK" = "Unknown" ] && STACK="Go"
    FRAMEWORK=$(head -1 go.mod 2>/dev/null | awk '{print $2}')
    [ -z "$PACKAGE_MANAGER" ] && PACKAGE_MANAGER="go mod"
    [ -z "$TEST_RUNNER" ] && TEST_RUNNER="go test"
    [ -z "$LINTER" ] && LINTER="go vet"
    [ -z "$FORMATTER" ] && FORMATTER="gofmt"
fi

# --- Rust ---
if [ -f "Cargo.toml" ]; then
    [ "$STACK" = "Unknown" ] && STACK="Rust"
    FRAMEWORK=$(grep '^name' Cargo.toml 2>/dev/null | head -1 | cut -d'"' -f2)
    [ -z "$PACKAGE_MANAGER" ] && PACKAGE_MANAGER="cargo"
    [ -z "$TEST_RUNNER" ] && TEST_RUNNER="cargo test"
    [ -z "$LINTER" ] && LINTER="clippy"
    [ -z "$FORMATTER" ] && FORMATTER="rustfmt"
fi

# --- Ruby ---
if [ -f "Gemfile" ]; then
    [ "$STACK" = "Unknown" ] && STACK="Ruby"
    grep -q "rails" Gemfile 2>/dev/null && FRAMEWORK="${FRAMEWORK:+$FRAMEWORK, }Rails"
    [ -z "$PACKAGE_MANAGER" ] && PACKAGE_MANAGER="bundler"
    [ -z "$TEST_RUNNER" ] && TEST_RUNNER="rspec"
fi

# --- Java / Kotlin ---
if [ -f "pom.xml" ]; then
    [ "$STACK" = "Unknown" ] && STACK="Java"
    [ -z "$PACKAGE_MANAGER" ] && PACKAGE_MANAGER="Maven"
    [ -z "$TEST_RUNNER" ] && TEST_RUNNER="mvn test"
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    [ "$STACK" = "Unknown" ] && STACK="Java/Kotlin"
    [ -z "$PACKAGE_MANAGER" ] && PACKAGE_MANAGER="Gradle"
    [ -z "$TEST_RUNNER" ] && TEST_RUNNER="gradle test"
fi

# --- Luau / Roblox ---
if [ -f "default.project.json" ] || [ -f "wally.toml" ]; then
    [ "$STACK" = "Unknown" ] && STACK="Luau"
    FRAMEWORK=$(grep -o '"name":\s*"[^"]*"' default.project.json 2>/dev/null | head -1 | cut -d'"' -f4)
    [ -f "wally.toml" ] && PACKAGE_MANAGER="wally" || PACKAGE_MANAGER="none"
    [ -z "$TEST_RUNNER" ] && TEST_RUNNER="lune test"
    [ -z "$LINTER" ] && LINTER="selene"
    [ -z "$FORMATTER" ] && FORMATTER="stylua"
elif find . -maxdepth 2 \( -name "*.luau" -o -name "*.lua" \) 2>/dev/null | grep -q .; then
    [ "$STACK" = "Unknown" ] && STACK="Luau"
    [ -z "$LINTER" ] && LINTER="selene"
    [ -z "$FORMATTER" ] && FORMATTER="stylua"
fi

# --- Monorepo detection ---
MONOREPO="false"
SUB_PROJECTS=""
if [ -f "package.json" ] && command -v jq &>/dev/null && jq -e '.workspaces' package.json &>/dev/null; then
    MONOREPO="true"
    SUB_PROJECTS=$(jq -r '.workspaces[]' package.json 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//')
elif [ -f "pnpm-workspace.yaml" ]; then
    MONOREPO="true"
    SUB_PROJECTS=$(grep -E '^\s*-\s+' pnpm-workspace.yaml 2>/dev/null | sed 's/^\s*-\s*//' | head -5 | tr '\n' ', ' | sed 's/,$//')
elif [ -f "lerna.json" ] || [ -f "nx.json" ]; then
    MONOREPO="true"
fi

# --- Write context file ---
cat > "$CONTEXT_FILE" << EOF
## Project Context (auto-detected)
- **Stack**: $STACK
- **Framework**: ${FRAMEWORK:-none detected}
- **Package Manager**: ${PACKAGE_MANAGER:-unknown}
- **Test Runner**: ${TEST_RUNNER:-unknown}
- **Linter**: ${LINTER:-none detected}
- **Formatter**: ${FORMATTER:-none detected}
- **Monorepo**: $MONOREPO
- **Sub-projects**: ${SUB_PROJECTS:-none}
EOF

exit 0
