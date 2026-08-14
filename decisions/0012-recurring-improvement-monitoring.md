# ADR 0012 · recurring-improvement-monitoring

Status: Accepted (2026-05-10). Decision item « no auto-backlog » superseded partial by 0013 §D7. Implementation: Sprint 3 — `hooks/improvement-monitor.sh` + skill `/improvement-monitor`. First report: `state/MONITORING-2026-05.md`.
Date: 2026-05-10

## Context

Le user veut "rester au max dans le temps" sur les pratiques d'agent-coding et l'écosystème Claude Code. Le survey manuel du 2026-05-10 (cf. `state/IMPROVEMENT-BACKLOG.md`, sources `tmp/improvement-survey-20260510/`) a coûté ~30 min agent-time + synthèse lead. 22 gaps internes croisés à 15 patterns externes. Tenu manuellement = ne tient pas dans la durée — entre 2.1.116 et 2.1.138 le changelog liste >150 items et l'écosystème (AGENTS.md cross-tool, plugin marketplace, native sandboxing, dreaming, OTel GenAI) bouge tous les mois [OBSERVED `state/IMPROVEMENT-BACKLOG.md`, `tmp/improvement-survey-20260510/survey-external.md` items #4/#5/#8/#11/#13]. L'infra existe déjà : skills `/loop` et `/schedule` shippés, hook SessionStart pour ré-injection, knowledge-graph Memory MCP `alwaysLoad: true`.

## Decision

Skill `/improvement-monitor` (ou cron `claude -p`) qui tourne **mensuellement** avec scope étroit :
1. Fetch deltas depuis le dernier run : Claude Code changelog (par version), Anthropic Engineering blog (par date), optionnel `claude-plugins-official` releases
2. Diff vs inventaire plugin courant (relire `agents/`, `skills/`, `hooks/`, `decisions/` pour décider "déjà couvert oui/non/partiel")
3. Output unique : `state/MONITORING-{YYYY-MM}.md`, max 30 lignes, items >5 = warning de focus
4. Lecture par le user au prochain `/team` ou session resume (le hook session-resume-journal pointe dessus)
5. **Pas** de génération automatique de backlog ni d'ADR — c'est un radar, pas un autopilot

Pas de Gate, pas de migration `/evals`-style. Si signal trop faible 3 mois de suite → kill, on reviendra à du manuel.

## Tests that would invalidate this design

- **T1 — signal mort** : 3 runs consécutifs produisent 0 items actionable (ni shippés, ni archivés explicitement par le user). Le monitor n'apporte rien que la lecture passive du changelog ne donnerait → scrap.
- **T2 — pas de causation backlog** : sur 2 cycles backlog (Sprint 1 + Sprint 2 du IMPROVEMENT-BACKLOG.md), <3 items proviennent du monitor. Le monitor n'influe pas les décisions → redondant avec le `/team` ad-hoc.
- **T3 — coût > valeur** : tokens mensuels >$2 OU latence par run >5 min OU le user déclare "je savais déjà X sans le monitor" >50% du temps → ROI négatif.

## Consequences

Remplace les `/team regarde les best practices` ad-hoc par une cadence structurée (~1 page/mois). Surface à maintenir : 1 skill + 1 cron. Question ouverte : auto-curate Memory MCP en parallèle (dreaming, X3 backlog) ou rester radar pur ? Décider à l'usage post-T1.
