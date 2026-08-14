---
description: Manage ADRs (.claude/decisions/) and current state (.claude/state/) of the project
argument-hint: "[optional] init | update | show | decision <title>"
context: fork
background: false
---

## Project context
- Name: !`basename $(pwd)`
- Stack: !`cat package.json 2>/dev/null | head -5 || cat requirements.txt 2>/dev/null | head -5 || echo "Stack non detectee"`
- Existing decisions: !`ls .claude/decisions/ 2>/dev/null || echo "Pas de .claude/decisions/"`
- Existing state: !`ls .claude/state/ 2>/dev/null || echo "Pas de .claude/state/"`

## Goal

Manage two project folders:
- `.claude/decisions/` — accepted ADRs, **append-only**, numbered `NNNN-slug.md`
- `.claude/state/` — mutable state, rewritten at will (`STATE.md`, `ROADMAP.md`)

## Commands

### `init` (or if these folders do not exist)

#### Step 0 — Gitignore check (MANDATORY before creation)

ADRs are **versioned by design** (append-only, source of truth). If `.claude/` is gitignored globally, the ADRs will be invisible to git → breaks the promise.

1. Check `.gitignore`: look for a pattern that matches the entire `.claude/` (not a subpath).
   - **Match**: lines starting with `.claude`, `.claude/`, `.claude/*`, `/.claude`, `/.claude/` (with or without a trailing comment)
   - **Not a match**: specific subpaths such as `.claude/tmp/`, `.claude/agent-memory/`, `.claude/cache/`
   - Robust grep: `grep -E '^/?\.claude/?(\*)?[[:space:]]*(#.*)?$' .gitignore 2>/dev/null`
2. Also check if an exception already exists for `decisions/` or `state/`: `grep -E '^!\.claude/(decisions|state)' .gitignore 2>/dev/null`. If yes → move on to the next step, no warning.
3. If the entire `.claude/` is gitignored AND no exception:
   - Display a clear WARNING: `.claude/ est gitignore. Tes ADRs ne seront PAS versionnes.`
   - Propose 3 options via `AskUserQuestion`:
     - (a) Add `!.claude/decisions/` and `!.claude/state/` in `.gitignore` (the skill adds them at the end of the file)
     - (b) Place `decisions/` and `state/` at the root (`./decisions/`, `./state/`) instead of inside `.claude/`
     - (c) Continue anyway (ADRs not versioned, risk accepted)
4. Depending on the user's choice:
   - (a) → append `\n!.claude/decisions/\n!.claude/state/\n` to `.gitignore`, then continue init in `.claude/`
   - (b) → use `./decisions/` and `./state/` at the root for all subsequent commands (adapt the paths shown in the visible WARNING)
   - (c) → continue inside `.claude/` without modifying the gitignore

If `.gitignore` is absent, or `.claude/` is not gitignored → go directly to step 1.

#### Step 1 — Creation

Create `.claude/decisions/` and `.claude/state/` with:

**`.claude/state/adr-template.md`** (stored in `state/`, not in `decisions/`, so as NOT to pollute the list of active ADRs):
```markdown
# ADR NNNN — {titre}

**Status**: Proposed | Accepted | Supersedes NNNN | Superseded by NNNN
**Date**: YYYY-MM-DD

## Context
Quel problème/choix déclenche cette décision.

## Decision
La décision en 2-3 phrases.

## Consequences
- Positive : ...
- Negative : ...
- Neutre : ...

## Alternatives considered
| Option | Retenue ? | Raison |
|--------|-----------|--------|
```

**`.claude/state/STATE.md`**:
```markdown
# Etat du projet — {nom}
**Derniere mise a jour** : YYYY-MM-DD

## En cours
- ...

## ADRs recents
(auto-maintenu — ls .claude/decisions/*.md par date)
```

**`.claude/state/ROADMAP.md`**:
```markdown
# Roadmap — {nom}

## En cours
- ...

## A venir
- ...

## Termine
- ...
```

### `decision <title>`

Create `.claude/decisions/NNNN-<slug>.md` from `.claude/state/adr-template.md` (NNNN = max existing + 1, zero-padded to 4 digits). Substitute `NNNN` in the content with the assigned number. Open in the editor if possible, otherwise display the path.

### `update`

Update `.claude/state/STATE.md` from:
- `git log --oneline -20`
- `git diff --stat`
- `ls .claude/decisions/*.md` to regenerate the "ADRs recents" section

### `show`

Display: ADR list + STATE.md + ROADMAP.md.

## Default behavior

- If neither folder exists → `init`
- Otherwise → `show`

## Backward compatibility

If `.planning/` exists (old format):

**Pre-check: git tracking of `.planning/`**

Detect whether `.planning/` is tracked in git: `git ls-files .planning/ 2>/dev/null | head -1`.
- **If tracked** (at least one file returned): migrating to `.claude/state/` while leaving `.claude/` gitignored would silently lose the git history.
  - Do NOT migrate automatically.
  - Display WARNING: `.planning/ est tracke en git (N fichiers). Migration auto = perte visibilite git.` (N = `git ls-files .planning/ | wc -l`)
  - Propose 3 options via `AskUserQuestion`:
    - (a) **Keep `.planning/` as is** (recommended) — the skill configures access to the 2 locations (`.planning/` remains the source for historical files, new ADRs go into `.claude/decisions/`)
    - (b) **Migrate to `.claude/state/` AND version it** — automatically adds `!.claude/decisions/` and `!.claude/state/` in `.gitignore` to exclude these folders from the global `.claude/` gitignore, then migrate the files.
    - (c) **Migrate without versioning** — git history loss, explicit confirmation required
- **If not tracked**: automatic migration OK (steps below).

**Migration (if authorized by the pre-check)**:
1. Create empty `.claude/decisions/` and `.claude/state/`
2. Copy `.planning/STATE.md` → `.claude/state/STATE.md`
3. Copy `.planning/ROADMAP.md` → `.claude/state/ROADMAP.md`
4. Copy `.planning/PROJECT.md` and `REQUIREMENTS.md` into `.claude/state/` (compat)
5. Display: "Migration .planning/ → .claude/ effectuée. Tu peux supprimer .planning/ après vérification."

Do NOT delete `.planning/` automatically (the user validates).

