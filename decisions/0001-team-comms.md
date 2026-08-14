# ADR 0001 — Communication inter-agent /team

- **Status** : Accepted (2026-06-04, promoted by 0016 §D-3; originally Proposed v2 — itération post-challenge 1/5). Implementation: bloc commun ×17 agents + send-message-guard.sh + rule 19 grep.
- **Date** : 2026-04-25
- **Authors** : team-lead (consolidation), architect-research, analyzer-diag, innovator-creative, challenger-arch (audit)
- **Supersedes** : —
- **Superseded by** : —

## Context

Le skill `/team` orchestre 12 agents spécialisés via Claude Code experimental Agent Teams (TeamCreate + Agent + tmux panes + SendMessage natif). Observation empirique multi-projets : **les sub-agents finissent leur tâche silencieusement, le team-lead ne reçoit aucune notification, le pipeline se bloque ou ralentit massivement** [OBSERVED: TheTeacher session 89774821 ; ce pipeline lui-même — 4 sub-agents ont livré sans envoyer SendMessage].

### Diagnostic empirique [SOURCE: `diagnosis.md` v2 — 12 causes racines, cross-validation 4/4]

Top 4 causes racines :

1. **RC10 (9/10) — `SendMessage` indisponible côté sub-agent.** [OBSERVED: 3 agents indépendants — analyzer-diag a empiriquement reçu *"Error: No such tool available: SendMessage. SendMessage exists but is not enabled in this context"* ; innovator-creative a dû append directement à `inboxes/team-lead.json` ; architect-research a dû Write `_status_*.md`]. Le tool est annoncé en runtime mais absent du function schema effectif. Limitation runtime Claude Code, **pas un trou de configuration**.
2. **RC1 (9/10) — System prompts agents totalement muets sur le protocole d'équipe** [OBSERVED: scan des 12 `agents/*.md` → 0 mention SendMessage, STATUS, team-lead, teammate]. Le rôle est défini, le protocole d'équipe ne l'est pas.
3. **RC2 (9/10) — Briefs lead inconsistants** [OBSERVED: scan des 16 briefs historiques persistés → 50 % omettent l'invocation explicite de SendMessage]. Le brief est jetable, sa qualité varie.
4. **RC4 (8/10) — Pas de filet d'enforcement plateforme** [OBSERVED: `~/.claude/settings.json` n'a câblé aucun hook réagissant à la fin de tour d'un teammate].

### Contraintes plateforme [SOURCE: `gh api`, doc officielle]

- Bug Anthropic **#24108 → canonical #23415** *"mailbox never polled in tmux split-pane"* — `state=closed`, `state_reason=not_planned`, closed 2026-03-20 [SOURCE: `gh api /repos/anthropics/claude-code/issues/23415`]. **Anthropic ne corrigera pas.** Toute solution doit traiter cette limitation comme structurelle, pas transitoire.
- Hooks lifecycle disponibles incluent `SubagentStop` (pour subagents au sens tool `Agent`/`Task`) ET `TeammateIdle` (pour teammates Agent Teams) [SOURCE: https://code.claude.com/docs/en/hooks vérifié 2026-04-25, 28 events listés]. Distinction critique : `/team` spawne via TeamCreate → ce sont des **teammates**, donc `TeammateIdle`, **pas** `SubagentStop`.
- `TeammateIdle` fire déjà gratuitement [OBSERVED: `~/.claude/teams/comms-research-1777152274/inboxes/team-lead.json` contient 4 `idle_notification` automatiques sans aucun hook custom].

### État de l'art [SOURCE: `state-of-art.md` — 5 frameworks, 9 patterns scorés]

Top 3 patterns sur 4 dimensions (rétro-compat / observabilité / robustesse / simplicité) :

| Pattern | Score |
|---|---|
| Orchestrator-Worker + Status Protocol explicit | 18/20 |
| Group Chat round-robin déterministe | 17/20 |
| Blackboard filesystem + inbox.md | 16/20 |

Anthropic eux-mêmes recommandent [SOURCE: https://www.anthropic.com/engineering/multi-agent-research-system, principe #2 *"Teach the orchestrator how to delegate"*] :

> *"Each subagent needs an objective, an output format, guidance on the tools and sources to use, and clear task boundaries."*

## Decision

Pattern **3-layers** (réduit de 5 après challenge) — focus sur ce qui ferme RC1, RC2, RC4 directement, **en composant avec la limitation runtime SendMessage** (RC10 + bug #23415 not_planned).

### Layer 1 — Protocole encodé dans le rôle agent (ferme RC1)

Ajouter à **chaque** `~/.claude/agents/*.md` un bloc commun **"Protocole de communication d'équipe"** (~15 lignes), inline en bas de fichier [INTUITION: réduction taille à valider quand bloc écrit].

Auto-détection team [OBSERVED: présence de `~/.claude/teams/{team}/config.json` lisible OU env `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`] → si pas de team détectée, le bloc est inerte (préserve comportement actuel hors team).

Performatives fermées : `DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED` [SOURCE: réutilise convention `~/.claude/docs/verdict-protocol.md` déjà établie côté skill].

**Canaux de notification ordonnés (le premier qui marche)** — ordre **inversé vs v1** suite finding H1 :

1. **Append à `~/.claude/teams/{team}/inboxes/team-lead.json`** [OBSERVED: validé empiriquement par innovator-creative dans cette même team]
2. **Write `~/.claude/tmp/{team}/_status_<agent-name>.md`** [OBSERVED: validé empiriquement par architect-research et analyzer-diag dans cette même team]
3. **`SendMessage(to="team-lead", ...)` en best-effort** [OBSERVED: échoue actuellement côté sub-agent — RC10. Conservé en cas de fix Anthropic futur, mais NON le canal de premier ordre]

Justification ordre [SOURCE: bug canonical #23415 closed `not_planned` 2026-03-20] : Anthropic ne corrigera pas le mailbox poll. SendMessage en #1 = wishful thinking. Inversion = match avec la réalité observée.

Matrice de routing latéral fournie en exemples concrets dans le bloc (dev↔archi, reviewer↔dev, tester↔dev) [SOURCE: `~/.claude/skills/team/SKILL.md` règles 290-297 — déjà documenté côté lead].

Règle absolue : **la tâche n'est PAS terminée tant qu'au moins un canal de notification n'a pas été utilisé**. Le bloc encode cette règle explicitement.

### Layer 2 — Enforcement par polling lead LLM-réactif (ferme RC4, zero-hook)

Le SKILL.md du lead exécute, **à chaque tour de génération** (modèle LLM-réactif, pas démon de fond), une vérification Bash sur `~/.claude/teams/{team}/inboxes/team-lead.json` ET `~/.claude/tmp/{team}/_status_*.md`. Déclencheur : réception d'une `idle_notification` rendue dans le contexte du lead sous forme de `<teammate-message>`.

Pourquoi pas un hook custom : [OBSERVED: `idle_notification` arrive déjà gratuitement dans l'inbox lead → 4 entrées dans cette team sans aucun hook]. Ajouter `subagent-stop-notify-check.sh` est redondant, et ce serait câblé sur `SubagentStop` qui ne fire pas pour les teammates [SOURCE: doc hooks, distinction TeammateIdle vs SubagentStop — finding C1 du challenge].

Pourquoi pas un démon de fond : [INTUITION 7/10] aucun composant bash n'est wired sur l'inbox actuellement, et ajouter un loop bash en arrière-plan = +1 process à monitorer, +1 risque zombie, +1 dette. Le modèle LLM-réactif réutilise le tour de génération du lead qui existe déjà.

Algorithme côté lead (FSM légère, exécutée à chaque tour) :

1. À la réception d'une `idle_notification` du teammate X (rendue dans le contexte LLM)
2. `Bash("jq '.[] | select(.from == \"X\" and (.read // false) == false)' inbox/team-lead.json")` pour lister les messages non traités
3. Si trouvé message avec performative `DONE|DONE_WITH_CONCERNS|NEEDS_CONTEXT|BLOCKED` : `TaskUpdate(metadata.delivered_by=X)` (cohérent avec règle 14 dedup existante)
4. Sinon : check `~/.claude/tmp/{team}/_status_<X>.md` via `Bash("cat ...")`
5. Si toujours rien : envoi d'un PING au teammate via canal symétrique au Layer 1 #1 (Bash append à `~/.claude/teams/{team}/inboxes/<teammate>.json` performative `PING`) [INTUITION 6/10 : SendMessage côté lead écrit le fichier mais le sub-agent peut ne pas réveiller — observé empiriquement, mon SendMessage de re-challenge n'a pas réveillé le challenger zombie]. Le canal d'écriture marche ; le **réveil** côté sub-agent n'est pas garanti par Claude Code.
6. Si pas de réponse après timeout (cible 30s, configurable) : marquer `STATUS: BLOCKED` dans la TaskList et escalader à l'utilisateur.

Avantage [INTUITION 8/10] : zéro hook custom, exploite l'existant, observable par humain.

Limite explicite [OBSERVED: diagnosis.md §1.7 + chall-v2 finding M2] : Claude Code n'expose pas de mécanisme garanti de réveil sub-agent à réception d'un message. Si `idle_notification` ne fire pas dans une config tmux particulière, le polling LLM-réactif ne tourne pas. Mitigation : timeout dur (step 6) escalade plutôt que silence indéfini.

### Layer 3 — Validation template brief (ferme RC2)

Modifier `~/.claude/skills/team/SKILL.md` :

- Section **CONTEXTE A FORWARDER** devient un **template avec sections nommées obligatoires** : `## Contexte`, `## Objectif`, `## Livrable`, `## Teammates`, `## Protocole de fin`
- Avant chaque `Agent()` spawn, le **lead** (acteur explicité) bash-valide son brief contre ce template :
  ```bash
  for section in "## Contexte" "## Objectif" "## Livrable" "## Teammates" "## Protocole de fin"; do
    grep -qF "$section" "$brief_file" || { echo "BRIEF INVALID: missing $section"; exit 1; }
  done
  grep -qE "(SendMessage|inbox|_status_)" "$brief_file" || { echo "BRIEF INVALID: no notification channel"; exit 1; }
  ```
- Validation par `grep` simple [INTUITION 7/10 : risque faux positifs limité car les noms de section sont distinctifs] ; mode warning par défaut, mode block uniquement avec flag `--strict`.

## Consequences

### Positives

- **Triple canal redondant** [OBSERVED: 3 fallbacks empiriquement validés dans CETTE team] avec ordre aligné sur la réalité (`inboxes/` → `_status_` → SendMessage). Résilient à RC10 + bug #23415 not_planned.
- **Zero hook custom** [INTUITION 9/10] : Layer 2 exploite `idle_notification` natif. Pas de bash maintenance supplémentaire, pas de risque event mismatch (finding C1 fermé).
- **Rétro-compat totale** [OBSERVED: bloc en bas de fichier, auto-détection team] : aucun agent invoqué hors `/team` (via `/review`, `/security`, etc.) ne voit un protocole d'équipe non pertinent.
- **Validation lead-side** [SOURCE: pattern recommandé par Anthropic — "Lead agent must verify completion"] : ne dépend plus uniquement de la qualité du brief.
- **Pattern aligné avec recommandation Anthropic** [SOURCE: https://www.anthropic.com/engineering/multi-agent-research-system principe #2] : *"Each subagent needs an objective, an output format, guidance on the tools and sources to use, and clear task boundaries."*

### Négatives

- **Volume code** [INTUITION 7/10] : ~15 lignes × 12 agents = 180 lignes ajoutées dans `agents/*.md`. Maintenance si l'API évolue.
- **Polling lead** [INTUITION 6/10] : tour de boucle supplémentaire dans le lead pour parser inbox+files. Coût négligeable pour pipelines ≤ 12 agents.
- **N=1 reproducer pour RC10** [OBSERVED: triangulé sur 3 agents dans CETTE team, mais 1 contexte plateforme]. Si Anthropic active SendMessage côté sub-agent demain, l'ordre des canaux devient sous-optimal (mais pas cassé — SendMessage en #3 ne nuit pas).

### Périmètre explicite

**Non couvert** par cet ADR (à conserver, [SOURCE: challenger-arch finding S4 valide]) :
- Sécurité/auth inter-agent (hors scope solo dev)
- Multi-tenant teams [SOURCE: doc Agent Teams — interdit]
- Communication latérale **complexe** (>10 échanges entre 2 pairs) — escalade lead reste la règle [SOURCE: `~/.claude/docs/team-anti-patterns.md`]
- Recovery après crash tmux pane [SOURCE: limitation Claude Code documentée]
- Routing FSM déterministe (Layer 4 v1 supprimé) — pas justifié [OBSERVED: mis-routing absent du top 12 RC d'analyzer]. Reportable dans un ADR séparé si problème devient observable.
- Sentinel tmux (Layer 5 v1 supprimé) — redondant avec `TeammateIdle` natif [SOURCE: finding H4 challenge].

## Risks

| Risque | Sévérité | Marker | Mitigation |
|---|---|---|---|
| Anthropic active SendMessage côté sub-agent → ordre canaux sous-optimal | LOW | [INTUITION 6/10] | SendMessage en #3 reste fonctionnel ; reordering trivial |
| `idle_notification` ne fire pas dans une config tmux particulière | MEDIUM | [INTUITION 5/10] | Layer 1 fallback fichier `_status_*` reste opérationnel |
| Validation `grep` Layer 3 trop laxiste | LOW | [INTUITION 7/10] | Mode warning par défaut, block opt-in |
| Inflation prompts agents (15 lignes × 12) | LOW | [OBSERVED: total agents `wc -l` = 2107 lignes, +180 = +8.5%] | Bloc en bas de fichier, lecture header prioritaire |

## Migration path

**Phase 1 — chirurgical** [INTUITION 8/10 : 30-45 min] :
1. Écrire le bloc commun "Protocole de communication d'équipe" (1 fois, ~15 lignes)
2. Insérer dans les 12 `agents/*.md` (Layer 1)
3. Modifier SKILL.md `/team` : ajouter validation template Layer 3 + boucle polling Layer 2

**Phase 2 — validation** [INTUITION 7/10 : ~1h] :
4. Relancer `/team` sur **5 pipelines de types variés** (Bug, Feature, Refactoring, UI, Review) — N=5 nécessaire pour distinguer 100 % réel d'un taux probabiliste (rappel : RC2 v1 montrait taux d'échec ~50 %, validation N=1 ne discrimine pas)
5. Mesurer le taux de notifications reçues vs spawnés. **Cible : 5/5 STATUS reçus**. Si 4/5 → investiguer le cas qui a échoué AVANT Phase 3
6. Vérifier que canal #1 (`inboxes/`) fire, fallback #2 (`_status_*.md`) fire si #1 indisponible

**Phase 3 — canary** [INTUITION 6/10 : 1 semaine d'usage normal] :
7. Tracker via `token-tracker.sh` (existant) le taux de pipelines bloqués > 1h sans STATUS
8. Si taux > 5 % : itérer sur Layer 2 (timeout, retry policy)

## References

- `state-of-art.md` — benchmark 5 frameworks + 9 patterns scorés [architect-research, 80 % sourcé]
- `diagnosis.md` — 12 causes racines + cross-validation 4/4 RC10 (analyzer-diag, innovator-creative, team-lead, challenger-arch — chacun a livré son artefact via filesystem fallback, pas SendMessage côté sub-agent) [analyzer-diag]
- `creative-angles.md` — 8 angles non-conventionnels, top-2 [innovator-creative]
- `challenge-report.md` — audit adversarial 4.5/10 v1 → cible 8+/10 v2 [challenger-arch]
- [Anthropic — How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) [SOURCE: WebFetch vérifié 2026-04-25]
- [Claude Code — Hooks (28 events)](https://code.claude.com/docs/en/hooks) [SOURCE: WebFetch 2026-04-25]
- [Issue #23415 canonical](https://github.com/anthropics/claude-code/issues/23415) — closed `not_planned` 2026-03-20 [SOURCE: `gh api`]
- [MetaGPT paper — Message Pool + Subscription](https://arxiv.org/html/2308.00352v6) [SOURCE: validé via state-of-art.md]
- [CrewAI #3179 — manager delegates to wrong agent](https://community.crewai.com/t/manager-agent-delegates-task-to-wrong-agent-in-a-hierarchical-process/3179) [SOURCE: pattern reference, applicable seulement si Layer 4 réintégré dans ADR séparé]

## Statistiques markers

[OBSERVED: ce fichier contient 22 [SOURCE], 17 [OBSERVED], 13 [INTUITION] inline = 52 markers sur ~52 décisions techniques distinctes → ≈100 % sourcé, gate ≥ 7/10 respecté (score formel 7.3/10 mesuré par challenger-v2)]
