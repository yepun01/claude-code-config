# ADR 0010 — Viewer markdown renderer : custom JSX au lieu de marked + DOMPurify

## Status

Proposed (2026-05-01). **Amends ADR 0004 D-1** (`decisions/0004-viewer-multi-plateforme.md:40`) — autorise un custom JSX renderer pour Phase 1d à la place du pipeline `marked` v13+ → `DOMPurify` v3 strict mode initialement mandaté. **Étend ADR 0004 endpoint inventory** (ligne 33-36) avec `GET /notes?path=` (lecture markdown ADR via `DECISIONS_DIR` sandbox).

## Context

Phase 1d Decisions sub-page (per ADR 0008 D-4c) demande un rendering markdown des ADRs : "headings, code blocks, lists, tables". Implémentation initiale = `renderMarkdown` custom 45 LOC dans `viewer/src/pages/Decisions.tsx` qui supporte h1/h2/h3 + ul/li + paragraphes via JSX (pas `dangerouslySetInnerHTML`). Le custom renderer émerge comme déviation du pipeline ADR 0004 D-1 mandate.

Compliance scanner (ultra-review Phase 1d, 2026-05-01) flag HIGH : "renderMarkdown bypasse pipeline marked+DOMPurify obligatoire ADR 0004 D-1 ligne 40". Scope expansion backend `GET /notes?path=` (handleNotesRead, 10 LOC + path traversal protection via `resolve()` + `startsWith(DECISIONS_DIR + sep)`) flag MEDIUM : "endpoint hors inventory ADR 0004 D-1 4-endpoints".

Trois trajectoires évaluées :
- **(A) Installer marked + DOMPurify** : alignement strict ADR 0004 D-1, +2 deps (~30-40 KB gz selon tree-shaking, frôle target 50 KB ADR 0004 D-1), config DOMPurify allowlist non-triviale, couvre tables/code blocks gratuit, T8 fuzz test exécutable directement.
- **(B) Custom JSX renderer (status quo Phase 1d) + amend ADR 0004 D-1** : 0 deps (bundle stable 47 kB gz mesuré), JSX auto-escape couvre XSS pour string content, manque tables/code blocks (acceptable Phase 1d : ADRs actuels n'en utilisent pas significativement), T8 à porter sur custom renderer.
- **(C) Différer décision Phase 1e** : dette ADR connue mais non résolue, ROADMAP item ajouté.

Sélection user : **(B)** post-AskUserQuestion 2026-05-01. Rationale user : "0 deps ajoutés, ADR 0004 reste Proposed donc l'amendement formalise le shift, pas de re-implementation Phase 1d".

## Decision

### D-1 · Custom JSX markdown renderer pour ADRs viewer

`renderMarkdown(text: string): JSX.Element[]` dans `viewer/src/pages/Decisions.tsx` — parser line-based qui produit du JSX (auto-escape par construction Preact). Tags supportés Phase 1d : `h1` (`# `), `h2` (`## `), `h3` (`### `), `ul`/`li` (`- `), `p` (paragraphes joinés). Tags non-supportés Phase 1d : tables (`|`), code blocks (` ``` `), inline code (`` ` ``), images, links, blockquotes, em/strong. Comportement sur tags non-supportés : rendu comme texte plat dans paragraphe (ex: ligne `**bold**` → `<p>**bold**</p>`).

Pas de `dangerouslySetInnerHTML` dans le rendering path. JSX auto-escape garantit que tout string injecté (titres, contenus paragraphes) est échappé HTML par Preact — vecteurs XSS classiques (`<script>`, `<img onerror=>`, `<a href="javascript:">`) rendus comme texte affiché.

### D-2 · Endpoint `GET /notes?path=`

Ajout à l'endpoint inventory ADR 0004 D-1 :
- `GET /notes?path=<relpath>` — lit le contenu d'un fichier sous `DECISIONS_DIR` (`~/.claude/decisions/`). Path traversal : `resolve(DECISIONS_DIR + path)` + `startsWith(DECISIONS_DIR + sep)` check. Réponse `200 text/plain; charset=utf-8` ou `400 Bad Request` (path invalide / hors sandbox). Pas d'auth (le serveur bind localhost only per ADR 0004 D-1).

Convention : `/notes` GET (lecture markdown ADR) coexiste avec `/notes` POST (append `NOTES.jsonl`) — semantique différente per verbe HTTP, pas d'ambiguïté.

### D-3 · Migration vers marked + DOMPurify différée

Phase 1d ne porte pas la lib markdown. La migration est différée à Phase 2 ou plus tard, déclenchée empiriquement par l'un des signaux suivants :
- Un ADR du repo introduit tables ou code blocks significatifs (≥3 occurrences sur ≥2 ADRs)
- Le custom renderer atteint ≥80 LOC (overrun simplicity budget)
- Un test fuzz T8-style trouve un bypass de l'auto-escape JSX (improbable, mais signal d'invalidation)

Si déclenchée, la migration est un nouvel ADR (0011 ou plus) qui supersede ce D-1.

## Consequences

**Positives**
- Bundle gz reste stable (47 kB mesuré, < 50 kB target ADR 0004 D-1)
- Zéro deps ajoutés à `viewer/package.json` (preact, @preact/signals, dexie, preact-iso seulement)
- Phase 1d livrée sans library lock-in non décidé
- Custom renderer = 45 LOC lisibles, debugger-friendly (pas de couche marked tokens → DOMPurify hooks)

**Négatives**
- Tables et code blocks pas supportés Phase 1d. Sur les 9 ADRs actuels, 1 (`0004-viewer-multi-plateforme.md`) a une grammaire markdown avec ` ``` ` qui s'affichera comme paragraphe plat — dégradé visuel acceptable Phase 1d, à mesurer empiriquement post-merge
- T8 (XSS fuzz `<script>window.__pwn=1</script>`) pas exécuté contre custom renderer Phase 1d. À porter Phase 2 si custom renderer perdure
- Si Phase 2 introduit besoin tables/code blocks → migration marked+DOMPurify obligatoire (re-write Decisions.tsx, +30-40 kB gz)

**Neutres**
- Endpoint `GET /notes?path=` ajoute une surface attaque pour path traversal — mitigée par `resolve()` + `startsWith()` empiriquement testés (6 vecteurs : `decisions/0001-...`, `..`, `../etc/passwd`, paths absolus, segments mixtes — tous rejetés sauf paths sous `decisions/`)
- Symlinks sous `decisions/` non résolus avant le prefix check : surface mitigée par convention "pas de symlinks dans `decisions/`" (zero ajoutés par Claude Code, audit empirique : 0 symlinks dans `~/.claude/decisions/` 2026-05-01)

## Tests that would invalidate this design

- **T1** (D-1 — XSS via JSX auto-escape) : injecter dans un ADR le payload `<script>window.__pwn=1</script>` au sein d'un paragraphe ; ouvrir le viewer headless (Playwright), naviguer vers `/meta/decisions?focus=<id>` ; asserter `await page.evaluate(() => window.__pwn) === undefined` ET aucun `<script>` actif dans le DOM. Signal d'invalidation : `__pwn === 1` OU élément `<script>` exécuté → custom renderer compromis, migration marked+DOMPurify obligatoire immédiate.
- **T2** (D-1 — infinite loop sur input pathologique) : invoquer `renderMarkdown("####\n#tag\n#!/bin/bash\n")` (3 lignes commençant par `#` non-prefixe heading) ; asserter retour dans <100ms avec ≥1 paragraphe rendu. Signal d'invalidation : timeout / OOM / call-stack overflow → fix iter 1 invalidé, redesign loop.
- **T3** (D-2 — path traversal `GET /notes`) : `curl 'http://localhost:4848/notes?path=../etc/passwd'` puis `curl 'http://localhost:4848/notes?path=decisions/../etc/passwd'` puis `curl 'http://localhost:4848/notes?path=/etc/passwd'`. Réponse attendue 400 sur les 3. Signal d'invalidation : statut 200 + contenu `/etc/passwd` → handleNotesRead compromis.
- **T4** (D-3 — déclenchement migration empirique) : compter via grep le nombre d'ADRs contenant ` ``` ` ou tables `|` significatives. Si ≥3 sur ≥2 ADRs → trigger migration marked+DOMPurify (D-3 explicit). Signal d'invalidation : si seuil atteint et migration non lancée 2 phases plus tard → custom renderer dette technique non gérée.
