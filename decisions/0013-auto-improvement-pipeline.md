# ADR 0013 — Auto-improvement pipeline (Option A)

**Status**: Proposed
**Date**: 2026-05-19
**Context**: ADR 0012 a posé un *radar pur* (`/improvement-monitor` → `state/MONITORING-YYYY-MM.md`, lecture humaine). L'utilisateur a confirmé que ce niveau de friction ralentit la boucle : il faut un cron qui identifie ET prépare l'application (sans jamais merger), avec gate humain explicite à chaque transition. Décision : ajouter une couche *triage + apply* au-dessus du radar, sans toucher le radar lui-même.
**Decision**: 4 deltas surgicaux : (1) le **hook bash** `hooks/improvement-monitor.sh` (extension déterministe) écrit `state/PENDING-IMPROVEMENT.md` + lance `osascript` quand le skill LLM a renvoyé un JSON de classification structuré avec ≥1 `[high]` ; (2) le skill `/improvement-monitor` est ramené à un rôle de classifieur pur (entrée: changelog stdout ; sortie: JSON via `--json-schema`) ; (3) un nouveau skill `/apply-improvement` lit le pending, demande `AskUserQuestion`, crée une branche `improvement/YYYY-WW`, invoque `/team` en interne via subprocess avec contrat explicite (status JSON + exit codes), lance E2E, notifie ; (4) un script `tests/e2e-improvement.sh` valide les hooks modifiés sur fixtures synthétiques. **Rien ne merge automatiquement.**
**Consequences**: Le radar reste falsifiable (T1/T2/T3 d'ADR 0012 toujours valides). Friction réduite (notification push vs. lecture passive). Boundary LLM ↔ bash déterministe explicite (side-effects en bash). Risque résiduel : un `[high]` mal classifié génère du noise hebdomadaire — mitigé par la confirmation AskUserQuestion et le fait que rejet = `git branch -D`. Cet ADR **supersede partiellement ADR 0012** sur le point "Pas de génération automatique de backlog" : on génère un *pending* (1 item, 1 fichier, écrasable), pas un backlog. Le radar lui-même reste intact.

---

# Architecture — Auto-improvement pipeline (Option A)

## Context and constraints

**État actuel** (post-ADR 0012, validé sur disque) :
- `hooks/improvement-monitor.sh` fetch le changelog [OBSERVED `hooks/improvement-monitor.sh:33`], écrit stdout brut depuis la dernière version monitorée.
- `skills/improvement-monitor/SKILL.md` classifie `[high]/[mid]/[skip]` et écrit `state/MONITORING-YYYY-MM.md` [OBSERVED `skills/improvement-monitor/SKILL.md:22-29`].
- Cron lundi 9h27 : `claude -p "/improvement-monitor"` [OBSERVED `crontab -l`].
- `state/MONITORING-2026-05.md` contient déjà 5 items `[high]` actionable [OBSERVED `state/MONITORING-2026-05.md:11-24`].

**Gap** : la lecture est passive. L'utilisateur doit ouvrir une session, lire le rapport, décider, lancer `/team`. Friction = oubli + retard.

**Contraintes utilisateur (interview)** :
- Rien ne s'implémente sans approbation explicite.
- Tests = E2E (pas juste lint), < 5 min, fixtures synthétiques (pas de vrai réseau).
- Accept UX = commandes git manuelles (pas de skill accept/rollback dédié).
- Scope = tenter tous les `[high]` ; si >3 itérations review échouent → branche vide + notification "too complex".
- Rien ne merge sur main sans action manuelle.

**Constraints CLAUDE.md** :
- Zéro abstraction prématurée. Pas de validation hors boundaries système.
- ADRs append-only — cet ADR supersede partiellement ADR 0012.
- Scratch zone = `.claude/tmp/` uniquement.
- **Justifiability rule** : pas de fichier sans caller défini.

**Contrainte empirique CLI** (testée 2026-05-19) :
- `claude --help` ne propose **pas** de flag global qui court-circuite `AskUserQuestion`. Les flags disponibles : `--permission-mode auto`, `--dangerously-skip-permissions`, `--max-budget-usd`, `--json-schema`, `-p/--print`. Aucun ne désactive `AskUserQuestion`. Conséquence : tout subprocess `/team` peut bloquer si le skill invoque `AskUserQuestion` (5 sites recensés [OBSERVED `skills/team/SKILL.md:30,89,132,313,320`]).

## Patterns evaluated

| Pattern | Domain | Decision | Technical justification | Source | Refutable by |
|---------|--------|----------|-------------------------|--------|--------------|
| **Pure radar (status quo ADR 0012)** | CLI tooling | ❌ REJECTED | Friction lecture passive, gap entre signal et action | [OBSERVED `decisions/0012-recurring-improvement-monitoring.md:17`] | *Refutable by:* mesure user déclare "je lis MONITORING.md chaque lundi sans rappel" sur 3 cycles → radar suffit |
| **Full autopilot (cron merge auto)** | CLI tooling | ❌ REJECTED | Viole contrainte interview "rien ne merge sans action manuelle" + viole CLAUDE.md scope expansion | [OBSERVED `~/.claude/CLAUDE.md` §"Scope expansion check"] | *Refutable by:* utilisateur change d'avis et accepte merges auto sur green E2E |
| **Pending file + notification + manual /apply** (SELECTED) | CLI tooling | ✅ SELECTED | Découplage signal/action ; gate humain via AskUserQuestion ; aucune écriture sur main sans `git merge` explicite | [INTUITION: single-slot pending parce que cadence cron 1x/semaine matche le throughput d'application user] | *Refutable by:* notification ignorée >4 semaines consécutives → push channel inefficace, revenir au radar pur |
| **Issue queue (multi-pending stack)** | CLI tooling | ⚠️ DEFERRED | Au-delà de YAGNI **pour le throughput utilisateur**, mais MONITORING-2026-05 montre 5 `[high]` actifs → top-1 selection requise (cf. D1 révisé). Queue bornée à 3 reste DEFERRED jusqu'à 2 cycles consécutifs avec ≥2 [high] non-classifiés "skip" | [OBSERVED `state/MONITORING-2026-05.md:11-24`] | *Refutable by:* le user demande "je veux 3 items en parallèle" sur 2 cycles → introduire queue bornée à 3 |
| **Worktree par item (parallel branches)** | CLI tooling | ❌ REJECTED | Surface 2.1.143 `worktree.bgIsolation` non encore absorbée par plugin [OBSERVED MONITORING-2026-05 watch] ; 1 item/semaine ne justifie pas | [OBSERVED `state/MONITORING-2026-05.md:20`] | *Refutable by:* >1 improvement actif simultanément requis |
| **Bash E2E fixture (selected)** | Test framework | ✅ SELECTED | Stack 100% bash, pas de runner Python/npm ; fixtures = stdin/stdout/exit code | [OBSERVED `~/.claude/CLAUDE.md` "Stack: Bash uniquement"] | *Refutable by:* fixture-based tests miss >50% of real bugs sur 3 cycles |
| **BATS test framework** | Test framework | ❌ REJECTED | Introduit dépendance externe ; YAGNI pour 1 script E2E ; user veut "no framework" | [OBSERVED user interview note] | *Refutable by:* >5 test scripts à maintenir → BATS justifié |
| **macOS notif via `osascript` (best-effort)** | UX channel | ✅ SELECTED | Déjà utilisé par plugin Notification hook ; canal **ergonomic** (pas truth-layer — voir D2 révisé) | [OBSERVED `~/.claude/CLAUDE.md` §"Notification"] | *Refutable by:* user disable macOS notifs (Focus mode) → besoin canal secondaire (session-resume-journal display) |
| **AskUserQuestion gate** | UX gate | ✅ SELECTED | Built-in Claude Code, satisfait "rien ne s'implémente sans approbation" | [SOURCE: Claude Code official tool AskUserQuestion, used in 14+ skills] | *Refutable by:* user veut auto-yes sur low-risk items → introduire `--auto-low-risk` flag |
| **State Machine explicite (file marker)** | CLI tooling | ✅ SELECTED (révisé suite à HIGH-2) | 4 états + transitions atomiques par renommage de fichier marker. Pas de XState formel, juste suffix-rename convention | [INTUITION: simpler than FSM lib, idempotent re-entry on crash] | *Refutable by:* >2 cycles avec bug d'état (transition incorrecte) → introduire FSM lib explicite |
| **LLM-driven side-effects (status quo skill)** | CLI tooling | ❌ REJECTED (révisé suite à CRITICAL-3) | LLM non-déterministe au cron (token budget, hallucination). Side-effects critiques (PENDING write + osascript) doivent être en bash | [INTUITION: skill markdown interprété par LLM ne garantit pas exec d'étapes] | *Refutable by:* `claude -p "/improvement-monitor" 2>&1 \| grep -c OSASCRIPT` = 5/5 sur 5 cron runs → LLM-exec fiable |
| **Bash-driven side-effects + awk parse of MONITORING.md** | CLI tooling | ✅ SELECTED (révisé suite à challenge-code v2 CRITICAL-1) | Boundary LLM ↔ déterministe explicite. Le skill `/improvement-monitor` est invoqué EN SESSION (pas au cron) et écrit `state/MONITORING-YYYY-MM.md` avec sa classification `[high]/[mid]/[skip]`. Le hook bash, déclenché ensuite (cron OU session post-skill), **parse `## Actionable` de MONITORING-*.md avec awk** pour extraire le top item, écrit PENDING, invoque osascript. Pas de 2ème appel LLM au cron. `--json-schema` superflu. | [ENGINEERING: awk parsing MONITORING.md produit par LLM = déterministe au cron sans 2ème appel] | *Refutable by:* `awk '/^## Actionable/,/^## /'` ne retourne pas le top `[high]` sur 1/5 fixtures synthétiques → parser regex insuffisant |
| **`claude -p "/team"` subprocess avec contrat explicite** | CLI tooling | ✅ SELECTED (révisé suite à CRITICAL-1+2) | Contrat formel : `--permission-mode auto`, status JSON à path connu, timeout. Audit des 5 AskUserQuestion sites de `/team` est dans le scope dev | [OBSERVED `claude --help` 2026-05-19: pas de flag global skip-AskUserQuestion ; donc on transmet `$ARGUMENTS` non-vide + on capture stderr] | *Refutable by:* `claude -p --permission-mode auto "/team --auto <ambiguous>"` deadlock sur 3 trials → contrat insuffisant, switcher vers approche alternative (cf. §Subprocess contract D3) |
| **`git log` + `git reflog` comme audit trail** | CLI tooling | ✅ SELECTED (suite à HIGH-4) | Cohérent avec "commandes git manuelles" et "git CLI native, zero dépendance". Remplace `state/applied/` orphan | [OBSERVED `~/.claude/CLAUDE.md` "Justifiability rule"] | *Refutable by:* user demande "je veux voir l'historique sans toucher git" → réintroduire state/applied/ avec consumer concret |

## Proposed architecture

### Overview

```
[Crontab lundi 9h27] (unchanged)
        │
        ▼
[claude -p "/improvement-monitor"]
        │
        ▼
┌─────────────────────────────────────────┐
│ skill /improvement-monitor (MODIFIED)   │
│  1. exec hooks/improvement-monitor.sh   │
│     (fetch changelog → stdout)          │
│  2. classify [high]/[mid]/[skip]        │
│  3. write state/MONITORING-YYYY-MM.md   │
│  4. NEW: run hook --write-pending →     │
│     hook parses ## Actionable via awk   │
└─────────────────────────────────────────┘
        │
        ▼
[hooks/improvement-monitor.sh --write-pending] (bash déterministe)
        │
        ├─ parse ## Actionable → top [high] item via awk
        │
        ├─ if top item found:
        │     ├─ write state/PENDING-IMPROVEMENT.md
        │     └─ osascript -e 'display notification ...'
        │
        ├─ else: idempotent (no PENDING, no notify)
        │
        └─ log to cache/cron-improvement-monitor.log
        │
        ▼  (user voit notif OU lit PENDING via session-resume-journal)
        │
[claude /apply-improvement]
        │
        ▼
┌─────────────────────────────────────────┐
│ skill /apply-improvement (NEW)          │
│  State machine: pending → applying →    │
│    pass | fail | complex | rejected     │
│  Each transition = marker file rename   │
│                                         │
│  1. check git status clean              │
│  2. read state/PENDING-IMPROVEMENT.md   │
│     + capture mtime (race detection)    │
│  3. AskUserQuestion(item)               │
│     ├── no  → marker -rejected.md, exit │
│     └── yes ▼                           │
│  4. re-check mtime; if changed → abort  │
│  5. git checkout -b improvement/YYYY-WW │
│     marker → -applying.md               │
│  6. subprocess /team (contract: status  │
│     JSON, exit codes — cf §Subprocess)  │
│     ├─ pass: marker → -pass.md          │
│     ├─ FAIL_CRITICAL: marker → -fail.md │
│     └─ >3 review iter: marker→-complex  │
│  7. tests/e2e-improvement.sh            │
│  8. osascript notify w/ next git cmds   │
└─────────────────────────────────────────┘
        │
        ▼ (user exécute manuellement)
[git merge] OR [git branch -D]
```

### Main components

| Component | Responsibility | Technology | Type |
|-----------|----------------|------------|------|
| `hooks/improvement-monitor.sh` | Fetch changelog (CHANGELOG_URL configurable) en mode default ; en mode `--write-pending` : **parse awk MONITORING.md + write PENDING + osascript** (déterministe bash, pas de 2ème appel LLM au cron) | Bash + curl + awk + osascript | EXTENDED (additive, no breaking) |
| `skills/improvement-monitor/SKILL.md` | Classifier + writer de MONITORING.md (skill LLM en session, inchangé depuis ADR 0012) | Skill markdown | UNCHANGED (rôle préservé) |
| `skills/apply-improvement/SKILL.md` | Read PENDING, gate user, branch, `/team` subprocess avec contrat, E2E, notify, état machine via marker rename | Skill markdown | NEW |
| `tests/e2e-improvement.sh` | Validate hooks + skill classification + state machine on synthetic fixtures (CHANGELOG_URL=file://...) | Bash | NEW |
| `state/PENDING-IMPROVEMENT.md` | Single-slot pending item (overwritable) | Markdown | NEW (transient state) |
| `state/applying/YYYY-WW-<slug>-{pending,applying,pass,fail,complex,rejected}.md` | Stateful marker (suffix-rename = transition) ; consumer: `/apply-improvement` lui-même au re-run pour idempotence + `session-resume-journal.sh` pour afficher état | Markdown | NEW (consumer concret défini) |
| `hooks/session-resume-journal.sh` | Lit JOURNAL + **NEW: PENDING-IMPROVEMENT.md (abs path) + state/applying/*-applying.md** pour signaler resume state | Bash | MODIFIED (1-liner additif) |

### Data flows

**Flow 1 — Monitor → Pending (cron path, deterministic bash core)** :
```
crontab lundi 9h27 → invoque le skill LLM /improvement-monitor en session :
   ├─ skill classifie le changelog [high]/[mid]/[skip]
   └─ skill écrit state/MONITORING-YYYY-MM.md (## Actionable + ## Watch)

puis (même cron, étape post-skill OU session manuelle) :
hooks/improvement-monitor.sh --write-pending
   │
   ├─ 1. lit le plus récent state/MONITORING-*.md (ls + tail -1)
   │
   ├─ 2. awk parse section `## Actionable` → premier item `- vX.Y.Z` = top item
   │     (déterministe, pas de 2ème appel LLM au cron)
   │
   ├─ 3. if top_item != "":
   │       ├─ derive slug (kebab-case du feature name)
   │       ├─ grep -n -F -- "$top_item" → numéro de ligne source
   │       ├─ write state/PENDING-IMPROVEMENT.md (Source/Generated/Item/Rationale)
   │       └─ osascript -e 'display notification "..."'
   │
   ├─ 4. else: log PENDING_WRITTEN=false, exit 0 (idempotent)
   │
   └─ log "PENDING_WRITTEN=<bool> slug=<slug> monitoring=<file>" → cache/cron-improvement-monitor.log
```

LLM ne touche AUCUN side-effect (PENDING + osascript). LLM produit MONITORING.md en session, le hook bash parse au cron. Frontière LLM ↔ déterminisme explicite, sans appel `claude -p` au cron.

*Refutable by:* `awk` ne match pas un `## Actionable` malformé (header avec espaces traînants, lignes vides intercalées) → cas e2e à couvrir.

**Flow 2 — Pending → Branch (user-initiated path, state machine)** :
```
user (Cmd+Space, types "claude")
   │
   ▼
/apply-improvement
   │
   ├─ check git status clean (else abort "Working tree dirty")
   │
   ├─ read state/PENDING-IMPROVEMENT.md
   │  + stat -f %m PENDING → MTIME_BEFORE
   │
   ├─ AskUserQuestion
   │   │
   │   ├── no  → touch state/applying/YYYY-WW-<slug>-rejected.md
   │   │         remove PENDING
   │   │         exit 0
   │   │
   │   └── yes
   │       │
   │       ├─ stat -f %m PENDING → MTIME_AFTER
   │       │  if [[ $MTIME_BEFORE != $MTIME_AFTER ]] → abort "PENDING changed, re-run"
   │       │
   │       ├─ git checkout -b improvement/YYYY-WW
   │       │  touch state/applying/YYYY-WW-<slug>-applying.md
   │       │  (PENDING stays until terminal state — re-entry safety)
   │       │
   │       ├─ subprocess /team (cf §Subprocess contract)
   │       │  ├─ status JSON pass → mv -applying.md -pass.md
   │       │  ├─ status JSON FAIL_CRITICAL → mv -applying.md -fail.md
   │       │  └─ review_iterations > 3 → mv -applying.md -complex.md
   │       │
   │       ├─ tests/e2e-improvement.sh (best-effort, logs only)
   │       │
   │       ├─ osascript notify w/ results + 2 git commands
   │       │  (best-effort, not part of state machine)
   │       │
   │       └─ rm state/PENDING-IMPROVEMENT.md (terminal state reached)
   │
   └─ re-entry: at startup, if any -applying.md exists → notif "Resume?" + exit
                if -pending.md exists → re-read PENDING normally
```

### Technical stack

| Technology | Role | Justification | Source |
|------------|------|---------------|--------|
| Bash + `osascript` | Notifications (best-effort layer, NOT truth-layer) | Déjà utilisé par plugin Notification hook | [OBSERVED `~/.claude/CLAUDE.md` "macOS notifications"] |
| Bash + `curl` (CHANGELOG_URL env override) | Changelog fetch testable | Hook existant + 1-liner pour testabilité | [OBSERVED `hooks/improvement-monitor.sh:33`] |
| Git CLI (incl. `git log`, `git reflog`) | Branch + merge + audit trail | Native, zero dépendance, cohérent avec "commandes git manuelles" | [OBSERVED `~/.claude/CLAUDE.md` "Justifiability rule"] |
| `claude -p --json-schema --permission-mode auto` | Subprocess invoke avec contrat | Tested via `claude --help` 2026-05-19, flags exists | [OBSERVED `claude --help` output 2026-05-19] |
| Skills markdown | Skill definition | Standard Claude Code | [SOURCE: Claude Code skills docs] |
| AskUserQuestion tool | Confirmation gate (interactive only) | Built-in interactive primitive ; pas court-circuitable au CLI | [SOURCE: Claude Code tool AskUserQuestion + observed claude --help] |
| `jq` | JSON parsing for LLM classifier output | Standard POSIX-ish toolchain, déjà sur poste dev macOS (Homebrew) | [ENGINEERING: macOS dev posts ont jq via brew, single dep] |
| `stat -f %m` (BSD) | mtime check pour race detection (cron vs /apply) | Native macOS, 1-liner | [INTUITION: vs lockfile = overkill] |
| File marker rename | State machine sans FSM lib | `mv -<old>.md -<new>.md` = transition atomique au niveau OS | [INTUITION: atomic rename pattern, used widely in mail spool, queue dirs] |

## Subprocess contract

### `claude -p "/team ..."` invocation contract

**Invocation form** (mandatory):
```bash
TEAM_NO_GC=1 claude -p \
  --permission-mode auto \
  --max-budget-usd 5.00 \
  "/team --auto $ITEM_DESCRIPTION (auto-improvement context, status JSON required at ~/.claude/tmp/$TEAM_DIR/team-status.json)"
```

**Why this exact triple-flag composition** (corrige la confusion `--permission-mode auto` vs `/team --auto` relevée iter 2 HIGH-A) :

1. **`TEAM_NO_GC=1`** (env var) — court-circuite STEP 0bis (gc orphans) qui ferait `AskUserQuestion` si orphans détectés dans `~/.claude/tmp/`. Le déclencheur est l'**état du fs** (orphans >7 jours), pas les arguments — donc impossible à neutraliser par la prompt seule. La variable est lue explicitement par le skill [OBSERVED `skills/team/SKILL.md:93` "Skip this step if flag `--no-gc` or env `TEAM_NO_GC=1`"].

2. **`--permission-mode auto`** (flag de `claude` runtime) — autorise les file edits autonomes côté runtime Claude Code [OBSERVED `claude --help` 2026-05-19]. Ne silence PAS `AskUserQuestion` (primitive distincte) — c'est pourquoi `--auto` est aussi requis.

3. **`/team --auto`** (flag du skill `/team`) — "no confirmation between steps (for tests/CI)" [OBSERVED `skills/team/SKILL.md:67`]. C'est le flag qui court-circuite les confirmations inter-steps du pipeline `/team` lui-même (interview, routing ambigu, validation intermédiaire). Distinct de `--permission-mode auto` malgré la nomenclature similaire.

**Sites AskUserQuestion résiduels après cette composition** : `$ITEM_DESCRIPTION` non-vide bypasse STEP 0 (ligne 30). `TEAM_NO_GC=1` bypasse STEP 0bis (ligne 89). `--auto` bypasse les confirmations inter-steps (incl. routing ligne 132, interview ligne 313, validation ligne 320). Les 5 sites [OBSERVED `skills/team/SKILL.md:30,89,132,313,320`] sont donc tous adressés par construction, pas seulement T6-falsifiés. T6 ci-dessous valide empiriquement la composition.

**Status output contract** :
- `/team` MUST write `~/.claude/tmp/$TEAM_DIR/team-status.json` before exit, with shape:
  ```json
  {
    "verdict": "PASS | FAIL_CRITICAL | FAIL_WARNING | NEEDS_JUSTIFICATION",
    "review_iterations": <int>,
    "commits_count": <int>,
    "branch": "improvement/YYYY-WW",
    "team_id": "<team-dir-name>"
  }
  ```
- `/apply-improvement` parses this file post-subprocess. If absent → treat as crash (state machine → `-fail.md` with reason "team-status missing").
- This contract is enforced by Implementation plan §10 (modify `skills/team/SKILL.md` STEP 6 to write `team-status.json` before TeamDelete). Voir §10 pour la spec exacte : path, JSON shape, persistance de `review_iterations` via `iter-count.txt`, comportement sur crash et FAIL_CRITICAL. Additive, non-breaking — solo runs écrivent le fichier sans le consommer.

**Exit codes** :
- `0` = subprocess completed (verdict in JSON tells PASS/FAIL distinction)
- `non-zero` = subprocess crashed (treat as -fail.md with stderr capture)
- Timeout (>30 min) = SIGTERM by `/apply-improvement`, state → -fail.md

**Fallback if `--permission-mode auto` does NOT short-circuit all AskUserQuestion** (concrete plan B):
- T6 falsification test will detect deadlock empirically. If deadlock confirmed on the 4 conditional sites:
- **Alternative D3 path** : invoke `/team` **without** subprocess — instead, `/apply-improvement` writes a `PENDING-TEAM-INVOCATION.md` and notifies user "Open new session and run `/team <item>` manually, then re-launch `/apply-improvement --resume`". This trades automation for determinism. Cost : 1 extra manual step per cycle. Justified if subprocess proves unreliable.
- Decision gate : if T6 fails 2/3 trials → switch to Alternative D3 path before shipping.

## Key technical decisions

### D1. Single-slot PENDING + deterministic top-1 selection (révisé suite à HIGH-5)

Alternative considérée : queue de pendings (FIFO ou priority). **Selected**: single-slot, deterministic top-1, BUT **deterministic ranking explicit** (was implicit before).

**Top-1 heuristic** (deterministic, bash-enforced — not LLM-discretion):
1. Skill LLM returns JSON with `items[]` ordered by **changelog file order** (line number ascending — first to appear in upstream notes).
2. Skill also returns `top_high_index` = index of FIRST item with `priority="high"`.
3. If 0 high items → `top_high_index = null` → no PENDING.
4. Hook bash reads `top_high_index` from JSON (no re-ranking) and writes that single item.

**Why this works on 5+ [high] reality** : MONITORING-2026-05 currently shows 5 [high] entries — but only the top 1 enters PENDING per cycle. Iterations N+1, N+2 etc. re-classify (changelog is monotonically growing — items already in MONITORING.md persist). The user processes 1/week ; in 5 weeks all 5 are addressed (assuming none becomes obsolete). If a [high] is never processed and falls off the changelog edge → **archived in `state/MONITORING-YYYY-MM.md`** (radar layer, ADR 0012 invariant) → not lost, just not pushed.

**Refutable by:** sur 8 semaines, ≥3 PENDING écrasés sans avoir été lus → on a perdu du signal → introduire queue bornée à 3 (Pattern marked DEFERRED in §Patterns).

### D2. osascript = best-effort ergonomic layer, NOT truth-layer (révisé suite à HIGH-3)

Reformulated : `osascript` is used as a **push channel** for ergonomics. Its delivery is **NOT confirmed** (macOS Focus Mode silently drops notifs while returning exit 0 — empirically observed, no exit-code distinction). 

**The authoritative channel is the filesystem** : `state/PENDING-IMPROVEMENT.md` existence is the invariant. `hooks/session-resume-journal.sh` extension (cf. Implementation plan §8) makes this visible at each session start — that's the **reliable** notification.

`osascript` remains because it's free (already wired via plugin Notification hook) and helps when user IS at desk. But the design does not rely on its delivery confirmation.

**Refutable by:** measure on 100 invocations (a) latency, (b) reproduce Focus Mode + check exit code remains 0 with no banner. If Focus Mode silent + exit 0 confirmed → session-resume-journal fallback is the only correct channel (which is what we ship).

### D3. `/team` invoqué via `claude -p` subprocess avec contrat formel (révisé suite à CRITICAL-1+2)

Alternative : invoquer `/team` "inline" dans le contexte du skill `/apply-improvement`. **Rejected** : un skill ne peut pas invoquer un autre skill nativement (pas d'inter-skill API stable).

**Contrat formalisé** (cf. §Subprocess contract above) :
- Invocation : `TEAM_NO_GC=1 claude -p --permission-mode auto --max-budget-usd 5.00 "/team --auto <non-empty ITEM> (auto-improvement context, status JSON required)"` (triple-flag composition — cf. §Subprocess contract pour la justification)
- Output : `team-status.json` à path connu, parsé par `/apply-improvement`.
- Exit code 0 = ran (verdict in JSON), non-zero = crash, timeout 30min = SIGTERM.
- AskUserQuestion handling : `$ITEM_DESCRIPTION` non-vide gates STEP 0 (1 site). 4 sites résiduels (orphans, routing, interview, validation) falsifiés par T6.
- Fallback Alternative D3 path : si T6 deadlock → manual two-session protocol (cf. §Subprocess contract).

**Refutable by:** T6 falsification test ; si fails 2/3 → Alternative D3 path engagé.

### D4. State machine via marker file rename (révisé suite à HIGH-2)

Alternative considérée : 4 états (pending/applying/tested/reviewed) gérés in-memory dans le skill. **Rejected** : non-idempotent au crash. 

**Selected** : file-marker state machine in `state/applying/`:
- `YYYY-WW-<slug>-applying.md` : created at branch creation (after yes)
- → `-pass.md` : `/team` returned PASS verdict in status JSON
- → `-fail.md` : `/team` returned FAIL_CRITICAL or crashed or status missing
- → `-complex.md` : `/team` review_iterations > 3
- → `-rejected.md` : user said NO at AskUserQuestion (created INSTEAD of -applying)

**Atomic transition** : `mv old.md new.md` on Unix is atomic at the inode level. No partial states.

**Re-entry semantics** : at startup of `/apply-improvement`:
- If `state/applying/*-applying.md` exists → notif "Branch <X> was mid-apply, resume manually or `rm` marker to reset" + exit. No silent retry.
- If `state/applying/*-rejected.md` exists for current week + PENDING absent → idle.
- If PENDING exists + no applying marker → normal flow.

**Audit trail** : `git log state/applying/` + `git reflog` give full history. Consumer of these markers : `/apply-improvement` itself at re-entry (idempotence) + `session-resume-journal.sh` for visibility at session start (cf. §8). NOT orphan.

**Refutable by:** invoke `/apply-improvement`, accept, kill -9 mid-`/team`. Relaunch. If skill detects -applying marker and notifies/exits cleanly → idempotent. If crashes or silently retries → finding confirmed.

### D5. E2E fixtures synthétiques + CHANGELOG_URL env var (révisé suite à MEDIUM-2)

`tests/e2e-improvement.sh` mocks the changelog via `CHANGELOG_URL="file://$TMPDIR/fixture.md"`. Hook `hooks/improvement-monitor.sh` accepts `CHANGELOG_URL="${CHANGELOG_URL:-https://...}"` (1-liner change).

**Result** : the E2E tests the REAL hook (incl. curl machinery against `file://`), not a mock. Granularity claim "no network" is enforceable : test runs offline.

**Refutable by:** lancer `tests/e2e-improvement.sh` Wi-Fi off → exit 0 sans erreur réseau → claim valide.

### D6. Branche `improvement/YYYY-WW` (week-based, pas item-based)

ISO week = unique sur le cycle cron. Si user lance `/apply-improvement` deux fois la même semaine (rejette le premier, accepte le second), la deuxième invocation détecte un marker `-rejected.md` pour la semaine courante MAIS PENDING absent (puisque cron n'a pas re-tiré) → notif "Already rejected this week ; wait until next cron Monday, or re-run `/improvement-monitor` manually to regenerate". 

Si branche existe (marker `-applying`) → notif "Branch exists, mid-state, resume manually" — voir D4 re-entry.

**Refutable by:** user veut 2 attempts/semaine — alors slug-based naming requis.

### D7. Cet ADR supersede partiellement ADR 0012

ADR 0012 §"Decision" item 5 : "**Pas** de génération automatique de backlog ni d'ADR — c'est un radar, pas un autopilot". Cet ADR change ça partiellement : on génère un *pending de 1 item* (transient, écrasable), pas un backlog persistant. Le radar (MONITORING-YYYY-MM.md) reste intact. C'est pourquoi le Status est **Supersedes partial** sur le point §Decision item 5 — la falsification T1/T2/T3 de ADR 0012 reste applicable.

### D8. PENDING absent vs marker "idle" (suite à MEDIUM-3)

Tranchage : **PENDING absent si rien d'actionable**. Simple, et la `cache/cron-improvement-monitor.log` (append-only par hook) sert de heartbeat ("cron a tourné lundi N — wrote_pending=false"). `/apply-improvement` voit PENDING absent → notif "Nothing pending. Last cron run: <log timestamp>" + exit.

**Refutable by:** user demande "je veux savoir quand cron a tourné même si rien à faire" → introduire marker idle file (downgrade to LOW change).

### D9. Audit trail via git log / git reflog, pas `state/applied/` (suite à HIGH-4)

`state/applied/` était un orphan (no caller). Supprimé du scope. Remplacé par :
- `state/applying/*-{rejected,pass,fail,complex}.md` markers (consumer concret : re-entry du skill + session-resume-journal)
- `git log improvement/*` pour voir ce qui a été tenté (commits sur branches improvement/*)
- `git reflog` pour audit après suppression de branche

**Cohérent avec** "git CLI native, zero dépendance" + "commandes git manuelles" + Justifiability rule.

**Refutable by:** user dit "je veux un fichier de récap permanent par item appliqué" → réintroduire state/applied/ avec consumer (e.g. `/apply-improvement` affiche les 3 derniers au lancement).

## Identified risks

### R1. Noise hebdomadaire si classification `[high]` trop laxiste

**Impact** : user reçoit notif inutile → ignore notifs → vraies opportunités manquées.
**Mitigation** : SKILL.md §Heuristics deja stipule "When in doubt → `[mid]` over `[high]`". Plus : T1 (3 runs vides) reste actif depuis ADR 0012. Plus : top-1 deterministic (D1) — pas N items pollués, 1 seul par cycle.

### R2. `/team` invoqué via subprocess perd le contexte de session

**Impact** : `/team` ne sait pas qu'il tourne dans le cadre d'auto-improvement (pas d'env var transmise).
**Mitigation** : injecter via env (`AUTO_IMPROVEMENT_SOURCE=PENDING-IMPROVEMENT.md`, `AUTO_IMPROVEMENT_TEAM_DIR=...`) avant `claude -p`. `/team` peut lire ça si besoin (optionnel). Status JSON path = `$AUTO_IMPROVEMENT_TEAM_DIR/team-status.json`.

### R3. AskUserQuestion timeout/skip → confusion d'état

**Impact** : user lance `/apply-improvement`, ne répond pas, ferme session → PENDING toujours là, branche pas créée, état flou.
**Mitigation** : pas de side-effect avant le yes. État machine D4 garantit : si crash entre yes et branch creation → pas de marker `-applying` créé → re-run repart proprement. Si crash après marker → re-entry détecte et notifie.

### R4. E2E tests faux positif (passent mais bug en prod)

**Impact** : merge d'une amélioration qui casse en prod.
**Mitigation** : T2 + T3 explicitement énoncé. E2E couvre les **boundaries critiques** (exit codes des hooks, format PENDING-IMPROVEMENT.md, JSON schema de classification, state machine transitions, status JSON parsing), pas l'implémentation interne de `/team` (out of scope).

### R5. Concurrent cron + manual /apply-improvement

**Impact** : lundi 9h27 le cron écrase PENDING pendant que user est en train de l'appliquer.
**Mitigation concrète** (révisé suite à MEDIUM-1) : avant `AskUserQuestion`, `stat -f %m PENDING-IMPROVEMENT.md` → `MTIME_BEFORE` ; après yes, re-stat → `MTIME_AFTER`. If `MTIME_BEFORE != MTIME_AFTER` → notif "PENDING changed during confirmation, re-run /apply-improvement" + exit. 2-line bash, robust. Lock file reste overkill.

**Refutable by:** injecter `touch state/PENDING-IMPROVEMENT.md` entre AskUserQuestion et yes ; vérifier que l'erreur déclenche.

### R6. macOS Focus Mode silently drops osascript notifications (révisé suite à HIGH-1+3)

**Impact** : user a Focus Mode "Work" H24 → cron tire chaque lundi, écrit PENDING, lance osascript → macOS supprime notif silencieusement → user ne sait jamais. PENDING-IMPROVEMENT.md s'écrase chaque lundi pendant N semaines, items perdus (mais conservés dans MONITORING radar layer).

**Mitigation** (concrète, dans Implementation plan §8) :
1. **`hooks/session-resume-journal.sh` modifié** pour détecter `$HOME/.claude/state/PENDING-IMPROVEMENT.md` (path absolu) ET `$HOME/.claude/state/applying/*-applying.md` ET les afficher à chaque session start. C'est le **canal authoritative** : invisible-to-Focus-Mode mais visible-at-session-start.
2. `cache/cron-improvement-monitor.log` heartbeat = secondary signal pour health-check.

R6 n'est PAS un "risque résiduel non-mitigé" — il est mitigé par §8.

### R7. LLM classifier returns malformed JSON despite `--json-schema`

**Impact** : hook bash receives invalid JSON → jq fails → no PENDING written, no error visible.

**Mitigation** : `hooks/improvement-monitor.sh` validates JSON with `jq -e` (exit code) ; on failure → log "CLASSIFICATION_INVALID" to `cache/cron-improvement-monitor.log` AND write `state/PENDING-IMPROVEMENT.md` with content `# CLASSIFICATION FAILED <timestamp>` so session-resume-journal surfaces it. Best-effort osascript notify "Classification failed, check log".

**Refutable by:** 5 cron runs avec `claude -p --json-schema`, count valid JSON outputs. If <5/5 → fallback needed (already implemented).

### R8. Risque résiduel accepté — Ctrl-C utilisateur pendant subprocess /team

**Impact** : subprocess `/team` orphelin tourne dans le vide après que `/apply-improvement` parent est tué. Git peut être dans un état mixte (HEAD detached, fichiers staged).

**Mitigation** : `/apply-improvement` fait `git status --porcelain` AVANT toute action (pre-flight). Au re-entry, marker `-applying.md` détecté → notif "previous run was killed, inspect manually: `git status`, `git branch`, `rm state/applying/YYYY-WW-*-applying.md` to reset".

**Accepté comme résiduel** sur l'événement Ctrl-C lui-même : impossible de faire mieux sans wrapper supervisor (overkill pour 1/sem cron + 1 user).

## Explicit perimeter

**Cette architecture NE GÈRE PAS** :
- Le contenu de l'amélioration elle-même (responsabilité de `/team`)
- Le rollback post-merge (responsabilité du user via `git revert`)
- Les tests de l'amélioration appliquée elle-même (responsabilité de `/team` + ses agents tester/reviewer)
- Une UI / dashboard (CLI only, conforme stack)
- Notifications cross-platform (macOS only — osascript)
- Multi-machine sync (single-user, single-machine)
- Détection automatique d'AskUserQuestion residuel dans `/team` (T6 le falsifie ; si fail → fallback Alternative D3 path manuel)

## Suggested implementation plan

**Ordre pour le développeur** :

1. **`hooks/improvement-monitor.sh`** — extension déterministe (cœur du shift LLM→bash) :
   - Ajouter `CHANGELOG_URL="${CHANGELOG_URL:-https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md}"` au top (1 ligne).
   - Le hook fournit deux modes :
     - mode par défaut (fetch) : curl le changelog + émet le delta sur stdout. Le skill LLM `/improvement-monitor` consomme ce stdout, classifie en session, et écrit `state/MONITORING-YYYY-MM.md`.
     - mode `--write-pending` (ou env `IMPROVEMENT_MONITOR_WRITE_PENDING=1` pour le cron) : skip le fetch, parse le MONITORING-*.md le plus récent et écrit PENDING + osascript.
   - **Parse via awk (pas via `claude -p --json-schema`)** : la classification est déjà LLM-effectuée et persistée dans MONITORING.md. Le hook parse `## Actionable` avec awk pour extraire le premier item `- vX.Y.Z`. Raison : le hook tourne au cron APRÈS le skill ; un 2ème appel LLM serait redondant et introduirait une dépendance cron→LLM non nécessaire. awk parsing MONITORING.md (produit par LLM) = déterministe au cron sans 2ème appel.
   - Si top item trouvé :
     - dériver `$slug` (kebab-case du feature name extrait du format `- vX.Y.Z — <feature> — already in plugin? <yes|no|partial>`)
     - `grep -n -F -- "$top_item" "$latest" | head -1 | cut -d: -f1` → numéro de ligne source (le `-F` désactive l'interprétation regex, le `--` protège des items commençant par `-`)
     - écrire `state/PENDING-IMPROVEMENT.md` (format spec §4)
     - `osascript -e 'display notification "Improvement ready: '"$slug"'. Run /apply-improvement." with title "Claude plugin"'` (best-effort, `|| true`)
     - log `PENDING_WRITTEN=true slug=$slug monitoring=$(basename "$latest")` dans `cache/cron-improvement-monitor.log`
   - Sinon : log `PENDING_WRITTEN=false reason=no-high-actionable monitoring=...` (heartbeat).

   *Refutable by:* `grep -c "claude -p" hooks/improvement-monitor.sh` retourne >0 → le hook réinvoque le LLM au cron, déviation par rapport à cette décision.

2. **`hooks/improvement-monitor.schema.json`** — ❌ NOT NEEDED. Le choix awk-parse-MONITORING (cf. §1) supprime le besoin d'un JSON schema : pas d'appel `claude -p --json-schema` au cron. Section conservée pour traçabilité de la décision mais aucun fichier n'est créé.

3. **`skills/improvement-monitor/SKILL.md`** — rôle inchangé par rapport à ADR 0012 (classifier + writer de MONITORING.md, en session LLM) :
   - Description : "Classifie le delta changelog (priorités high/mid/skip) et écrit `state/MONITORING-YYYY-MM.md` avec sections `## Actionable` (les `[high]`) et `## Watch` (les `[mid]`)."
   - Le skill tourne en session LLM (cadence : invoqué par le cron via `claude -p "/improvement-monitor"`, OU par l'utilisateur en interactif).
   - Au cron, après que le skill a écrit MONITORING.md, le hook `improvement-monitor.sh --write-pending` est invoqué dans la foulée (par le même cron OU par un dernier step du skill) pour parse-awk → PENDING + osascript. Pas de boucle cron→LLM redondante.

4. **`state/PENDING-IMPROVEMENT.md` spec** (created by hook §1) :
   ```markdown
   # PENDING — <slug>
   Source: state/MONITORING-YYYY-MM.md line N
   Generated: <ISO timestamp>
   Item: <full [high] line copiée verbatim depuis MONITORING.md>
   Rationale: top-1 actionable from monthly radar
   ```

5. **`skills/apply-improvement/SKILL.md`** — nouveau skill :
   - Description : "Apply the top pending improvement from state/PENDING-IMPROVEMENT.md on a dedicated branch with state-machine tracking."
   - Workflow detailed in Flow 2 above. Key steps :
     - pre-flight: `git status --porcelain` empty
     - re-entry detection: scan `state/applying/*-applying.md` → abort if found
     - mtime check around AskUserQuestion (R5 mitigation)
     - branch + marker `-applying.md` creation
     - subprocess `/team` invocation per §Subprocess contract
     - parse `team-status.json` → marker transition
     - E2E run + osascript notify best-effort
     - `rm PENDING-IMPROVEMENT.md` at terminal state

6. **`tests/e2e-improvement.sh`** — script bash :
   - Setup : `TMPDIR=$(mktemp -d)`, `CHANGELOG_URL="file://$TMPDIR/fixture.md"`
   - Cases (au moins 6) :
     - `case_1_high_present` : fixture avec 2 entries `[high]` → assert PENDING-IMPROVEMENT.md créé, contenu top 1 (= first high in JSON items order), osascript appelé (mock).
     - `case_2_no_high` : fixture sans `[high]` → assert PENDING absent, pas d'osascript, log `PENDING_WRITTEN=false`.
     - `case_3_overwrite` : PENDING existe déjà → assert overwrite avec nouveau timestamp.
     - `case_4_branch_exists` : marker `-applying.md` déjà présent → `/apply-improvement` détecte, notif erreur, exit non-zero.
     - `case_5_status_json_parsing` : mock `claude -p "/team"` qui écrit team-status.json avec `verdict:"PASS"`, `review_iterations:2` → assert marker renamed to `-pass.md`. Repeat with `review_iterations:4` → marker `-complex.md`. Repeat with status JSON absent → marker `-fail.md`.
     - `case_6_invalid_classification_json` : LLM returns malformed JSON → hook detects, logs CLASSIFICATION_INVALID, writes failure marker PENDING.
   - Mock `osascript() { echo "OSASCRIPT_CALLED: $*" >&2; }` exporté dans env de test.
   - Mock `claude -p` via stub bash (writes canned team-status.json based on `$ITEM_DESCRIPTION` content).
   - Cleanup : `trap "rm -rf $TMPDIR" EXIT`
   - **Durée cible** : <60s sur les 6 cases.

7. **Crontab** : ordre `skill puis hook --write-pending`. Le cron lance d'abord `claude -p "/improvement-monitor"` (skill LLM en session, écrit MONITORING.md), puis enchaîne sur `$HOME/.claude/hooks/improvement-monitor.sh --write-pending` (parse awk MONITORING.md → PENDING + osascript). Exemple : `27 9 * * 1 claude -p "/improvement-monitor" && $HOME/.claude/hooks/improvement-monitor.sh --write-pending`. Justification : déterminisme bash au cron (parse awk) sans 2ème appel LLM redondant. *Refutable by:* deux LLM calls observables au cron via `grep -c "claude -p" cache/cron-improvement-monitor.log` > 1 par run → cron mal configuré, dépendance LLM doublée.

8. **`hooks/session-resume-journal.sh`** — modification (mitigation R6, S2 résolu) :
   - Resolve absolute path : `PENDING_FILE="$HOME/.claude/state/PENDING-IMPROVEMENT.md"`.
   - If `[[ -f "$PENDING_FILE" ]]` → append to journal block : "⚠ PENDING improvement awaits — run `/apply-improvement`".
   - Also scan `$HOME/.claude/state/applying/*-applying.md` ; if any → append "⚠ Improvement mid-apply : <slug> (run `/apply-improvement` to resume status or `rm` marker)".
   - Coût : ~5 lignes bash additives. Backward compat préservée.

9. **ADR persistence** : cet `arch.md` devient `.claude/decisions/0013-auto-improvement-pipeline.md` (lead persiste).

10. **`skills/team/SKILL.md`** — additif contract `team-status.json` (mitigation HIGH-B iter 2, sortie out-of-band du contract subprocess) :
    - **Où** : au STEP 6 (DONE), juste **avant** `TeamDelete` (et avant toute cleanup tmp).
    - **Quoi écrire** :
      ```bash
      cat > "$HOME/.claude/tmp/${TEAM_NAME}/team-status.json" <<EOF
      {
        "verdict": "${FINAL_VERDICT}",
        "review_iterations": ${REVIEW_ITER_COUNT},
        "commits_count": ${COMMITS_COUNT},
        "branch": "$(git rev-parse --abbrev-ref HEAD)",
        "team_id": "${TEAM_NAME}"
      }
      EOF
      ```
    - **Comment alimenter `review_iterations`** : le lead incrémente un compteur à chaque retry du challenge loop / review cycle et le persiste dans `~/.claude/tmp/${TEAM_NAME}/iter-count.txt` (1 ligne, entier). Lecture finale = `cat iter-count.txt` ; absence du fichier = 0.
    - **Comment alimenter `commits_count`** : `git rev-list --count main..HEAD` au moment de l'écriture (commits propres à la branche en cours par rapport à `main`).
    - **Comportement crash** : si le lead crash avant cette ligne → fichier absent = signal légitime traité comme `-fail.md` côté `/apply-improvement` (cf. §Subprocess contract "absent → treat as crash").
    - **Comportement FAIL_CRITICAL** : écrire le JSON quand même (verdict = "FAIL_CRITICAL"), pas seulement sur PASS. Le consumer `/apply-improvement` parse `.verdict` pour distinguer PASS vs FAIL_CRITICAL vs missing.
    - **Backward compat** : solo runs (sans `AUTO_IMPROVEMENT_SOURCE` env var) écrivent quand même le fichier — non-breaking, juste un fichier ignoré dans `~/.claude/tmp/` qui sera gc-ed par `team-gc.sh` au cycle suivant.
    - **Refutable by** : après implémentation, lancer `TEAM_NO_GC=1 claude -p --permission-mode auto "/team --auto test-item"` puis vérifier `ls ~/.claude/tmp/*/team-status.json` non-vide ET `jq -e .verdict $f` retourne string non-null. Si fichier absent ou JSON malformé → contrat §10 non implémenté correctement.

## Tests that would invalidate this design

- **T1** — *Composant `hooks/improvement-monitor.sh` (extended) + classifier subprocess* sous *trigger* "run with fixture containing 0 `[high]` items" doit produire *signal* "PENDING-IMPROVEMENT.md is absent AND osascript NOT called AND log shows PENDING_WRITTEN=false". Si PENDING est créé quand vide → l'assertion "rien ne notifie sans `[high]`" est fausse, architecture invalide.

- **T2** — *Composant `skills/apply-improvement` (new) + state machine* sous *trigger* "user répond NO à AskUserQuestion" doit produire *signal* "no branch created AND no commits AND marker `state/applying/YYYY-WW-<slug>-rejected.md` exists AND PENDING-IMPROVEMENT.md removed". Si une branche est créée avant le yes → la gate humaine est leaky, viole contrainte "rien ne s'implémente sans approbation". Si marker absent ou wrong suffix → state machine D4 broken.

- **T3** — *Composant `tests/e2e-improvement.sh` + CHANGELOG_URL env var* sous *trigger* "exécution sur poste neuf cloné depuis git, Wi-Fi off, CHANGELOG_URL=file://..." doit produire *signal* "exit 0 en <300s sans accès réseau et sans dépendance non-bash (sauf jq)". Si le test requiert npm/python/curl-réseau → la contrainte "stack bash uniquement, E2E < 5min" est violée. Si le hook ignore CHANGELOG_URL et hit GitHub → D5 invalide.

- **T4** — *Composant subprocess `/team` invocation + status JSON parsing* sous *trigger* "`/team` itère review 4 fois sans converger (mock subprocess writes team-status.json with review_iterations=4)" doit produire *signal* "marker renamed to `-complex.md` AND notif macOS contient le mot 'COMPLEX' AND PENDING removed AND branch exists (possibly empty)". Si parsing fails ou marker wrong → contrat CRITICAL-2 broken. Si pipeline boucle au-delà ou écrase main → cap "3 itérations" et "rien ne merge sans manuel" sont violés.

- **T5** — *Composant notification chain (osascript) + session-resume-journal fallback* sous *trigger* "macOS Focus mode activé" devrait produire *signal* "notification potentially dropped silently (acceptable per D2 révisé) MAIS session-resume-journal.sh affiche PENDING ou marker `-applying` au next session start (mitigation R6)". Si la notif est perdue ET session-resume-journal ne mentionne PAS PENDING → mitigation R6 broken, le canal authoritative est perdu.

- **T6** — *Composant subprocess contract triple-flag composition (`TEAM_NO_GC=1` + `--permission-mode auto` + `/team --auto`) + AskUserQuestion residual sites* sous *trigger* "invoke `TEAM_NO_GC=1 claude -p --permission-mode auto --max-budget-usd 0.50 \"/team --auto <intentionally ambiguous item description that could trigger interview or routing AskUserQuestion>\"` on 3 trials, **pre-condition: `~/.claude/tmp/` ayant ≥3 sous-dossiers >7 jours** pour stress-tester STEP 0bis suppression effective" doit produire *signal* "exit 0 OR non-zero clean exit dans <300s par trial, AUCUN deadlock infini, stderr capture confirme AUCUN trigger AskUserQuestion (i.e. les 5 sites `skills/team/SKILL.md:30,89,132,313,320` sont tous court-circuités par construction)". Trial supplémentaire à exécuter sans `TEAM_NO_GC=1` et sans `/team --auto` (seulement `--permission-mode auto`) pour falsifier la baseline : doit deadlock ou trigger AskUserQuestion → confirme que les 2 flags additionnels sont effectivement load-bearing. Si la composition triple-flag deadlock sur ≥2/3 trials → §Subprocess contract falsifié → fallback Alternative D3 path engagé (manual two-session protocol). Si la baseline (sans triple-flag) ne deadlock pas non plus → l'un des flags est redondant, simplifier. Ce test est le **gate critique du shipping** — exécuter avant tout merge sur main.

## Pre-mortem CC-2 — 3 disaster scenarios

### Scenario S1 — "Le bot de la honte" (6 mois plus tard)

**Composant** : `skills/apply-improvement` + `claude -p "/team ..."` subprocess
**Trigger** : Lundi N+24, le cron classifie `[high]` une entrée de changelog qui a une formulation ambiguë ("Improved hook lifecycle"). User clique OK distraitement sur AskUserQuestion. `/team` interprète "improve" comme "refactor toutes les hooks" → branche `improvement/2026-W43` contient 47 commits qui touchent les 15 hooks.
**Signal mesurable** : `git diff main..improvement/2026-W43 --shortstat` > 500 lignes, ou `git log improvement/2026-W43 --oneline | wc -l` > 10.
**Adressé dans le design** : OUI — D4 (state machine cap 3 review iter via `review_iterations` in status JSON) + R1 (heuristics conservatives). T4 le falsifie explicitement. Status JSON contract (§Subprocess) rend le compte d'itérations observable depuis l'extérieur — pas aspirational comme avant.

### Scenario S2 — "La notification fantôme" (RÉSOLU dans design)

**Composant** : `osascript notify` + macOS Focus mode / DND
**Trigger** : User a Focus mode "Work" activé H24 (cas réel pour senior dev). Cron tire chaque lundi, écrit PENDING, lance osascript. macOS supprime la notif silencieusement. User ne sait JAMAIS qu'il y a un pending.
**Signal mesurable** : compter sur 8 semaines `cat cache/cron-improvement-monitor.log | grep -c "PENDING_WRITTEN=true"` > 4 ET `state/applying/*-*.md` count < 2 → divergence = signal perdu côté user.
**Adressé** : OUI (auparavant PARTIELLEMENT). Implementation plan §8 explicite la modification de `hooks/session-resume-journal.sh` pour détecter `$HOME/.claude/state/PENDING-IMPROVEMENT.md` + `state/applying/*-applying.md` au session start. Le canal "session-resume-journal display" est invisible-to-Focus-Mode. T5 falsifie. D2 révisé acte que osascript est best-effort, pas truth-layer — le fs IS la vérité.

### Scenario S3 — "Le pied de biche git"

**Composant** : Git branch management + subprocess `/team`
**Trigger** : User lance `/apply-improvement`, accepte, `/team` commence à implémenter sur `improvement/2026-W22`. À mi-parcours, user Ctrl-C la session (urgence). Le subprocess `/team` continue à tourner ou laisse l'état git dans un mode incohérent.
**Signal mesurable** : `git status` après un crash/Ctrl-C montre des fichiers staged non-commités OU `state/applying/*-applying.md` existe mais HEAD est sur main.
**Adressé** : OUI (auparavant PARTIELLEMENT). Mitigation explicite : (a) `/apply-improvement` fait `git status --porcelain` pré-flight ; non-vide → abort. (b) State machine D4 : marker `-applying.md` détecté au next run → notif "previous run mid-apply, inspect or `rm` marker". (c) Cohérence avec D9 (audit trail via git log + reflog). **Accepté comme risque résiduel** sur l'événement Ctrl-C pendant subprocess lui-même : impossible à empêcher sans wrapper, marker fait son boulot au re-entry.

---

**Architect**, 2026-05-19 (v2 post-challenge). Stack: bash. Effort: L. References: ADR 0012 (supersede partial §Decision item 5), MONITORING-2026-05.md, criteria.md du team, challenge-arch.md (FAIL_CRITICAL 5/10 → adressé : 3 CRITICAL + 4 HIGH + 2 MEDIUM).
