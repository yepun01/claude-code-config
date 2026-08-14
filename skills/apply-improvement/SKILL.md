---
description: Apply the top pending improvement from state/PENDING-IMPROVEMENT.md on a dedicated weekly branch with explicit human gate and state-machine tracking (ADR 0013).
---

## Goal

Consume `state/PENDING-IMPROVEMENT.md` (written by `/improvement-monitor` + `hooks/improvement-monitor.sh`), confirm with the user, spawn `/team` in subprocess on a fresh branch, capture the verdict, and notify. **Nothing merges to `main` without manual `git merge`.**

## State machine (file markers)

Each invocation writes one terminal marker to `state/applying/`:

| Suffix | Trigger |
|---|---|
| `-applying.md` | branch created, `/team` running |
| `-pass.md` | `/team` returned `verdict:PASS` in `team-status.json` |
| `-fail.md` | `verdict:FAIL_CRITICAL`, subprocess crash, or `team-status.json` missing |
| `-complex.md` | `review_iterations > 3` in `team-status.json` |
| `-rejected.md` | user said NO at the AskUserQuestion gate |

Atomic transitions via `mv` (POSIX rename atomicity). Re-entry: any `*-applying.md` present at startup → notify "previous run mid-apply" + exit.

## Workflow

### 1. Pre-flight

```bash
PENDING="$HOME/.claude/state/PENDING-IMPROVEMENT.md"
APPLYING_DIR="$HOME/.claude/state/applying"
mkdir -p "$APPLYING_DIR"

if [ ! -f "$PENDING" ]; then
    osascript -e 'display notification "Nothing pending. Cron has not surfaced a [high] item." with title "Claude plugin"' || true
    echo "Nothing pending."
    exit 0
fi

# Re-entry guard: any -applying marker = previous run interrupted.
if ls "$APPLYING_DIR"/*-applying.md >/dev/null 2>&1; then
    osascript -e 'display notification "Previous improvement mid-apply. Inspect or rm marker to reset." with title "Claude plugin"' || true
    echo "Previous run is still marked -applying. Inspect: ls $APPLYING_DIR ; git status ; git branch"
    exit 1
fi

# All-disposed sentinel: the monitor hook writes "# PENDING — none" (no Item: line) when every
# Actionable radar entry is already dispositioned. That file passes the [ -f ] check above, so without
# this guard /team would spawn on an empty task (ADR 0013 D8 — nothing actionable => exit clean).
if ! grep -q '^Item:' "$PENDING"; then
    osascript -e 'display notification "Nothing actionable (all radar items disposed)." with title "Claude plugin"' || true
    echo "Nothing actionable: PENDING has no Item: line (all-disposed sentinel)."
    exit 0
fi
```

### 2. Display item + gate

Read `PENDING-IMPROVEMENT.md`, display the `Item:` line in the chat, then call `AskUserQuestion` with the verbatim item text and a yes/no choice.

Capture mtime before/after the question to detect a concurrent cron overwrite:

```bash
MTIME_BEFORE=$(stat -f %m "$PENDING")
# ... AskUserQuestion ...
MTIME_AFTER=$(stat -f %m "$PENDING")
if [ "$MTIME_BEFORE" != "$MTIME_AFTER" ]; then
    echo "PENDING changed during confirmation. Re-run /apply-improvement."
    exit 1
fi
```

### 3. NO branch

If the user answers NO:

```bash
WEEK=$(date +%Y-W%V)
SLUG=$(head -1 "$PENDING" | sed 's/^# PENDING — //')
mv "$PENDING" "$APPLYING_DIR/$WEEK-$SLUG-rejected.md"
exit 0
```

No branch, no commit. The marker captures the decision for the audit trail (`git log state/applying/`).

### 4. YES branch — pre-checks

Each `bash` block in a skill is invoked independently by the lead LLM via the Bash tool — variables do not persist across blocks. Each block re-derives `WEEK`, `SLUG`, `BRANCH`, `APPLYING_MARKER` from disk state.

```bash
WEEK=$(date +%Y-W%V)
SLUG=$(head -1 "$HOME/.claude/state/PENDING-IMPROVEMENT.md" 2>/dev/null | sed 's/^# PENDING — //' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g')
BRANCH="improvement/$WEEK"
APPLYING_DIR="$HOME/.claude/state/applying"
APPLYING_MARKER="$APPLYING_DIR/${WEEK}-${SLUG}-applying.md"

# Working tree must be clean.
if [ -n "$(git status --porcelain)" ]; then
    osascript -e 'display notification "Working tree dirty. Stash or commit, then re-run." with title "Claude plugin"' || true
    echo "Working tree not clean. Aborting."
    exit 1
fi

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    osascript -e 'display notification "Branch $BRANCH already exists. Inspect or delete it first." with title "Claude plugin"' || true
    echo "Branch $BRANCH exists. Aborting."
    exit 1
fi
```

### 5. Branch + marker

```bash
WEEK=$(date +%Y-W%V)
SLUG=$(head -1 "$HOME/.claude/state/PENDING-IMPROVEMENT.md" 2>/dev/null | sed 's/^# PENDING — //' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g')
BRANCH="improvement/$WEEK"
APPLYING_DIR="$HOME/.claude/state/applying"
APPLYING_MARKER="$APPLYING_DIR/${WEEK}-${SLUG}-applying.md"
PENDING="$HOME/.claude/state/PENDING-IMPROVEMENT.md"

git checkout -b "$BRANCH"
cp "$PENDING" "$APPLYING_MARKER"
```

PENDING stays in place until the terminal state — re-entry safety (D4).

### 6. Subprocess `/team`

Extract the `Item:` text from PENDING, then invoke `/team` per the §Subprocess contract of ADR 0013:

```bash
ITEM=$(grep '^Item:' "$PENDING" | sed 's/^Item: //')
TEAM_DIR_HINT="auto-improvement-$(date +%Y%m%d%H%M%S)"
export AUTO_IMPROVEMENT_SOURCE="$PENDING"
export AUTO_IMPROVEMENT_TEAM_DIR="$HOME/.claude/tmp/$TEAM_DIR_HINT"
export IMPROVEMENT_PIPELINE=1

TEAM_NO_GC=1 claude -p \
    --permission-mode bypassPermissions \
    --max-budget-usd 5.00 \
    "/team --auto $ITEM (auto-improvement context, status JSON required at \$AUTO_IMPROVEMENT_TEAM_DIR/team-status.json)" \
    || true

# 30 min timeout enforced by the caller, not inside this skill (use `timeout` if needed).
```

`--permission-mode bypassPermissions` (not `auto`): a headless `-p` subprocess cannot answer a permission prompt, and `auto` still prompts before editing `~/.claude/**` — the prompt auto-denies and the dev returns `STATUS: BLOCKED` (observed W21, 2026-05-21). `bypassPermissions` matches the main session's `defaultMode` and stays safe under the ADR 0013 model: the subprocess works on an isolated `improvement/YYYY-WW` branch and nothing merges without the manual human gate.

### 7. Parse verdict + transition

```bash
WEEK=$(date +%Y-W%V)
SLUG=$(head -1 "$HOME/.claude/state/PENDING-IMPROVEMENT.md" 2>/dev/null | sed 's/^# PENDING — //' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g')
APPLYING_DIR="$HOME/.claude/state/applying"
APPLYING_MARKER="$APPLYING_DIR/${WEEK}-${SLUG}-applying.md"

# Find the team dir actually used (the lead may pick its own timestamp).
STATUS_JSON=$(ls -t "$HOME"/.claude/tmp/*/team-status.json 2>/dev/null | head -1)

if [ -z "$STATUS_JSON" ] || [ ! -f "$STATUS_JSON" ]; then
    mv "$APPLYING_MARKER" "${APPLYING_MARKER%-applying.md}-fail.md"
    REASON="team-status.json missing (crash or contract violation)"
else
    VERDICT=$(jq -r '.verdict' "$STATUS_JSON")
    ITER=$(jq -r '.review_iterations // 0' "$STATUS_JSON")
    case "$VERDICT" in
        PASS)
            mv "$APPLYING_MARKER" "${APPLYING_MARKER%-applying.md}-pass.md"
            REASON="PASS"
            ;;
        FAIL_CRITICAL)
            mv "$APPLYING_MARKER" "${APPLYING_MARKER%-applying.md}-fail.md"
            REASON="FAIL_CRITICAL"
            ;;
        *)
            mv "$APPLYING_MARKER" "${APPLYING_MARKER%-applying.md}-fail.md"
            REASON="unexpected verdict: $VERDICT"
            ;;
    esac
    if [ "$ITER" -gt 3 ]; then
        # Override: complex takes precedence over fail/pass for review iter cap.
        FINAL_MARKER=$(ls "$APPLYING_DIR/$WEEK-$SLUG-"{pass,fail}.md 2>/dev/null | head -1)
        [ -n "$FINAL_MARKER" ] && mv "$FINAL_MARKER" "$APPLYING_DIR/$WEEK-$SLUG-complex.md"
        REASON="COMPLEX (review_iterations=$ITER)"
    fi
fi
```

### 8. E2E tests (best-effort)

```bash
if [ -x "$HOME/.claude/tests/e2e-improvement.sh" ]; then
    "$HOME/.claude/tests/e2e-improvement.sh" >/dev/null 2>&1 && E2E="pass" || E2E="fail"
else
    E2E="skip"
fi
```

### 9. Notify + cleanup

```bash
osascript -e "display notification \"Improvement applied: $REASON. E2E: $E2E. Next: git diff main..$BRANCH ; git merge $BRANCH OR git branch -D $BRANCH\" with title \"Claude plugin\"" || true

# Always print the exact follow-up commands to stdout (the authoritative channel).
cat <<EOF

## Result: $REASON
- Branch: $BRANCH
- E2E: $E2E
- Inspect: git diff main..$BRANCH
- Accept:  git checkout main && git merge --no-ff $BRANCH
- Reject:  git checkout main && git branch -D $BRANCH

EOF

# Consume PENDING — terminal state reached.
rm -f "$PENDING"
```

## Anti-patterns

- Never `git merge` automatically. Always `git checkout -b` only, even on PASS.
- Never retry `/team` on FAIL_CRITICAL — the marker captures it, surface to user, stop.
- Never delete `state/applying/*` markers — they are the audit trail. `git log state/applying/` + `git reflog` give full history.
