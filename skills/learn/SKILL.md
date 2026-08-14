---
description: Extract and persist the knowledge acquired during a /team pipeline or after a work session
argument-hint: <optional summary of what was done>
---

## Goal

Extract structured learnings from the work that was just performed and persist them in the file-based auto-memory (`~/.claude/projects/<slug>/memory/`) to accelerate future pipelines.

## Context

**If invoked from /team**: use the context provided in `$ARGUMENTS` (pipeline type, iterations, arch.md, issues). Do NOT re-analyze the entire git log.

**If invoked independently**: analyze `git log -20` and `git diff HEAD~5` to reconstruct the context of the recent work.

**Project name**: !`basename $(pwd)`

## 5 extraction axes

### Axis 1 — Context analysis
- What **TYPE** of problem was it? (bug, feature, refactor, perf, security...)
- Which **DOMAIN**? (API, frontend, data, infra, CI/CD...)
- What real vs estimated **COMPLEXITY**? (under-estimated / well estimated / over-estimated)

### Axis 2 — Solution extraction
- What **WORKED**? (patterns, approaches, tools)
- What **FAILED** and **WHY**? (root cause, not just "it didn't work")
- Were there any **PIVOTS**? (change of approach, re-architecture)

### Axis 3 — Related docs
- Existing docs to update? (README, API docs, architecture docs)
- New reusable patterns to document?
- **Flag** the docs to update — do NOT modify them

### Axis 4 — Prevention
- How to **PREVENT** this category of problems in the future?
- Could a hook, a test, or a lint rule catch this automatically?
- **Propose** (do not implement) process improvements

### Axis 5 — Classification and persistence
Structured tags for future retrieval:
- `domain`: [API | frontend | data | infra | CI/CD | ...]
- `pattern`: [name of the main pattern used]
- `stack`: [technologies involved]
- `difficulty`: [XS | S | M | L | XL]
- `pipeline_type`: [feature | bug | refactor | ...]

**IMPORTANT — auto-memory vs `.claude/decisions/` boundary**: If a learning of type 'project archi decision' (`Pattern X choisi pour raison Y`, `Stack Z retenue pour raison W`) is identified, do NOT persist it in auto-memory. Instead, suggest to the user: `/spec decision <titre>` to create a dedicated ADR. Auto-memory is reserved for **general** patterns (language gotchas, commit conventions, tooling tips, process lessons).

## Persistence

Store in the file-based auto-memory of the **current project**:

1. Resolve the store: `MEMORY_DIR=~/.claude/projects/$(pwd | sed 's|[/.]|-|g')/memory` (slug = cwd with `/` and `.` replaced by `-`). If the directory does not exist, STOP and report "store introuvable: {path}" — do not create it, do not write elsewhere.
2. **Anti-duplicate**: read `MEMORY.md` (the index). If an existing memory already covers this learning → UPDATE that file (Edit) instead of creating a new one.
3. Otherwise write `{MEMORY_DIR}/feedback_{slug-court}.md`:

```markdown
---
name: {slug-court-kebab}
description: {résumé 1 ligne — utilisé pour le recall}
metadata:
  type: feedback
---

{Le pattern/l'erreur, 2-5 lignes. Ce qui a marché / échoué + cause racine.}

**Why:** {pourquoi c'est vrai — evidence}
**How to apply:** {condition d'applicabilité + geste concret}
```

4. Add one index line to `{MEMORY_DIR}/MEMORY.md` under `## Feedback`: `- [Titre](feedback_{slug-court}.md) — {hook 1 ligne}`. Never put memory content in the index. Leave `.consolidate-lock` untouched.

If the learning contains a **SUBSTANTIAL REUSABLE PATTERN** (non-obvious transferable solution) → also write it in `docs/solutions/{slug}.md`.

## Output format

```
## Learning — {titre court}

| Axe | Résultat |
|-----|----------|
| Contexte | {type} / {domaine} / {complexité réelle vs estimée} |
| Solution | {ce qui a marché + pourquoi} |
| Échec | {ce qui a échoué + pourquoi} |
| Docs | {docs à mettre à jour — liste ou "aucune"} |
| Prévention | {suggestion concrète ou "aucune"} |
| Tags | {domain, pattern, stack, difficulty} |

Persisté: {MEMORY_DIR}/{fichier}.md ✓ (+ index MEMORY.md)
```

## Rules

- Maximum 2 minutes of execution — not a thesis
- Do NOT create a learning if the work was trivial and taught nothing new
- Do NOT modify project files (the only authorized writes: the auto-memory store `{MEMORY_DIR}/` per the Persistence section, and `docs/solutions/` if a substantial pattern)
- If invoked from /team: use the provided context, do not re-analyze the git log
- If invoked independently: analyze `git log -20` and `git diff HEAD~5` for the context

