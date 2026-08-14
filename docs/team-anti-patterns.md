# /team anti-patterns and recovery

## ANTI-PATTERNS — NEVER DO

- Launching teammates before STEP 0 (mandatory workflow validation)
- Spawning teammates before having decomposed the task
- Spawning a dialogue teammate without an explicit `name` (unaddressable via SendMessage; `team_name` itself is deprecated — single implicit team)
- Running everything sequentially when tasks are independent
- Giving the same large context blob to each teammate — targeted context only
- Copying the architecture document content into a prompt — always pass the file path
- Specifying the model manually in spawns (it is automatically inherited from the leader)

## RECOVERY — STUCK TEAMMATE

1. Send a message to the stuck teammate
2. If no response or still stuck → shutdown the teammate
3. **Before respawning**: run `git status` and `git diff --stat` to see what was done
4. Spawn a new teammate of the same type with:
   - Full context of where things stand
   - Current git state (modified files, diff)
   - What was left to do
5. Inform the user of the issue and the resumption
6. TaskUpdate the current task to reflect the change of owner

## CONVERGENCE LIMITS

| Loop | Max iterations | Independent of |
|------|---------------|----------------|
| Arch challenge (STEP 1.5) | 5 | Everything |
| Code challenge (STEP 2.5) | 5 | Everything |
| Review/fix (STEP 3-4) | 3 | Challenge |
| Test/fix (STEP 5) | 3 | Review/fix |
| Direct exchanges between teammates | 5 (lead intervenes) → 10 max | Everything |

## RELIABILITY PATTERNS

### 1. Teammate message dedup (rule 14)

**Problem**: a teammate sending `STATUS: DONE` may re-deliver its report via `idle_notification` or directly. The lead LLM does not dedup naturally.

**Pattern**: explicit state machine via `TaskUpdate.metadata`. After 1st DONE: mark `delivered_by`. Before processing a message: check metadata.

**Observed case**: a teammate re-delivered 3x in a single session; several others 2x. Proof that the lead forgets without persisted state.

### 2. Socket-aware tmux capacity (legacy pane era — rule 15 now covers Workflow scheduler capacity)

**Problem**: `tmux list-panes -a` without `-L` connects to the default socket (e.g.: 11 user shellfish panes). The teams are on `/tmp/tmux-$(id -u)/claude-swarm-*`. The naive threshold measures the wrong socket and lets spawns through while the claude-swarm socket is saturated.

**Pattern**: detect the active claude-swarm socket via `ls /tmp/tmux-$(id -u)/claude-swarm-* | head -1` then `tmux -S $SOCK list-panes -a | wc -l`.

**Observed case**: `tmux list-panes -a` returned 11 (shellfish), while `tmux -S claude-swarm-99532 list-panes -a` returned 2 (real teammates).

### 3. GC filesystem orphans (STEP 0bis)

**Problem**: teams never `TeamDelete`d, tmp dirs never cleaned up. Filesystem accumulates orphans indefinitely.

**Pattern**: `hooks/team-gc.sh` with mtime threshold of 7 days. Dry-run by default, `--force` after user confirmation. Excludes teams with a tmux socket still active.

**Observed case**: 4 teams + 15 tmp dirs orphaned in `~/.claude/teams/` and `~/.claude/tmp/` (dates >7 days). 13 `.md` files at the root of `.claude/tmp/` (sub-agent pollution).

### 4. Shutdown timeout 30s (rule 16)

**Problem**: `shutdown_request` without a timeout makes the lead wait indefinitely if the teammate is a zombie.

**Pattern**: strict timeout; after expiry, log and close the task row (rule 16) — no registry teardown exists since TeamDelete's removal. Data loss minimal because Write is POSIX-atomic.

### 5. Lead-only mkdir + block tmp root pollution (rule 12 + hook)

**Problem**: sub-agents can write `*.md` at the root of `.claude/tmp/` instead of inside their team folder.

**Pattern**:
- Rule 12: LEAD alone runs `mkdir -p .claude/tmp/{team-name}/` before any spawn, with existence check
- Hook `block-pollution-files.sh` blocks Write/Edit on `.claude/tmp/*.md` (1st line of defense)

