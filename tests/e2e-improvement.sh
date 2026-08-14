#!/usr/bin/env bash
# E2E test for the auto-improvement pipeline (ADR 0013).
# Validates hooks/improvement-monitor.sh side-effects (PENDING + osascript)
# on synthetic fixtures, with CHANGELOG_URL overridable to a file:// URL so
# the suite runs offline. Stack: bash only, no framework.
#
# Runtime target: <30s for 4 cases.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/improvement-monitor.sh"

if [ ! -x "$HOOK" ]; then
    echo "FATAL: hook not executable at $HOOK" >&2
    exit 2
fi

TMPDIR=$(mktemp -d -t e2e-improvement.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0
FAILURES=()

# Each case runs in a fresh sub-environment to avoid cross-contamination.
setup_env() {
    local case_dir="$1"
    rm -rf "$case_dir"
    mkdir -p "$case_dir/.claude/state" "$case_dir/.claude/cache" "$case_dir/bin"

    # Stub osascript: log invocations so tests can assert on them.
    cat > "$case_dir/bin/osascript" <<EOF
#!/usr/bin/env bash
echo "OSASCRIPT_CALLED: \$*" >> "$case_dir/osascript.log"
exit 0
EOF
    chmod +x "$case_dir/bin/osascript"

    # Stub claude: only --version is exercised by the hook's stdout path.
    cat > "$case_dir/bin/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
    echo "2.0.0 (Claude Code stub)"
    exit 0
fi
exit 0
EOF
    chmod +x "$case_dir/bin/claude"
}

assert() {
    local label="$1"
    local condition="$2"
    if eval "$condition"; then
        return 0
    else
        FAILURES+=("$label: assertion failed: $condition")
        return 1
    fi
}

run_case() {
    local name="$1"
    local case_dir="$TMPDIR/$name"
    setup_env "$case_dir"
    # Returns 0 on pass, 1 on fail.
    if "case_$name" "$case_dir"; then
        PASS=$((PASS + 1))
        echo "  PASS: $name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $name"
    fi
}

# Case 1: monitoring fixture with one [high] entry → PENDING written + osascript called.
case_test_high_present() {
    local d="$1"
    cat > "$d/.claude/state/MONITORING-2026-05.md" <<'EOF'
Since: 2.0.0
Current: 2.1.143
Fetched: 2026-05-19

## Actionable
- v2.1.143 — worktree.bgIsolation parallel agent runs — already in plugin? no
- v2.1.140 — statusline tokens API — already in plugin? partial

## Watch
- v2.1.139 — minor hook tweak — already in plugin? partial
EOF

    HOME="$d" PATH="$d/bin:$PATH" "$HOOK" --write-pending >/dev/null 2>&1

    local pending="$d/.claude/state/PENDING-IMPROVEMENT.md"
    assert "$FUNCNAME pending exists" "[ -f '$pending' ]" || return 1
    assert "$FUNCNAME osascript called" "[ -f '$d/osascript.log' ]" || return 1
    assert "$FUNCNAME osascript mentions improvement" "grep -q 'Improvement' '$d/osascript.log'" || return 1
    assert "$FUNCNAME pending mentions top item" "grep -q 'v2.1.143' '$pending'" || return 1
    return 0
}

# Case 2: monitoring fixture with no [high] → PENDING absent, osascript not called.
case_test_no_high() {
    local d="$1"
    cat > "$d/.claude/state/MONITORING-2026-05.md" <<'EOF'
Since: 2.0.0
Current: 2.1.143
Fetched: 2026-05-19

## Watch
- v2.1.139 — minor hook tweak — already in plugin? partial

_No actionable deltas this period._
EOF

    HOME="$d" PATH="$d/bin:$PATH" "$HOOK" --write-pending >/dev/null 2>&1

    local pending="$d/.claude/state/PENDING-IMPROVEMENT.md"
    assert "$FUNCNAME pending absent" "[ ! -f '$pending' ]" || return 1
    assert "$FUNCNAME osascript not called" "[ ! -f '$d/osascript.log' ]" || return 1
    return 0
}

# Case 3: PENDING file format matches the ADR 0013 §4 spec.
case_test_pending_format() {
    local d="$1"
    cat > "$d/.claude/state/MONITORING-2026-05.md" <<'EOF'
Since: 2.0.0
Current: 2.1.143
Fetched: 2026-05-19

## Actionable
- v2.1.143 — worktree.bgIsolation parallel agent runs — already in plugin? no
EOF

    HOME="$d" PATH="$d/bin:$PATH" "$HOOK" --write-pending >/dev/null 2>&1

    local pending="$d/.claude/state/PENDING-IMPROVEMENT.md"
    assert "$FUNCNAME pending exists" "[ -f '$pending' ]" || return 1
    assert "$FUNCNAME Item line" "grep -q '^Item:' '$pending'" || return 1
    assert "$FUNCNAME Generated line" "grep -q '^Generated:' '$pending'" || return 1
    # [ENGINEERING] regex ^Source: .* line [0-9]+$ — asserts numeric line reference
    assert "$FUNCNAME Source line" "grep -qE '^Source: .* line [0-9]+\$' '$pending'" || return 1
    return 0
}

# Case 4: CHANGELOG_URL pointing at a nonexistent file → hook fails with non-zero exit.
case_test_changelog_url_override() {
    local d="$1"
    CHANGELOG_URL="file://$d/does-not-exist.md" HOME="$d" PATH="$d/bin:$PATH" \
        "$HOOK" >/dev/null 2>"$d/stderr.log"
    local rc=$?

    assert "$FUNCNAME non-zero exit" "[ $rc -ne 0 ]" || return 1
    assert "$FUNCNAME stderr mentions fetch failure" "grep -qi 'fetch' '$d/stderr.log'" || return 1
    return 0
}

# Case 5: markdown-bold format `- **X.Y.Z** — …` (LLM-rendered, real artifact).
# Regression guard against the format mismatch between the skill spec
# (`- v<semver>`) and what the LLM actually writes when /improvement-monitor
# runs. See ADR 0013 amendment.
case_test_markdown_bold_format() {
    local d="$1"
    cat > "$d/.claude/state/MONITORING-2026-05.md" <<'EOF'
Since: 2.0.0
Current: 2.1.143
Fetched: 2026-05-19

## Actionable
- **2.1.121** — PostToolUse hooks replace output for all tools — already in plugin: no
- **2.1.139/141** — Hook args string array exec form — already in plugin: no
EOF

    HOME="$d" PATH="$d/bin:$PATH" "$HOOK" --write-pending >/dev/null 2>&1

    local pending="$d/.claude/state/PENDING-IMPROVEMENT.md"
    assert "$FUNCNAME pending exists" "[ -f '$pending' ]" || return 1
    assert "$FUNCNAME pending mentions top item" "grep -q '2.1.121' '$pending'" || return 1
    assert "$FUNCNAME osascript called" "[ -f '$d/osascript.log' ]" || return 1
    return 0
}

# Case 6: H2 section settled by a `_Disposition` footnote + live H3 addendum
# (real artifact shape: MONITORING-2026-06.md) → top-1 comes from the H3
# section, never from the disposed H2.
case_test_h3_addendum_parsed() {
    local d="$1"
    cat > "$d/.claude/state/MONITORING-2026-05.md" <<'EOF'
Since: 2.0.0
Current: 2.1.158
Fetched: 2026-05-31

## Actionable
- 2.1.154 — Dynamic workflows orchestration — already in plugin? no ← top 1

## Watch
- 2.1.153 — statusline COLUMNS/LINES — statusline custom

_Disposition ([ADR 0015](../decisions/0015.md)) : workflows→[ADR 0014]._

---

## Addendum 2026-06-04 — delta

### Actionable (nouveau cycle)
- 2.1.163 — fresh actionable feature — already in plugin? no ← top 1

### Watch
- 2.1.163 — neutral platform change
EOF

    HOME="$d" PATH="$d/bin:$PATH" "$HOOK" --write-pending >/dev/null 2>&1

    local pending="$d/.claude/state/PENDING-IMPROVEMENT.md"
    assert "$FUNCNAME pending exists" "[ -f '$pending' ]" || return 1
    assert "$FUNCNAME top item from H3 addendum" "grep -q '2.1.163' '$pending'" || return 1
    assert "$FUNCNAME disposed H2 item excluded" "! grep -q 'Dynamic workflows' '$pending'" || return 1
    return 0
}

# Case 7: every item disposed or `already in plugin? n/a` → explicit
# "no actionable" PENDING written, osascript NOT called.
case_test_all_disposed_no_actionable() {
    local d="$1"
    cat > "$d/.claude/state/MONITORING-2026-05.md" <<'EOF'
Since: 2.0.0
Current: 2.1.158
Fetched: 2026-05-31

## Actionable
- 2.1.154 — Dynamic workflows orchestration — already in plugin? no ← top 1

_Disposition ([ADR 0015](../decisions/0015.md)) : workflows→[ADR 0014]._

### Actionable (nouveau cycle)
- 2.1.161 — Parallel tool calls batch fix — already in plugin? n/a (bugfix gratuit)
- 2.1.162 — Cross-session SendMessage fix — already in plugin? n/a (bugfix gratuit)
EOF

    HOME="$d" PATH="$d/bin:$PATH" "$HOOK" --write-pending >/dev/null 2>&1

    local pending="$d/.claude/state/PENDING-IMPROVEMENT.md"
    assert "$FUNCNAME pending exists" "[ -f '$pending' ]" || return 1
    assert "$FUNCNAME explicit no-actionable message" "grep -q 'actionnable' '$pending'" || return 1
    assert "$FUNCNAME no item leaked as top-1" "! grep -q '^Item:' '$pending'" || return 1
    assert "$FUNCNAME osascript not called" "[ ! -f '$d/osascript.log' ]" || return 1
    return 0
}

# Case 8: live item whose feature keywords match a recent commit subject →
# skipped as already shipped; next live item becomes top-1.
case_test_shipped_item_skipped() {
    local d="$1"
    cat > "$d/.claude/state/MONITORING-2026-05.md" <<'EOF'
Since: 2.0.0
Current: 2.1.160
Fetched: 2026-06-04

## Actionable
- 2.1.160 — write-deny build-tool configs hardening — already in plugin? no ← top 1
- 2.1.163 — fresh actionable feature — already in plugin? no ← top 2
EOF
    git -C "$d/.claude" init -q
    git -C "$d/.claude" -c user.name=t -c user.email=t@t commit -q --allow-empty \
        -m "feat(security): write-deny build-tool configs"

    HOME="$d" PATH="$d/bin:$PATH" "$HOOK" --write-pending >/dev/null 2>&1

    local pending="$d/.claude/state/PENDING-IMPROVEMENT.md"
    assert "$FUNCNAME pending exists" "[ -f '$pending' ]" || return 1
    assert "$FUNCNAME shipped item skipped" "! grep -q '2.1.160' '$pending'" || return 1
    assert "$FUNCNAME next live item picked" "grep -q '2.1.163' '$pending'" || return 1
    return 0
}

echo "Running E2E improvement tests..."
run_case test_high_present
run_case test_no_high
run_case test_pending_format
run_case test_changelog_url_override
run_case test_markdown_bold_format
run_case test_h3_addendum_parsed
run_case test_all_disposed_no_actionable
run_case test_shipped_item_skipped

echo
echo "Result: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "Failures:"
    for f in "${FAILURES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi
exit 0
