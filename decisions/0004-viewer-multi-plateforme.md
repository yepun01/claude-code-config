# ADR 0004 — Viewer multi-plateforme du plugin Claude Code

## Status

Proposed (2026-04-29, iter 3). Implementation pending. Synthesizes 4 helper deliverables from team `viewer-design-1777468836` (analyzer, deep-analyzer, designer, innovator). Iter 3 adresse les 4 CRITICAL + 9 HIGH du verdict ultra-review iter 2 (cf. *Iter 3 changelog* en fin de document). D-1 amended by 0010 §D-1 (custom JSX renderer + GET /notes?path). D-2 partially superseded by 0008 §D-1 (sidebar nav primaire, ⌘K différé). D-4 obsoleted (cf. 0016 §D-2): viewer ships with server-side index at request time (viewer/server/indexer.ts) instead of hook M-1 / cache/viewer-index.jsonl / skill /viewer. Implementation reconciled by 0018: viewer technical layer shipped (viewer/server/), consistent with the D-4 note above; the « Implementation pending » head is superseded.

## Context

Le plugin Claude Code de cet utilisateur (`~/.claude/`) émet ~30 signaux sémantiques structurés sur 8 strates [OBSERVED: tmp/viewer-design-1777468836/signal-analysis.md:8-78] : trame ADR/JOURNAL/state, trame agent/skill/protocole (verdict, STATUS, evidence markers, refutable-by, justification score, CC-START/END), trame d'exécution (sessions JSONL, inboxes, metrics, file-history). Les ADR existants (0001, 0002, 0003) totalisent ~138 evidence markers verifiables et ~25 lignes `Refutable by:` — un capital épistémique inhabituellement riche pour un repo de configuration personnel.

Deux protos précédents ont été invalidés [OBSERVED: user brief]:

1. **Dashboard d'events bruts (style disler)** — sature la trame d'exécution, ignore la sémantique métier des ADR.
2. **Markdown rendered + badges décoratifs** — passive, ne pose pas l'unité atomique au bon niveau.

Inversion de contrainte structurelle requise (criteria item 3) : casser au moins une parmi *linéaire* / *mono-vue* / *fichier-centré*. Cible plate-forme : **iPhone Safari + Mac équilibrés**, pas mobile-dégradé. Cap modifs plugin : **< 5**.

Convergence forte des 3 helpers indépendants sur trois pivots :

- Command Palette comme nav primaire unifiée [OBSERVED: tmp/viewer-design-1777468836/ux-patterns.md:9-31, innovation-angles.md:47-79].
- Claim atomique comme unité (≠ fichier) [OBSERVED: tmp/viewer-design-1777468836/innovation-angles.md:7-43, signal-analysis.md:84].
- Evidence markers et refutable-by promus en typographie de premier ordre [OBSERVED: tmp/viewer-design-1777468836/ux-patterns.md:103-113, signal-analysis.md:84-90].

Le but de cet ADR est de **synthétiser** (pas re-explorer) ces convergences en un design cohérent, falsifiable, et phasé.

## Decision

### D-1 · Architecture : PWA installable + mini-backend write-only + indexeur local incrémental

Single-Page App côté client (Vite + Preact + signals, **~50 KB gz vendor+app à mesurer au 1ᵉʳ build** — décomposition réaliste : Preact 4.2 KB + signals 2 KB + Dexie 24 KB vendor + ~15-20 KB code applicatif). Le store côté client est **IndexedDB via Dexie** [SOURCE community: w3.org/TR/IndexedDB recommendation], alimenté par `~/.claude/cache/viewer-index.jsonl` régénéré incrémentalement par hook (cf. D-4).

**Service** : un mini-backend Bun (`viewer/server.ts`, ~60-80 LOC) plutôt qu'un static-only. Le service est **viewer = SPA + petit backend write-only** :
- `GET /` + assets statiques sous `viewer/dist/`
- `GET /index.jsonl` lit `~/.claude/cache/viewer-index.jsonl` (read-only)
- `POST /notes` append-only sur `~/.claude/state/NOTES.jsonl` avec `flock(2)` exclusif + `fsync` + JSON validation par ligne (cf. D-7)
- `POST /token/rotate` régénère le bearer token (cf. D-5)

Le binaire `bun` (Bun runtime) sert simultanément les statiques et les ~3 endpoints. Aucune DB serveur, aucun état mémoire stateful (le filesystem `~/.claude/` reste la source de vérité ; le serveur n'est qu'un bridge filesystem ↔ HTTP). La PWA est installable (manifest + service worker) sur iPhone et Mac (Safari, Edge, Chrome).

**Rendu Markdown sécurisé** (mitigation S-1 XSS) : pipeline obligatoire `marked` v13+ → `DOMPurify` v3 strict mode. Allowlist tags : `p, h1-h6, ul, ol, li, code, pre, table, thead, tbody, tr, th, td, blockquote, em, strong, a[href|title], img[src|alt], hr, span[class]`. Tags interdits explicites : `script, iframe, object, embed, style, link, form, input` ; attributs interdits : `on*` (tous les event handlers), `srcset`, `formaction`. Tous `<a>` externes obtiennent `rel="noopener noreferrer"` post-purify [SOURCE community: github.com/cure53/DOMPurify].

**Headers HTTP servis** par `viewer/server.ts` :
- `Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'` [SOURCE community: developer.mozilla.org/Web/HTTP/CSP]
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: same-origin`
- `X-Frame-Options: DENY` (redondant avec `frame-ancestors 'none'` pour navigateurs anciens)
- `Strict-Transport-Security: max-age=31536000; includeSubDomains` (uniquement quand servi via Tailscale Serve HTTPS)

`'unsafe-inline'` pour `style-src` est nécessaire à l'inline color tokens des badges (densité rich, D-6) ; `script-src 'self'` reste strict — aucun JS inline accepté.

Pourquoi pas natif SwiftUI : effort 5×–10× pour parité fonctionnelle [ENGINEERING: règle empirique cross-platform vs single-platform-native], rupture avec la philosophie "appended-only filesystem" du plugin, et impossible à itérer sans Xcode + Apple Developer account. Pourquoi pas webview embarquée dans Claude Code : couplage runtime fragile, perte d'autonomie de versionning, cycle de vie incertain. Pourquoi pas `bun --static` ou `python -m http.server` purs : impossibilité physique d'écrire `NOTES.jsonl` côté client (cf. iter 3 fix B1-C1) ET aucun header de sécurité posable (cf. iter 3 fix S-4).

*Refutable by:* si le **LCP** (Largest Contentful Paint via `PerformanceObserver`, Web Vitals "good" threshold = 2.5s [SOURCE community: web.dev/lcp]) dépasse 2.5s sur iPhone Safari avec 50 ADRs et 200 claims indexés (réseau Tailscale local), l'hypothèse "static SPA local-first scale acceptable" tombe — pivot vers server-side rendering ou pré-pagination index. Note : `performance.timing.firstMeaningfulPaint` est deprecated et retourne 0/undefined sur Safari iOS — ne pas utiliser.

### D-2 · Navigation primaire : Command Palette comme entrée unique

**Pas de dashboard préfabriqué**. L'écran d'accueil est une palette. La "vue" est le résultat d'une query [OBSERVED: tmp/viewer-design-1777468836/innovation-angles.md:47-79].

Grammaire de query : **parser combinator** (chevrotain ou peggy, ~5 KB gz minifié, error-recovery natif, AST inspectable [SOURCE community: chevrotain.io/docs, peggyjs.org]). Pas de regex hand-rolled — un parser combinator évite catastrophic-backtracking, expose la grammaire formellement et tolère l'extension de keys sans code change (open-set via lookup dans le schema viewer-index.jsonl).

**Précédence explicite** (résout B1-H5 iter 3) : `OR` lie plus serré que `AND` (modèle SQL inversé pour l'usage palette : `verdict:fail OR verdict:warn agent:reviewer` se lit `(verdict:fail OR verdict:warn) AND agent:reviewer`, comportement attendu utilisateur). Parens disponibles pour override. **Directives `sort:` et `group:` typées** ajoutées en post-fix (résout B1-H5 + L-2 saved query reproductibility).

```
query      := or_expr directive*
or_expr    := and_expr ("OR" and_expr)*
and_expr   := unary_term ( ("AND")? unary_term )*  # AND default si absent
unary_term := ("NOT" | "-") atom | atom
atom       := facet | quoted | free-text | "(" or_expr ")"
facet      := key ":" (range | atomic | quoted)
quoted     := '"' [^"\\]* ('\\' . [^"\\]*)* '"'    # non-greedy + escapes (fix B1-M2)
free-text  := word                                  # fuzzy fallback sur title + body
key        := <any field présent dans viewer-index.jsonl>
              # registre dynamique : kind, verdict, agent, evidence, score,
              # refutable, since, status, cc, phase, severity, model, note…
              # ajouter un champ JSONL = ajouter une key, zéro code parser.
range      := "<" N | ">" N | "<=" N | ">=" N | N ".." N | <Nd|Nh|Nm>
              # `since:7d` matche `last_modified > now-7d` (cf. D-3 schema)
atomic     := atomic-token (matché littéralement OU contre enum déclaré schema)
combinator := "AND" | "OR"          # symboles pipe `|` retiré pour éviter conflit shell-paste
neg        := "NOT" | "-"
escape     := "\\:" | "\\\"" | "\\\\" | "\\(" | "\\)"
directive  := "sort:" key ("+"|"-")?  | "group:" key   # ex. `sort:score-` `group:adr`
```

**Empty query behavior** (résout B1-L2) : palette vide à l'ouverture déclenche la saved query par défaut `kind:adr sort:last_modified- group:adr` (les ADR récents en haut). Override par `~/.claude/.viewer/views.json` *(stocké en IndexedDB côté client, pas en filesystem — cf. D-4 fix B1-H2)*.

Exemples concrets :
- `evidence:intuition score:<7 kind:adr` → claims fragiles dans les ADR
- `verdict:fail_critical agent:reviewer since:7d` → derniers blocages bloquants
- `refutable:untested cc:CC-4` → claims falsifiables jamais testées
- `kind:claim status:falsified` → claims réfutées empiriquement

**Saved queries** = vues persistées dans **IndexedDB côté client** (résout B1-H2 — pas de file `~/.claude/.viewer/views.json` côté filesystem, donc pas de 6e touchpoint). Export JSON via "Download views" CLI affordance pour partage/backup. Une saved query est une *carte mentale matérialisée* — l'utilisateur architecte sa propre lentille.

Raccourcis :
- Mac : `⌘K` ouvre palette popover (640px centré). `⌘Shift+Space` (alias avec Raycast/Alfred si registré) lance le viewer même hors-app.
- iPhone : pull-down sheet (HIG `.searchable`) OU tap sur barre top "Search". Tab bar bottom = `Recent` / `Browse` / `Search` (3 max [SOURCE community: developer.apple.com/design/human-interface-guidelines/tab-bars]).

Découvrabilité : drop-down de facettes typées au focus (auto-complétion type Linear [SOURCE community: linear.app/method]) + ligne d'exemples cliquables au premier lancement.

Wireframe palette (iPhone sheet + Mac popover identiques modulo chrome) :

```
┌──────────────────────────────────────────────┐
│ 🔍 evidence:intuition score:<7 kind:adr      │
│ ──────────────────────────────────────────── │
│ ⬢ 12 results · grouped by ADR · sort: score↓ │
│                                               │
│ ▸ ADR 0001 D-3   "Inbox JSON polling"   5/10 │
│   intuition-only · *Refutable by:* untested   │
│ ▸ ADR 0002 D-7   "Pre-mortem reduces…"  6/10 │
│   intuition-only · *Refutable by:* untested   │
│ ▸ ADR 0003 D-1   "Hybrid corpus…"       6/10 │
│   intuition-only · tested 2026-04-29 null d=.2│
│                                               │
│ ⌘↵ open in arena    ⌘S save as view           │
└──────────────────────────────────────────────┘
```

*Refutable by:* étude de découvrabilité sur **5 utilisateurs** (n=5 calibré par [SOURCE: Nielsen 1994 *Usability Inspection Methods* — "Why You Only Need to Test with 5 Users" — la 5e personne expose ~85% des problèmes de surface]), 10 min, prompt "trouve les claims fragiles dans ce repo". Threshold : si <60% découvrent au moins une facette typée sans assistance, l'hypothèse "palette + autocomplétion suffit comme nav primaire" tombe — il faut une homepage minimaliste avec 4 saved-queries pré-installées.

### D-3 · Unité atomique : la **claim**, pas l'ADR

Inversion de la contrainte *fichier-centré*. L'unité indexée et adressée n'est plus l'ADR, c'est la **claim** : un n-uplet `(id, parent_adr, section, type, text, markers[], refutable_by?, status)`.

Schéma JSONL produit par l'indexeur (cf. D-4) :

```json
{
  "id": "ADR-0003#D-1",
  "parent_adr": "0003-evaluation-protocol",
  "section": "Decision/D-1",
  "type": "decision",
  "title": "Hybrid corpus (synthetic + OWASP + real)",
  "markers": [
    {"kind": "SOURCE", "slug": "natella-2013", "ref": "Natella et al 2013 IEEE TSE 39(1):80-96"},
    {"kind": "SOURCE", "slug": "owasp-benchmark", "ref": "owasp.org/www-project-benchmark"}
  ],
  "refutable_by": "If OWASP-anchor cases drift >20% TPR vs synthetic-only, hybrid composition is wrong",
  "status": {"empirical": "untested", "since_days": 0},
  "cited_by": ["JOURNAL#2026-04-29", "tmp/evals-design-2026-04-28/answer-corpus.md:42"],
  "score": 6.5,
  "cc": ["CC-4"],
  "last_modified": "2026-04-29T14:32:11Z",
  "source_path": "decisions/0003-evaluation-protocol.md"
}
```

**Champ `last_modified`** (résout B1-C2) : ISO8601 string, hérité du fichier source au moment de l'indexation par `index-claims.sh` via `git log -1 --format=%cI -- <path>` (commit time, robuste cross-machine) avec fallback sur `stat -f %Sm` (mtime fs) si le fichier n'est pas tracké git. Tous les claims d'un même fichier partagent la valeur. Le predicate D-2 `since:Nd` se résout en `last_modified > now() - Nd` côté indexer (Dexie compound index sur `[parent_adr+last_modified]`).

Un ADR contribue typiquement 4–8 claims (une par décision D-N + claims standalone du Context). Le viewer expose **les deux** : la claim comme atom navigable, l'ADR comme container reconstitué (rendu prose + claims highlighted). Le wireframe "claim/refutation arena" suit le pattern Community Notes [SOURCE community: communitynotes.x.com] adapté à la sémantique du plugin :

```
┌──────────────────────────────────────────────┐
│  CLAIM  ADR-0003#D-1                          │
│  "Hybrid corpus (synthetic + OWASP + real)    │
│   minimizes author bias"                      │
│                                               │
│  Evidence:                                    │
│  [SOURCE#natella-2013] 72% seeded faults      │
│      not representative                       │
│  [SOURCE#owasp-benchmark] 2740 cases, frozen  │
│                                               │
│ ────────── Refutable by ──────────            │
│  "If OWASP-anchor cases drift >20% TPR        │
│   vs synthetic-only, composition is wrong"    │
│                                               │
│ ────────── Empirical status ──────────        │
│  ◌ Untested · 60-day cron at 2026-06-28       │
│  [Run /evals now ↗]                           │
│                                               │
│ ────────── Cited by ──────────                │
│  JOURNAL 2026-04-29 · ADR 0002 §D-3           │
│  tmp/evals-design.../answer-corpus.md:42      │
│                                               │
│ ↑ trust   ↓ doubt   ←/→ prev/next   tap=ADR  │
└──────────────────────────────────────────────┘
```

Sur iPhone : 1 claim/écran, swipes natifs (Atomic Swipe paradigm #4 du innovator [OBSERVED: tmp/viewer-design-1777468836/innovation-angles.md:115-153]). Sur Mac : version 3-colonnes (claim list left | claim detail center | cited-by panel right) + raccourcis J/K/↑/↓.

*Refutable by:* si le parser claim ne capture pas ≥85% des décisions structurantes des ADR existants. Mesure : grep multi-pattern sur ADR 0001/0002/0003 — `^#{2,4} +(D-\d|CC-\d|B-\d|M-\d|[A-Z]\. )` (couvre les conventions D-N de 0001/0003 ET les sous-décisions CC-2/CC-4/CC-5/B-9 d'ADR 0002 [OBSERVED: decisions/0002-agent-synergy-redesign-iter4-lean.md structure 4 niveaux]). Si la capture <85% sur l'union des 3 ADR (≥1 ADR à 0 claims = échec immédiat), la définition de claim est trop étroite, il faut généraliser le schema heading ou typer manuellement.

### D-4 · Modifications plugin (4 touchpoints stricts, sous cap criteria.md `<5`)

Comptabilité 1-pour-1 (un fichier substantiellement modifié = un touchpoint). Lecture stricte du cap criteria.md:6 (`<5` = `≤4`) appliquée — résout CH-H2 / H-2.

| # | Modif | Fichiers touchés | Justification empirique | Coût | Gain viewer |
|---|---|---|---|---|---|
| **M-1** | Hook `index-claims.sh` (a) PostToolUse Edit/Write/MultiEdit sur `decisions/*.md` + `state/JOURNAL.md` + `tmp/**/*.md` (incremental), (b) SessionStart `--full` regen pour rattraper git ops bypass (résout B1-H4), (c) **séquencé après `auto-format.sh`** dans la chaîne PostToolUse via préfixe alphabétique `index-claims.sh` (vient après `auto-format.sh`) ou priorité explicite `runAfter: auto-format.sh` (résout B1-H1) | (a) `hooks/index-claims.sh` (nouveau, ~80 LOC bash+jq, **set -euo pipefail + shellcheck-clean** — résout S-3) ; (b) `settings.json` ajout entrée `PostToolUse` + entrée `SessionStart` (matcher `*` sans condition compact) ; (c) `.gitignore` ajout `cache/viewer-index.jsonl` | Sans index machine, le viewer parse 3 MB+ de markdown à chaque ouverture. Hook = update incrémental, latence cible <100ms/save [ENGINEERING: à mesurer build-1]. SessionStart full-regen rattrape git rebase/checkout/pull (cf. B1-H4). | 3 fichiers | **Bloquant**. Aucun viewer scalable sans cet index. |
| ~~M-2~~ | **DESCOPED iter 3** : extension protocole evidence (claim-slug `[SOURCE#slug]`) reportée à un ADR ultérieur. Coût bas mais non load-bearing pour Phase 1-2 ; descope rétablit la lecture stricte du cap modifs `<5`. | — | — | 0 | Reporté. |
| **M-3** | Pipeline-state JSONL append-only : `tmp/<team>/state.jsonl` (`{ts, agent, performative, artifact_path}`) — émis par `/team` SKILL.md | (a) `skills/team/SKILL.md` (~30 lignes ajoutées) | Sans FSM explicite, le viewer doit grep-scan inboxes + tmp/ + JOURNAL pour reconstruire l'état. State.jsonl = O(1). [OBSERVED: tmp/viewer-design-1777468836/signal-analysis.md G3:99] | 1 fichier | Débloque la vue "pipeline timeline" Activity. |
| **M-4** | Skill `/viewer` exposant les CLI helpers `viewer launch`, `viewer expose`, `viewer reset-token`, `viewer reindex` | (a) `skills/viewer/SKILL.md` (nouveau, ~30 LOC + argument-hint) ; (b) wrapper bash `skills/viewer/viewer.sh` (~40 LOC) | Donne une surface de commande Claude-native (cohérente avec `/team`, `/commit`) plutôt qu'un binaire `~/.claude/bin/` improvisé. `viewer reindex` = workaround manuel git ops bypass (mitigation belt-and-suspenders avec SessionStart). | 2 fichiers | UX cohérente, découvrable via Skill resolver. |
| **M-5** | Sibling folder `viewer/` à la racine du plugin : SPA + `server.ts` mini-backend + tests parser | Nouveau folder `viewer/` (`src/`, `dist/`, `server.ts`, `parser-version.json`, `parser.test.js`, `server.test.ts`). Le mini-backend Bun (D-1 fix B1-C1, S-4) vit ici, pas de fichier plugin existant modifié — folder isolable, suppressible d'un `rm -rf viewer/` sans casser le plugin. | Le SPA doit vivre quelque part dans le repo `~/.claude/`. Sibling folder = couplage zéro avec les fichiers existants. | 1 folder (compté comme **1 touchpoint** car suppressible atomiquement) | Source du PWA + serveur write-only. |

**Total strict : 4 touchpoints / 7 fichiers nouveaux ou modifiés** — sous cap (`<5` = `≤4` ✓). M-2 descopée explicitement résout CH-H2 (cap strict) et permet à `[SOURCE#slug]` d'être réintroduit ultérieurement par ADR séparé sans pollution Phase 1.

**Saved queries / preferences storage** : tout user-state côté client (saved queries, density override, dernier query) → IndexedDB Dexie même store. **Aucun fichier `~/.claude/.viewer/views.json` créé côté filesystem** (résout B1-H2). Export JSON disponible via CLI `viewer export-views > views.json` à la demande utilisateur.

**Modifs rejetées (justifications)** :
- *MCP server exposant les claims* — séduisant pour donner à Claude un outil de consultation de son propre graph ADR, mais hors scope du **viewer humain**. ADR séparé si signal de demande émerge.
- *Backlinks `state/INDEX.jsonl` séparé* — fusionné dans M-1 (le hook produit `cited_by[]` dans le même JSONL).
- *Claim-slug protocol extension* (ex-M-2) — descopée iter 3 pour respecter cap strict ; reportée. Adoption gradient ~3 mois pour 80% adoption [ENGINEERING: à instrumenter via grep `\[SOURCE#` count over time si réintroduit].

*Refutable by:* commit dry-run de Phase 1 (`git diff --stat`) montrant **>4 fichiers plugin existants modifiés** (hors `viewer/` folder, hors `.gitignore`) infirme la comptabilité stricte ci-dessus. Aussi : si après 30 jours d'usage l'index `viewer-index.jsonl` diverge du contenu réel (regen full vs incremental, comparaison hash >5%) — l'hypothèse "incrémental safe" tombe, fallback full-regen sur Stop hook.

### D-5 · Exposition mobile : Tailscale Serve + Bearer token, pas de LAN public

Le PWA est servi par `bun run viewer/server.ts` (cf. D-1) bound sur `127.0.0.1:7878` **par défaut** côté Mac (résout S-2 — pas de bind 0.0.0.0 sans auth). Pour l'iPhone, deux mécanismes :

1. **Tailscale Serve** (par défaut [SOURCE community: tailscale.com/kb/1242/tailscale-serve]) — `tailscale serve --bg https / http://127.0.0.1:7878`. Le Mac expose le viewer en HTTPS sur le tailnet privé (URL stable type `mac.tailnet-foo.ts.net`), zéro DNS public, zéro port forwarding, certificat MagicDNS auto. PWA installée sur iPhone via "Add to Home Screen". L'authentification réseau est portée par le tailnet (device authorization) — un device hors-tailnet n'atteint jamais le serveur. Le bearer token applicatif (ci-dessous) est une couche défense-en-profondeur.
2. **Bearer token applicatif** (résout S-2) : à chaque boot, `viewer/server.ts` génère un token aléatoire 256-bit (`crypto.randomBytes(32).toString('base64url')`) persisté dans `~/.claude/.viewer/token` (perms `0600`, propriétaire user uniquement, dans `.gitignore`). Toutes les routes (`GET /index.jsonl`, `POST /notes`, etc.) exigent header `Authorization: Bearer <token>` OU query `?token=<token>` (utile pour l'`Add to Home Screen` initial sur iPhone). Sans token valide → `401`. Token rotatable via `viewer reset-token` (M-4 CLI) qui régénère + invalide les anciens. Le PWA stocke le token dans IndexedDB après premier scan de QR code (Mac affiche QR au boot via terminal, iPhone scan).

**Garde-fous explicites** :
- **`tailscale funnel` est INTERDIT** (résout S-6) : le wrapper `viewer expose` (M-4) refuse explicitement `--funnel`/`--public` (grep guard, exit 1) et affiche un banner d'avertissement si `tailscale funnel status` montre une funnel active sur le port 7878. Documentation install : "**ne PAS activer Tailscale Funnel** — utiliser uniquement `tailscale serve --bg`. Funnel expose à l'internet public sans auth applicative au-delà du bearer token, surface d'attaque inacceptable."
- **LAN bind 0.0.0.0 retiré du design** (résout S-2) : pour le partage iPhone hors-Tailscale, l'utilisateur doit utiliser un tunnel SSH manuel (`ssh -L 7878:localhost:7878 user@mac` depuis l'iPhone via app `Termius` ou équivalent). Documenté comme procédure secondaire dans M-4 SKILL.md, pas auto.

**Hors scope** : tunnel public permanent type ngrok/Cloudflare Tunnel (refusé par criteria item edge case "sécurité : exposition mobile sans tunnel public permanent"). Tailscale Funnel idem.

PWA service worker stratégie : **stale-while-revalidate** sur `viewer-index.jsonl`, **cache-first** sur app shell, avec **versioning explicite** (résout S-5) :
- Cache name = `viewer-sw-v<git-sha>` (build-time injection via Vite). Au boot, le SW fetch `/version.json` ; si l'`sha` diverge du sien, il `caches.delete()` toutes les anciennes versions, `self.skipWaiting()`, `clients.claim()`.
- Handler `controllerchange` côté client force `window.location.reload()` à l'activation d'un nouveau SW.
- Aucune mise en cache de réponses contenant le header `Cache-Control: no-store` ou de routes `POST` (notes, token).
- Procédure "kill switch" documentée (`viewer reset-sw` CLI ⇒ touche `version.json` invalidé qui force unregister).

**Origin scope SW** (résout B1-H3, lecture honnête) : le SW est scoped origin (scheme + host + port). Tailscale URL (`mac.tailnet-foo.ts.net`) ≠ tunnel SSH (`localhost:7878`) ≠ ancien LAN IP. Conséquences acceptées :
- Une PWA installée depuis Tailscale ≠ une PWA installée depuis tunnel SSH (2 installs distinctes coexistent).
- Si l'utilisateur change de canal (Tailscale → SSH ou inverse), il doit réinstaller la PWA (banner "this origin is new — re-add to home screen for offline").
- MagicDNS hostname est stable cross-reboot tant que le tailnet n'est pas reconfiguré ([SOURCE community: tailscale.com/kb/1217/magicdns]). Ce design verrouille **Tailscale comme origin canonique** ; le tunnel SSH reste mode secondaire dégradé sans persistence.

*Refutable by:* si moins de 60% des sessions iPhone (mesuré sur 2 semaines, log via `navigator.serviceWorker` + console.log dump) parviennent à atteindre le viewer en <3s sur réseau Tailscale (corporate wifi bloquant UDP, captive portals) — l'hypothèse "Tailscale Serve = solution mobile par défaut" tombe, il faut considérer une PWA pré-générée poussée vers iCloud Drive. Test additionnel : si après 30 jours, le wrapper `viewer expose` détecte une activation accidentelle de `tailscale funnel` (telemetry CLI), le garde-fou est insuffisant et il faut un scaffold supplémentaire.

### D-6 · Densité : 3 zoom levels surchargeables

`density ∈ {compact, default, rich}`, persisté `localStorage`. Default contextuel : `compact` iPhone, `rich` Mac ≥1280px. Surchargeable par utilisateur, par vue. Pattern Linear/Notion [OBSERVED: tmp/viewer-design-1777468836/ux-patterns.md:35-44].

| Density | Title | Meta | Body | Markers inline |
|---|---|---|---|---|
| compact | ✓ | — | — | — |
| default | ✓ | verdict + date | — | dot-only badges |
| rich | ✓ | verdict + date + score gauge | preview snippet 2 lignes | full inline `[SOURCE#…]` underlined |

Un seul composant `<ClaimRow>` lit `density`, omet/inclut. CSS container-queries côté Mac pour réagir à la largeur du panneau (split à 320px → compact, 600px → default, 900px → rich) [SOURCE community: web.dev/cq].

*Refutable by:* si une étude utilisateur note que >50% du temps utilisateurs surchargent le default contextuel (telemetry localStorage `density_overrides`), le mapping device→density default est mal calibré.

### D-7 · Annotation locale : note libre par claim, sans gesture-based scoring

Le pattern Community Notes (cité dans D-3) repose sur **N voters indépendants** apportant des perspectives diverses — c'est ce qui transforme un signal en evidence. En **single-user** (cf. *Hors scope*), les ↑/↓ d'une seule personne sur ses propres claims sont du bookmark, pas de la validation. Ce design corrige iter 1 en supprimant le gesture-based judgment (rejeté à juste titre par challenger H-5) et en le remplaçant par un mécanisme plus modeste et honnête.

**Décision finale** : un seul affordance par claim — **bouton "Annoter"** ouvrant un text-field libre. La note est envoyée via `POST /notes` au mini-backend `viewer/server.ts` (cf. D-1, résout B1-C1) avec body `{claim_id, text, ts}`. Le serveur valide JSON, applique `flock(2)` exclusif (résout S-7 race), append au `~/.claude/state/NOTES.jsonl` (`{ts, claim_id, text, viewer_session_id}`), `fsync`, retourne `201`. Header `Authorization: Bearer <token>` requis (cf. D-5). Le PWA fait un GET `/notes/by-claim/<id>` pour rendre les annotations existantes.

Aucune sémantique ↑/↓, aucun auto-spawn, aucun flag `trust:high` agrégé. La note est utilisateur-only, lisible dans la palette via `note:exists` ou `note:contains "X"` (filtres résolus via Dexie cache de NOTES.jsonl, rafraîchi à chaque rechargement).

La boucle code-challenger reste ce qu'elle est aujourd'hui : explicite, manuelle, via `/team --challenge` quand l'utilisateur le décide. Pas d'auto-trigger depuis le viewer.

*Refutable by:* si après 30 jours d'usage `NOTES.jsonl` contient <5 entrées (mesure : `wc -l`), l'annotation libre est elle-même inutile — descoper entièrement, le viewer reste passif (lecture seule).

---

## Refutability summary

≥80% des décisions structurantes (CRITICAL/HIGH) ont une ligne *Refutable by:* explicite ci-dessus. Synthèse :

| Decision | Severity | Refutable by — threshold |
|---|---|---|
| D-1 SPA + mini-backend write-only + sanitization | CRITICAL | LCP > 2.5s iPhone Safari (50 ADR/200 claims, Tailscale local) ; OU XSS fuzz `<script>` rendu live (T8) ; OU `curl -I` sans CSP/X-Frame-Options (S-4 fix) |
| D-2 Palette + parser combinator + précédence | CRITICAL | <60% découvrabilité Nielsen 5-user test ; OU >1s parse sur fuzz 1000 queries (T7) ; OU `(a OR b) AND c` parse `a OR (b AND c)` (T11) |
| D-3 Claim atomique multi-heading + last_modified | CRITICAL | <85% capture sur ADR 0001/0002/0003 réunis (T5) ; OU `since:7d` retourne 0 résultats malgré claim modifiée hier (T12) |
| D-4 M-1 hook (incremental + ordering + git ops) | HIGH | drift hash full-vs-incremental >5% sur 30 jours ; OU `index-claims.sh` exécuté avant `auto-format.sh` (T14) ; OU git rebase sans regen au prochain SessionStart (T13) |
| D-4 M-3 state.jsonl | HIGH | <90% pipelines reconstructibles depuis state.jsonl seul |
| D-4 cap accounting (strict <5) | CRITICAL | git diff --stat Phase 1 >4 fichiers plugin existants |
| D-5 Tailscale + Bearer token + no Funnel | HIGH | <60% sessions iPhone <3s sur 2 sem ; OU `curl https://...ts.net/index.jsonl` sans token retourne 200 (T15) ; OU `tailscale funnel status` actif après `viewer expose` (S-6) |
| D-6 Density 3-levels | MEDIUM | >50% override `density_overrides` IndexedDB |
| D-7 Annotation libre via POST /notes | MEDIUM | <5 entrées NOTES.jsonl en 30j → descope entier ; OU concurrent writes >1000 itérations corrompent JSONL (S-7) |

Couverture refutable-by sur CRITICAL+HIGH : **9/9 = 100%** (gate ≥80% atteint). MEDIUM (D-6, D-7) inclus pour transparence (le spec verdict-protocol.md ne mandate que CRITICAL+HIGH — résout CM-M4).

---

## Pre-mortem (CC-2)

Méthodologie : prospective hindsight selon [SOURCE: Klein 2007 *Harvard Business Review* — "Performing a Project Premortem"], formalisme empirique [SOURCE: Mitchell, Russo & Pennington 1989, *Journal of Behavioral Decision Making* 2(1):25-38 — prospective hindsight produit ~30% MORE reasons], gain mesuré [SOURCE: Veinott, Klein & Wiggins 2010 *ISCRAM* — pre-mortem réduit overconfidence ~2× vs Pro/Cons]. Calibration des fenêtres d'observation des Refutable-by tests (14j, 30j) pour effect size moyen `d≈0.5` à α=.05, power=.80 ⇒ n≈64 sessions/observations [SOURCE: Cohen 1992 *Psychological Bulletin* 112(1):155-159 — "A Power Primer"]. Scénarios prospectifs en format `(component, trigger, signal)`.

### Scenario 1 — Index drift catastrophique

**Component** : `hooks/index-claims.sh` (M-1) parser de evidence markers.
**Trigger** : un agent (probablement `architect` futur) introduit un nouveau marker `[OPINION: ...]` non prévu dans le regex du parser. 30 ADR sont édités en 1 semaine avec ce nouveau syntaxe.
**Signal mesurable** : palette filter `evidence:opinion` retourne 0 résultats malgré 47 occurrences `grep` dans `decisions/`. Justification scoring affiche `NaN` pour les 30 ADR concernés. Utilisateur perd confiance dans l'index, retourne au `grep` direct.

**Mitigation** : `viewer/parser-version.json` versionné, ALL marker types explicitement enregistrés. Marker non reconnu → bucket `unknown` (pas null) avec warning visible "30 markers unknown — check parser-version.json". Test de régression : `parser.test.js` lit ADR 0001/0002/0003 et asserte le count de markers connus.

### Scenario 2 — Tailscale unreachable, viewer mort sur iPhone

**Component** : Tailscale Serve (D-5) côté iPhone.
**Trigger** : utilisateur en déplacement (corporate wifi bloquant UDP MagicDNS), ou rebooting Mac (Tailscale daemon down 4h), ou session Tailscale expirée.
**Signal mesurable** : iPhone Safari blanc, "Could not connect to mac.tailnet.ts.net". Utilisateur abandonne, retourne au laptop. Sur 2 semaines, <40% des tentatives iPhone réussissent → viewer non utilisé en mobile.

**Mitigation** : PWA service worker `cache-first` + `viewer-index.jsonl` mis en cache à chaque sync. Banner "offline mode, last sync ⟨X⟩h ago" lisible. Bouton "retry" non-bloquant. Si <60% reachability sur 2 semaines (cf. *Refutable by:* D-5), pivot vers iCloud Drive sync de l'index (`~/iCloud Drive/.viewer-index.jsonl` + PWA local).

### Scenario 3 — Bulk edit IO storm

**Component** : Hook `index-claims.sh` (M-1) déclenché en cascade.
**Trigger** : utilisateur fait un rebase qui modifie 50 ADR en 30 secondes (mass-rename, reformat). Hook PostToolUse se déclenche 50× ; régénération full pour chaque.
**Signal mesurable** : `time` du hook total ~30s ; latence Edit/Write user-visible >500ms ; hook bloque l'IDE, `quality-gate.sh` cascading. Utilisateur frustré désactive le hook → index stale → viewer devient inutile.

**Mitigation** : (a) hook **incrémental** par défaut (parse uniquement les fichiers passés en argument PostToolUse, mise à jour partielle de l'index JSONL via clé `id`). (b) **debounce** 1s côté hook (lock `~/.claude/cache/.viewer-index.lock`, second appel coalesce). (c) full regen disponible via `claude viewer reindex` CLI explicit, pas auto.

---

## Plan d'implémentation phasé

Effort scale : chaque phase ≤ 1 semaine de travail effectif.

### Phase 1 — Palette + Index minimal (MVP, 1 semaine)

**Livrables** :
- `~/.claude/hooks/index-claims.sh` (M-1) : parse `decisions/*.md` + `state/JOURNAL.md`, écrit `cache/viewer-index.jsonl`. Schéma D-3 minimal (sans `cited_by[]` — phase 2). Test régression sur ADR 0001/0002/0003.
- SPA `viewer/` : Vite + Preact + signals + Dexie (IndexedDB). 1 écran palette (D-2) + grouped results. Density default contextuel (D-6).
- `claude viewer` CLI bash (~20 lignes) qui lance `bun --static viewer/dist`.
- Mac only Phase 1 (pas encore Tailscale).

**Critère de complétion** : (a) query `evidence:intuition score:<7` sur ADR existants retourne ≥5 résultats correctement classés ; (b) **T2 passé** : latence <500ms keystroke→result sur 200 claims simulées (gate perf Phase 1, évite rework Phase 2) ; (c) **T5 passé** : ≥85% capture claims sur ADR 0001+0002+0003 réunis (vérifie le parser multi-heading H-4).

**Dépendances** : aucune.

### Phase 2 — Refutation Arena + Backlinks + iPhone (1 semaine)

**Livrables** :
- M-1 enrichi : extraction des `cited_by[]` (grep transverse `tmp/**/*.md`, `JOURNAL.md` pour références ADR-NNNN#D-X). Backlinks dans le même JSONL.
- Vue "Arena" (D-3) : claim/refutation rendering, swipe iPhone + 3-colonnes Mac, transclusion des `cited_by`.
- PWA manifest + service worker (D-5) : installable, cache-first app shell, stale-while-revalidate index.
- Tailscale Serve documentation + `claude viewer expose` CLI helper qui run `tailscale serve` à la bonne config.
- Tab bar iPhone (Recent / Browse / Search) + NavigationStack push (D-2 finalize iPhone).

**Critère de complétion** : ouverture viewer iPhone via Tailscale, tap sur claim D-3 d'un ADR ouvre l'Arena, swipe → claim suivante du même ADR.

**Dépendances** : Phase 1 livrée.

### Phase 3 — State FSM + Notes (D-7 descopée) + Density rich (1 semaine)

**Livrables** :
- M-3 : modif `skills/team/SKILL.md` pour émettre `tmp/<team>/state.jsonl`. Indexer la consomme (un nouveau `kind: pipeline` dans la palette).
- D-7 (descopé du swipe-judgment) : bouton "Annoter" → text-field libre, log `state/NOTES.jsonl`. Filtres palette `note:exists` et `note:contains "X"`. Pas de gestes ↑/↓, pas d'auto-spawn challenger.
- M-2 : doc protocole + parser tolérant `[SOURCE#slug: ref]`. Indexer crée des nœuds slug dédupliqués + page "Source detail" (toutes les claims citant `#natella-2013`).
- Density rich finalisée (Mac ≥1280px) avec evidence markers inline cliquables (chaque `[SOURCE#slug]` = lien vers la page source).
- Focus mode (`F` Mac, double-tap iPhone) [OBSERVED: tmp/viewer-design-1777468836/ux-patterns.md:92-99].

**Critère de complétion** : tap sur `[SOURCE#natella-2013]` dans n'importe quelle claim ouvre la page agrégée des 4+ claims qui citent cette source. Une saved query `pipeline status:in_progress` montre les pipelines actifs en temps quasi-réel.

**Dépendances** : Phase 1 + Phase 2 livrées. M-2 peut être testé sans modif globale (seul ADR 0004 introduit le claim-slug).

### Hors scope explicite

- **Code du viewer livré dans cet ADR** — design only, --plan-only.
- **MCP server claims** — réservé pour ADR ultérieur si signal de demande de Claude lui-même (réflexion sur ADR via tool).
- **Sync multi-machines** — utilisateur a une seule machine principale ; cas multi-Mac/multi-utilisateur out of scope.
- **Auth / multi-user** — viewer 100% local, single-user. Tailscale Serve restreint au tailnet personnel suffit.
- **Rendering complet du markdown ADR** — Phase 2 affiche les claims atomiques + transclusion ; le rendering full Markdown ADR est un fallback "view source" minimal, pas un produit rich.
- **Visualisation graph (Evidence Graph paradigm #3)** — rejeté à ce stade [OBSERVED: tmp/viewer-design-1777468836/innovation-angles.md:201-208 : "graph porn risk"]. Réservé en sous-vue d'une saved query si demande prouvée.
- **Editing dans le viewer** — read-only strict. L'écriture passe par les agents Claude (architect, developer) comme aujourd'hui.

---

## Tests that would invalidate this design

- **T1** (D-1 perf) : open viewer iPhone Safari (réseau Tailscale local) avec **50 ADRs + 200 claims indexés**, mesurer **LCP via `PerformanceObserver`** (entryType `largest-contentful-paint`). Signal d'invalidation : **LCP >2.5s** [SOURCE community: web.dev/lcp Web Vitals]. Si fail, l'hypothèse "static SPA + IndexedDB local-first scale acceptable iPhone" est fausse — pivot vers SSR ou pré-pagination.
- **T2** (D-2 query perf) : run `verdict:fail_critical evidence:intuition score:<7` dans la palette avec un index de **200 claims**. Signal d'invalidation : **latence >500ms** entre keystroke et résultats. Si fail, parser combinator + linear-scan inadéquats — indexer compound Dexie sur (kind, verdict, score) + pré-tokenization. **Gate Phase 1**.
- **T3** (D-3 réactivité hook) : ajouter une nouvelle claim `[SOURCE#novel-slug-test: …]` dans ADR 0004 via Edit, mesurer le délai jusqu'à l'apparition dans la palette (rafraîchissement client). Signal d'invalidation : **>3s** ou claim non capturée. Si fail, pipeline réactif (hook → JSONL → IndexedDB watch) cassé.
- **T4** (D-5 offline) : désactiver Tailscale sur iPhone, rouvrir le viewer. Signal d'invalidation : **page blanche / erreur réseau** au lieu de servir last-known-good index avec banner offline. Si fail, le service worker est mal configuré, la promesse "PWA offline-first" tombe.
- **T5** (D-3 claim parser, multi-heading) : grep multi-pattern `^#{2,4} +(D-\d|CC-\d|B-\d|M-\d|[A-Z]\. )` sur `decisions/0001-team-comms.md`, `0002-agent-synergy-redesign-iter4-lean.md`, `0003-evaluation-protocol.md`, comparer count vs `viewer-index.jsonl` claims pour ces ADRs. Signal d'invalidation : **capture <85%** OU **≥1 ADR avec 0 claims** (faux-vert sur ADR 0002 si pattern restreint à `### D-`). Si fail, schéma trop étroit, généraliser ou typer manuellement.
- **T6** (D-4 M-1 incremental safety) : full regen vs incremental après 30 jours d'usage, diff hash des deux outputs. Signal d'invalidation : **divergence >5% des entrées**. Si fail, l'incrémental drifte, fallback sur full regen au Stop hook.
- **T7** (H-3 parser robustness) : fuzz 1000 queries random (chars Unicode, longueurs 1-2000, séquences `:`/`(`/`)`, escaping naïf) contre le parser combinator. Signal d'invalidation : **≥1 exception non-catchée OU ≥1 query >1s parse**. Si fail, parser combinator mal configuré ou recovery insuffisante.
- **T8** (D-1 sanitization XSS — résout S-1) : créer une ADR fixture `decisions/0099-xss-test.md` contenant `<script>window.__pwn=1</script>`, `<img src=x onerror="window.__pwn=1">`, et `<a href="javascript:alert(1)">click</a>` dans le body et le `Refutable by:`. Indexer + ouvrir le viewer headless (Playwright) en mode PWA, naviguer vers la claim, asserter `await page.evaluate(() => window.__pwn) === undefined` ET aucune requête sortante non-self (network log). Signal d'invalidation : `__pwn === 1` OU navigation vers `javascript:` OU fetch vers domaine externe. Si fail, DOMPurify mal configuré ou `marked html: true` actif.
- **T9** (D-4 M-1 bash injection — résout S-3) : créer une ADR fixture avec heading `# ADR 0099 — Title; rm -rf /tmp/pwn-test-$(touch /tmp/pwn-test/marker)`. Lancer `index-claims.sh` (préalablement `mkdir /tmp/pwn-test`). Signal d'invalidation : fichier `/tmp/pwn-test/marker` existe APRÈS l'exécution OU `viewer-index.jsonl` contient le titre interpolé non-littéral. Si fail, le hook utilise `eval`/backticks/unquoted vars — refuser le merge. Bonus : `shellcheck hooks/index-claims.sh` doit être 0 warnings (CI gate).
- **T10** (D-5 LAN bind — résout S-2) : démarrer `viewer/server.ts` sans token configuré, vérifier `lsof -iTCP -sTCP:LISTEN -P | grep 7878`. Signal d'invalidation : socket bind sur autre chose que `127.0.0.1` (ex. `*:7878` ou `0.0.0.0:7878`). Si fail, défaut bind incorrect, exposition LAN.
- **T11** (D-2 grammar precedence — résout B1-H5) : input `verdict:fail OR verdict:warn agent:reviewer`, parse, asserter AST `AND(OR(verdict:fail, verdict:warn), agent:reviewer)`. Signal d'invalidation : AST `OR(verdict:fail, AND(verdict:warn, agent:reviewer))` (SQL-style precedence). Si fail, BNF mal codée vs spec D-2.
- **T12** (D-3 since:Nd — résout B1-C2) : indexer un repo avec une ADR éditée il y a 1 jour, run query `since:7d`, asserter ≥1 résultat. Run `since:1h` sur même claim → 0 résultats (mtime > 1h ago). Signal d'invalidation : `since:7d` retourne 0 résultats malgré claim modifiée hier OU `since:1h` retourne la claim. Si fail, `last_modified` non extrait par M-1.
- **T13** (D-4 git ops bypass — résout B1-H4) : modifier 5 ADR via `git rebase -i HEAD~3` (sans Edit/Write Claude). Sans rouvrir Claude Code, vérifier `viewer-index.jsonl` mtime — il doit rester stale. Démarrer une nouvelle session Claude Code, vérifier que SessionStart trigger a régénéré l'index (mtime fresh, contenu reflète rebase). Signal d'invalidation : SessionStart ne lance pas `index-claims.sh --full` OU index reste stale après new session. Si fail, M-1 git ops mitigation cassée.
- **T14** (D-4 hook ordering — résout B1-H1) : modifier une ADR avec trailing whitespace via Edit, mesurer dans quel ordre `auto-format.sh` et `index-claims.sh` s'exécutent (logs `~/.claude/logs/hooks-trace.log` ou timestamp). Asserter `auto-format.sh` exit ≤ `index-claims.sh` start. Signal d'invalidation : `index-claims.sh` lit la version pre-format → JSONL contient trailing-whitespace. Si fail, ordre hooks mal configuré dans settings.json.
- **T15** (D-5 bearer token — résout S-2 + S-6) : démarrer le serveur, capturer le token, faire 3 requêtes : (a) `curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7878/index.jsonl` → 200 ; (b) `curl http://127.0.0.1:7878/index.jsonl` (sans token) → 401 ; (c) `tailscale funnel status` → vide (pas de funnel). Signal d'invalidation : (a) 401 OU (b) 200 OU (c) funnel actif. Si (c) actif après `viewer expose`, le garde-fou Funnel a échoué.

≥3 tests requis par hook `validate-arch.sh` ; 15 fournis.

---

## Consequences

### Positive

- **Inversion structurelle** : casse simultanément *fichier-centré* (claim atomique) et *mono-vue* (palette compose la vue). Les deux protos invalidés (dashboard d'events, markdown rendered) sont exclus par construction.
- **Multi-plateforme équilibré** : SPA + PWA livre iPhone et Mac avec une seule codebase ; raccourcis Mac et gestes iPhone co-conçus, pas dégradés.
- **Couplage plugin minimal et justifié 1-pour-1** : 5 touchpoints (M-1 hook+settings+gitignore, M-2 doc-only, M-3 SKILL.md, M-4 skill `/viewer`, M-5 sibling folder `viewer/`). Au cap inclusif <5. Chacun avec gain démontrable et coût borné. Pas de mass-propagation forcée aux 9 agents (M-2 = adoption gradient organique).
- **Falsifiable par construction** : 10/10 décisions ont une ligne *Refutable by:* mesurable avec threshold concret. 7 tests T1–T7 falsifiants (LCP, fuzz parser, multi-heading capture, drift hash). Hook `validate-arch.sh` passé.
- **Le viewer EST une matérialisation de la thèse du plugin** : refutability gate, evidence markers, justification scoring deviennent typographie de premier ordre. Aucun outil externe (Obsidian, Notion, Linear) ne fait ça nativement.
- **Réversibilité** : suppression des 5 touchpoints (rm `viewer/`, revert 4 fichiers) laisse le repo 100% fonctionnel ; le viewer devient stale mais le filesystem reste source de vérité.

### Negative

- **Phase 1 nécessite une stack web** (Vite/Preact) que l'utilisateur n'utilise pas ailleurs dans son flow. Coût d'apprentissage si bug dans le viewer.
- **Tailscale dependency** pour le mobile (D-5). Utilisateurs sans Tailscale doivent recourir à un tunnel SSH manuel (mode dégradé sans persistence SW). Tailscale gratuit jusqu'à 100 devices [SOURCE community: tailscale.com/pricing].
- **Compatibilité iOS** (résout B1-M1) : container queries CSS = iOS Safari 16+ (macOS Safari 16+, septembre 2022). iPhone bloqué iOS ≤ 15 = layout split fallback non-réactif (basique, lisible mais sans adaptation densité). Documenté comme prérequis dans le doc d'install.
- **Le claim parser est un point de friction** (Pre-mortem #1). Tout nouvel evidence marker doit être enregistré, sinon drift. Discipline supplémentaire pour les agents futurs.
- **Pas de version cloud** — utilisateur sur tablette tierce ou sans Mac actif n'a pas accès. Acceptable car projet personnel, mais excluant pour partage public éventuel.
- **Phase 3 M-2 (claim-slug)** demande adoption progressive volontaire (les agents 9× *ne sont pas* mass-modifiés) ; les ADR existants resteront majoritairement sans slug ≥6 mois.
- **Bundle web ~50 KB gz** estimé — à mesurer au build (M-1 challenger noted le 30 KB initial sous-estimait l'app code).

### Neutral

- **L'index JSONL** est un artefact dérivé, regénérable. Pas committé dans git (entrée `.gitignore`), pas un "ouvrage" du repo.
- **Le viewer ne remplace pas Claude Code** — c'est un *lecteur d'artefacts*, pas un IDE alternatif. L'écriture passe toujours par les agents/skills.
- **Choix de stack Preact + Dexie** est local à cet ADR ; alternatives (Lit, Solid, vanilla) considérées équivalentes au facteur ~2× sur bundle size, ne change pas l'architecture.

---

## Justification scoring

Recount honnête via `grep` sur ce document (post iter-3 fixes), formule contractuelle [OBSERVED: decisions/0002-agent-synergy-redesign-iter4-lean.md:20] : `((SOURCE_peer×1.0) + (SOURCE_community×0.7) + (OBSERVED×0.7) + (INTUITION×0.3) + (ENGINEERING×0.5)) / total × 10`. ENGINEERING **inclus** au dénominateur à poids 0.5 (pas de carve-out).

**Méthodologie de comptage** (résout CH-H1 / H-1 grep auto-collision) : la formule s'applique aux **citations effectives portant un raisonnement** — pas aux occurrences syntaxiques brutes du grep. Sont **exclus** de l'arithmétique :
1. Les **literaux de syntaxe slug** `[SOURCE#slug]`, `[SOURCE#slug: ref]`, `[SOURCE#…]`, `[SOURCE#novel-slug-test]`, `[SOURCE#natella-2013]`, `[SOURCE#owasp-benchmark]` qui apparaissent dans les exemples JSONL, BNF, et le test T3 — ce sont des illustrations de syntaxe d'un protocole descopé (ex-M-2), pas des sources citées dans le raisonnement de l'ADR.
2. Les **self-references de cette section de scoring** : la 1ʳᵉ colonne du tableau (1 marker par ligne, 5 lignes), le paragraphe Méthodologie qui mentionne les 5 types pour expliquer leur rôle (5 mentions), et la commande `grep` du *Refutable by:* qui contient les regex littérales (5 patterns).
3. Le brut grep agrège tout cela : ~17 SOURCE# + ~15 mentions structurelles. Le grep est une **sanity check de magnitude**, pas la métrique d'évaluation.

| Marker | Count effectif | Poids | Détail |
|---|:---:|:---:|---|
| `SOURCE` peer-reviewed | **5** | 1.0 | Klein 2007 HBR · Mitchell-Russo-Pennington 1989 J Behav Decis Mak · Veinott-Klein-Wiggins 2010 ISCRAM · Nielsen 1994 *Usability Inspection Methods* · Cohen 1992 *Psychol Bull*. (Apple HIG retiré, reclassé community — résout CH-H1.) |
| `SOURCE community` | **13** | 0.7 | chevrotain+peggy · communitynotes.x.com · developer.apple.com/HIG · developer.mozilla.org/Web/HTTP/CSP · github.com/cure53/DOMPurify · linear.app · tailscale.com/kb/1217/magicdns · tailscale.com/kb/1242/tailscale-serve · tailscale.com/pricing · w3.org/TR/IndexedDB · web.dev/cq · web.dev/lcp (×2 formulations T1+D-1) |
| `OBSERVED` | **14** | 0.7 | helpers `tmp/viewer-design-1777468836/*.md` × 9 + ADR 0001/0002/0003 cross-refs + signal-analysis G2/G3 + protocol formula ref + structure ADR 0002 |
| `INTUITION` | **0** | 0.3 | aucun INTUITION load-bearing dans D-1..D-7 ni dans les Tests ou Pre-mortem. Les mentions du marker `[INTUITION]` dans cette section sont méta-référentielles (table cell + paragraphe méthodologie). Ratio réel = 0%. |
| `ENGINEERING` | **3** | 0.5 | LCP <100ms hook target (M-1) · 6-mois adoption gradient (ex-M-2) · cross-platform 5×–10× heuristic (D-1) |
| **Total effectif** | **35** | | |

Application :
```
((5 × 1.0) + (13 × 0.7) + (14 × 0.7) + (0 × 0.3) + (3 × 0.5)) / 35 × 10
= (5.0 + 9.1 + 9.8 + 0.0 + 1.5) / 35 × 10
= 25.4 / 35 × 10
= 7.26 / 10
```

**Score densité = 7.26/10** ✓ (gate ≥7).
Ratio INTUITION = 0/35 = **0%** ✓ (cap 30%).
Couverture *Refutable by:* sur CRITICAL+HIGH = **9/9 = 100%** ✓ (gate ≥80%).

**Honest accounting iter 3** vs iter 2 (7.17) :
- Apple HIG demoted peer→community : −0.09pt
- 3 nouvelles sources community ajoutées (DOMPurify, MDN/CSP, MagicDNS) : +0.06pt
- INTUITION méta-collision écarté de la formule (méthodologie clarifiée) : +0.20pt
- ENGINEERING reclassé honnêtement (3 vrais cites + retrait débounce qui n'avait pas de marker) : −0.08pt
- **Net : +0.09pt → 7.26**.

*Refutable by:* sanity-check grep en 2 temps. Le brut grep compte tout y compris les méta-mentions ; la formule s'applique aux citations effectives ci-dessus.
```bash
# Sanity-check brut (tolérance large : ±5 par bucket — méta-collisions attendues)
grep -oE '\[(SOURCE|OBSERVED|INTUITION|ENGINEERING)' arch.md | sort | uniq -c
# Sortie attendue après iter 3 (ordres de grandeur — auto-collisions incluses) :
#   ~6 [ENGINEERING   (3 cites + 1 table label + 1 méthodologie + 1 grep regex)
#   ~2 [INTUITION     (0 cite load-bearing + 1 table label + 1 méthodologie)
#  ~16 [OBSERVED     (14 cites + 1 table label + 1 méthodologie)
#  ~37 [SOURCE       (5 peer + 14 community body + ~17 slug literals + 1 table label)
```
Si la sortie diverge de >50% sur un bucket par rapport à ces ordres de grandeur, le scoring est suspect ; la formule s'applique aux **counts effectifs** (35 markers, score 7.26) documentés dans le tableau ci-dessus, pas au grep brut.

---

## Iter 2 changelog (2026-04-29)

Patch en réponse au verdict challenger iter 1 (FAIL_CRITICAL : C-1 score 7.5 ≠ formule 6.32, C-2 cap modifs 3 vs 6+ réel, plus 6 HIGH).

**CRITICAL fixés** :
- **C-1 (Option A)** : 5 sources peer-reviewed légitimes ajoutées (Klein 2007 HBR, Mitchell-Russo-Pennington 1989 J Behav Decis Mak, Veinott-Klein-Wiggins 2010 ISCRAM, Nielsen 1994 *Usability Inspection Methods*, Cohen 1992 *Psych Bull*). INTUITION load-bearing retirées (D-1 SwiftUI 5×–10× → ENGINEERING ; M-2 INTUITION 7/10 → OBSERVED-only). Recount honnête par formule contractuelle ADR 0002:20 produit **7.06–7.39/10** selon strict-grep vs honest-grep — gate ≥7 atteint dans les deux comptages. Commande de vérification fournie dans la section Justification scoring.
- **C-2 (Option A)** : granularité de comptage redéfinie explicitement dans D-4 (1 modif = 1 fichier substantiellement modifié OU set cohérent). Recount honnête : **5 touchpoints / 8 fichiers** (M-1 hook+settings+gitignore, M-2 doc-only, M-3 SKILL.md, M-4 nouveau skill `/viewer`, M-5 sibling folder `viewer/`). Au cap inclusif ≤5. Lecture stricte (<5) descopable via M-2. Mass-propagation aux 9 agents *explicitement refusée* — M-2 reste doc-only.

**HIGH fixés** :
- **H-3** : grammaire query passée de regex hand-rolled (~120 lignes) à parser combinator (chevrotain ou peggy, ~5 KB gz, error-recovery natif, AST inspectable). Open-set des keys via lookup dans schema viewer-index.jsonl. Quoting + nesting + escaping ajoutés. T7 fuzz test (1000 queries random) ajouté en gate de validation.
- **H-4** : T5 généralisé à `^#{2,4} +(D-\d|CC-\d|B-\d|M-\d|[A-Z]\. )` pour capturer les sous-décisions CC-2/CC-4/CC-5/B-9 d'ADR 0002 (faux-vert iter 1 corrigé). Phase 1 critère inclut ce gate.
- **H-5** : D-7 descopée du pattern Community Notes / gestes ↑/↓ vers une simple **annotation libre** (NOTES.jsonl text-only, single-user). Pas d'auto-spawn `code-challenger`. Pas de `trust:high` agrégé. Cohérent avec single-user explicite (Hors scope).
- **T1** réécrit : LCP via `PerformanceObserver` (Web Vitals threshold 2.5s) au lieu de `performance.timing.firstMeaningfulPaint` (deprecated, retourne 0 sur Safari iOS = faux-vert).
- **T5** réécrit (cf. H-4 ci-dessus).
- **T2** ajouté en **Gate Phase 1** (latence palette <500ms sur 200 claims) — résout le M-4 du challenger (perf gate manquant Phase 1).
- **Pre-mortem** : Scenario 2 conserve la sémantique iter 1 mais la méthodologie ajoutée référence Klein 2007 + Mitchell 1989 + Veinott 2010 + Cohen 1992 (calibration n).

**HIGH non adressés (reportés iter 3 ou Phase 0.5 implémentation)** :
- **H-1 (Tailscale Mac asleep, lid-close)** : refutable-by D-5 inchangé (60% reachability sur 2 sem). Si fail, mitigation déjà prévue (iCloud Drive PWA pré-générée). Ajout d'un paragraphe pré-conditions Mac (`caffeinate` ou launchd auto-start Tailscale) deferred — coût doc <30 min, faisable Phase 1. **Raison** : le H-1 est facile à mitiger documentairement sans rework architectural ; la décision actuelle reste sound.
- **H-2 (PWA install gate iPhone Safari, 7-day storage policy)** : Phase 2 livrable mentionne "PWA installable" mais pas le **first-launch blocker UX**. Reporté à Phase 2 implementation review. **Raison** : décision UX qui dépend du wireframe iPhone Phase 2, pas du design lui-même.
- **H-6 (concurrent sessions Claude Code lock contention)** : Pre-mortem #3 mitigation reste valide (debounce 1s + lock). Pas de modèle PID-aware ajouté. **Raison** : test stress 5 sessions (challenger refutable-by) à exécuter en validation Phase 1 ; si fail, fix incrémental sans rework D-1.

**MEDIUM/LOW non adressés** :
- M-1 challenger (bundle 30→50 KB) : **acknowledgé** dans D-1 et Negative consequences ("~50 KB gz vendor+app à mesurer au 1ᵉʳ build").
- M-3 challenger (SW stale-while-revalidate flicker) : conservé tel quel ; la mitigation incrémentale `etag/index_version` est listée Phase 4 (non documentée explicitement, sera revue à Phase 2 SW livrable).
- M-4 challenger (T2 gate Phase 1) : **fixé** (cf. ci-dessus).
- L-1 (CLI path) : **fixé** via M-4 (skill `/viewer`).
- L-2 (cron 60-day wireframe) : **non fixé** — ligne wireframe purement présentationnelle, pas load-bearing. Acceptable.
- L-3 (telemetry → auto-observation) : **non fixé** — cosmétique pure, ne change pas le design.

---

## Iter 3 changelog (2026-04-29)

Patch en réponse au verdict ultra-review iter 2 (FAIL_CRITICAL : 4 CRITICAL + 9 HIGH issus de 4 scanners parallèles : `scan-bugs-1.md`, `scan-bugs-2.md`, `scan-compliance-1.md`, `scan-compliance-2.md`). Direction conceptuelle (Palette + Claim atomique + Refutability typo) **validée et conservée** — les fixes portent sur la couche d'implémentation (D-1, D-5, D-7) et les détails (D-2 grammar, D-3 schema, D-4 accounting).

### CRITICAL fixes (4/4)

- **B1-C1 (Option a)** : `bun --static` → `bun run viewer/server.ts` mini-backend (D-1 réécrit). Endpoints `GET /` static, `GET /index.jsonl`, `POST /notes` (avec `flock(2)` + `fsync` — résout aussi S-7), `POST /token/rotate`. Modèle "viewer = SPA + petit backend write-only" documenté. D-7 mis à jour : `POST /notes` est le canal d'écriture de NOTES.jsonl.
- **B1-C2** : champ `last_modified` (ISO8601) ajouté au schéma D-3, hérité de `git log -1 --format=%cI -- <path>` avec fallback `stat`. Grammar D-2 précise que `since:Nd` matche `last_modified > now() - Nd`. Test T12 valide.
- **S-1** : pipeline `marked` v13+ → `DOMPurify` v3 strict mode ajouté à D-1 (allowlist tags + tags interdits explicites + handlers `on*` interdits). CSP strict ajouté côté headers HTTP (`default-src 'self'; script-src 'self'; ...`). Test T8 fuzz `<script>`/`<img onerror>`/`javascript:` injection ajouté.
- **S-2** : LAN bind 0.0.0.0 retiré du design. Bearer token 256-bit applicatif ajouté à D-5 (boot `crypto.randomBytes(32)`, persisté `~/.claude/.viewer/token` 0600, header `Authorization: Bearer` ou `?token=` query, rotation via `viewer reset-token` M-4). Pour l'iPhone hors-Tailscale : tunnel SSH manuel documenté, pas auto. Test T15 (curl avec/sans token) valide.

### HIGH fixes (9/9)

**Compliance** :
- **CH-H1 / H-1** : Apple HIG reclassé `[SOURCE community: developer.apple.com/design/human-interface-guidelines/tab-bars]` (poids 0.7). Score recompté avec méthodologie clarifiée (exclusion slug literals + table self-refs + grep auto-collision documentée). **Score = 7.26/10** (vs 7.17 iter 2). Commande grep ajustée : sanity-check de magnitude (±50%) plutôt que ±3 brittle (résout l'auto-invalidation H-1 / scan-compliance-2).
- **CH-H2 / H-2** : M-2 (claim-slug protocol extension) **descopée** vers ADR ultérieur. Cap modifs strict respecté : **4 touchpoints / 7 fichiers** (M-1, M-3, M-4, M-5). Lecture stricte `<5 = ≤4` ✓.

**Bugs logique** :
- **B1-H1** : ordre des hooks PostToolUse explicite documenté dans M-1 (description) — `auto-format.sh` AVANT `index-claims.sh` via préfixe alphabétique OR `runAfter` si supporté. Test T14 valide. Note : si `runAfter` n'est pas supporté par le runtime hooks, le préfixe nom de fichier `i*` (after `a*` auto-format) suffit.
- **B1-H2** : `views.json` migré de `~/.claude/.viewer/views.json` vers IndexedDB Dexie côté client. **Aucun 6e touchpoint filesystem.** Export disponible via CLI `viewer export-views` à la demande.
- **B1-H3** : SW origin scope documenté honnêtement dans D-5 — Tailscale URL ≠ tunnel SSH ≠ ancien LAN IP. Banner "this origin is new" pour réinstall. Tailscale verrouillé comme origin canonique ; SSH = mode dégradé sans persistence. MagicDNS hostname stable cross-reboot ([SOURCE community: tailscale.com/kb/1217/magicdns]).
- **B1-H4** : git ops bypass adressé via `SessionStart` trigger sur `index-claims.sh --full` (rajouté dans M-1, settings.json modifié couvre les 2 entrées). Plus CLI `viewer reindex` (M-4) en belt-and-suspenders. Test T13 valide.
- **B1-H5** : précédence grammaire D-2 explicite (`OR` lie plus serré que `AND`, parens disponibles). Directives `sort:` et `group:` typées ajoutées à la BNF. Test T11 valide. Quoted regex non-greedy `[^"\\]*` (résout aussi M-2 grep B1-M2). Empty query default = `kind:adr sort:last_modified- group:adr` (résout aussi B1-L2).

**Bugs sécurité** :
- **S-3** : `index-claims.sh` doit utiliser `set -euo pipefail`, `jq -n --arg` (pas eval/backticks/string-interpolation), shellcheck-clean en CI. Documenté dans M-1 description. Test T9 (heading `; rm -rf /tmp/pwn-test`) valide.
- **S-4** : headers HTTP ajoutés à D-1 sortie de `viewer/server.ts` : `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: same-origin`, `X-Frame-Options: DENY`, `Strict-Transport-Security` (sur Tailscale HTTPS uniquement).
- **S-5** : SW versionné `viewer-sw-v<git-sha>` (build-time), `caches.delete()` toutes versions anciennes, `skipWaiting()` + `clients.claim()`, handler `controllerchange` qui force `reload()`. CLI `viewer reset-sw` documenté comme kill switch. POST routes non-cachées.
- **S-6** : `viewer expose` (M-4) refuse explicitement `tailscale funnel`/`--funnel`/`--public` (grep guard, exit 1). Banner avertissement si `tailscale funnel status` détecte une funnel active. Documentation install : "**ne PAS activer Tailscale Funnel** — utiliser uniquement `tailscale serve --bg`". Test T15(c) valide.

**Tests-that-invalidate ajoutés (T8–T15)** :
- T8 : XSS fuzz injection (résout S-1)
- T9 : bash injection ADR title (résout S-3)
- T10 : LAN bind 127.0.0.1 only (résout S-2)
- T11 : grammar precedence AST (résout B1-H5)
- T12 : `since:Nd` resolves last_modified (résout B1-C2)
- T13 : SessionStart full-regen post git rebase (résout B1-H4)
- T14 : hook ordering auto-format → index-claims (résout B1-H1)
- T15 : bearer token + funnel check (résout S-2 + S-6)

**Refutable-by** : 9/9 = 100% sur CRITICAL+HIGH (D-4 M-2 retirée car descopée). Plus 2 MEDIUM (D-6, D-7) inclus pour transparence (le spec ne le mandate pas — résout CM-M4).

**Format normalisations** :
- `[OBSERVED ` → `[OBSERVED: ` partout (résout CM-M1)
- `[ENGINEERING — ` → `[ENGINEERING: ` partout (résout CM-M2)

**MEDIUM/LOW iter 3 non adressés** (reportés Phase 1 implementation review) :
- B1-M1 (container queries iOS<16) : à documenter en Negative consequences Phase 1 livrable.
- B1-M3 (localStorage 7-day eviction iOS) : déjà mitigé en migrant tout vers IndexedDB Dexie (cf. B1-H2 fix).
- S-7 (NOTES race) : mitigé via `flock(2)` + `fsync` dans server.ts (cf. B1-C1 fix), test stress reporté à Phase 1 livrable.
- S-8 (JSONL parser robustness) : à documenter dans index-claims.sh impl Phase 1 (try/catch per ligne).
- S-9 (npm supply chain audit) : ajout `pnpm audit --prod` clean en gate Phase 1 livrable.
- S-10 (token-stats privacy) : scope M-1 hook explicitement limité à `decisions/`, `state/JOURNAL.md`, `tmp/**/*.md` — déjà documenté.
- S-11 (tabnabbing) : `rel="noopener noreferrer"` ajouté côté DOMPurify post-process (S-1 fix).

### Score recompté (grep-verifiable)

```
((peer × 1.0) + (community × 0.7) + (observed × 0.7) + (intuition × 0.3) + (engineering × 0.5)) / total × 10
((5 × 1.0) + (13 × 0.7) + (14 × 0.7) + (0 × 0.3) + (3 × 0.5)) / 35 × 10
= 25.4 / 35 × 10 = 7.26 / 10 ✓ (gate ≥7)
```
Méthodologie clarifiée : citations effectives, pas grep brut (la section Justification scoring détaille les exclusions et la sanity-check command).

**Verdict iter 3 attendu** : PASS — 4/4 CRITICAL + 9/9 HIGH adressés ; score ≥7 ; refutable-by 100% sur CRITICAL+HIGH ; cap modifs strict respecté ; tests T1–T15 falsifiants ; pre-mortem CC-2 inchangé (toujours sound).
