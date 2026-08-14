# ADR 0022 — Aesthetic precedence between `/claude-design` and the official `frontend-design` skill

## Status
Proposed (2026-08-13)

Date: 2026-08-13
Supersedes: — (records a precedence rule between two coexisting skills; changes no prior decision)
Superseded by: —

## Context

Two skills carrying aesthetic prescriptions are loadable in the same session:

- `skills/claude-design/SKILL.md` — local, builds a copy-pasteable prompt for the external product claude.ai/design. Its template pins `Mood: sober, dense, confident, no ornament` `[OBSERVED :85]` and lists `Frontier features: 3D, voice UI, video, ornamental SVG illustrations` under OUT-OF-SCOPE `[OBSERVED :69]`.
- `frontend-design@claude-plugins-official` — enabled in `settings.json` `[OBSERVED enabledPlugins]`, applies to frontend code the agent writes itself. It prescribes `gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows, decorative borders, custom cursors, and grain overlays` `[OBSERVED :34]` and `Motion: Use animations for effects and micro-interactions` `[OBSERVED :32]`.

The 2026-08-12 audit (`tmp/audit-claude-design/rapport.md`, workflow `wf_6247f174-070`) flagged this as a frontal contradiction — an agent loading both receives opposite orders. Re-reading the official skill in full shows the conflict is **narrower than reported**, and that most of the apparent opposition is agreement:

- **Fonts** — both forbid Inter, Roboto, Arial, system stacks; the official skill additionally names Space Grotesk, which the local anti-slop list also bans. No conflict.
- **Purple gradients on white** — both forbid. No conflict.
- **Commitment** — the official skill says `Commit to a cohesive aesthetic` `[OBSERVED :31]`; the local template's AESTHETIC COMMITMENT section is the same idea, operationalized. No conflict.

The decisive clause is the official skill's own closing rule: *"Match implementation complexity to the aesthetic vision. Maximalist designs need elaborate code with extensive animations and effects. **Minimalist or refined designs need restraint**, precision, and careful attention to spacing, typography, and subtle details."* `[OBSERVED :40]` The ornament list is therefore a **palette conditioned on the stated vision**, not an unconditional prescription. `sober / no ornament` is a legitimate vision under that rule, not a violation of it.

What genuinely conflicts is smaller and lives elsewhere: the local template hardcodes `Grid: 12-col with 24px gutter`, `Max content width: 960px`, `Section spacing: 96px/48px` `[OBSERVED :90-94]`, while the official skill calls for `Unexpected layouts. Asymmetry. Overlap. Diagonal flow. Grid-breaking elements.` `[OBSERVED :33]` and names `predictable layouts and component patterns` as generic AI aesthetics `[OBSERVED :36]`. That one is real and is not resolved by the precedence rule below.

## Decision

**D-1 — Disjoint scopes, stated explicitly.** `frontend-design` governs frontend code **this agent writes**. `/claude-design` governs a prompt **handed to an external product**. They are not competing defaults for the same artifact, and neither is authoritative over the other's domain. Any future skill carrying aesthetic prescriptions declares its domain in the same terms.

**D-2 — The AESTHETIC COMMITMENT line wins inside its own artifact.** When `/claude-design` produces a prompt, its committed tone word governs every later choice in that prompt, including against the official ornament palette. This is not an override of the official skill: it is the application of its own §40 rule, which subordinates ornament to the declared vision. Recorded so it is not re-litigated as a violation.

**D-3 — Outside a stated commitment, the official skill is the default.** For frontend code written locally with no aesthetic commitment on the table, `frontend-design` governs — including motion and background treatment. `/claude-design`'s `no ornament` is scoped to the prompt it builds and does **not** leak into local component work.

**D-4 — The grid conflict is recorded as open, not resolved.** The local template's fixed 12-col / 960px / 96-48px scaffold is in genuine tension with `Unexpected layouts. Asymmetry. Grid-breaking elements.`, and it is the same defect the audit found independently: LAYOUT and PALETTE are not parameterized by the tone word, so the template imposes one spatial aesthetic regardless of the commitment the user was just asked to make. This ADR does **not** decide it. It is deliberately left to the separate arbitration on parameterizing the template, so that a precedence rule is not used to smuggle in a template redesign.

## Alternatives considered

- **Disable `frontend-design`.** Rejected: it covers a domain `/claude-design` does not touch (code the agent writes), it is maintained upstream, and 4 of the 6 local anti-slop lines have no equivalent in it — removing it loses coverage without gaining coherence.
- **Delete the local anti-slop block as redundant.** Rejected on measurement: line-by-line comparison gives 2 of 6 lines covered (fonts partially, gradients), not the ~80 % claimed by two agents during the audit. Layout slop, tone anchors, asset slop and frontier features are absent from the official skill.
- **Declare a single global aesthetic doctrine.** Rejected: it would force local component work into `sober / no ornament`, which is a prompt-level commitment for one external product, not a house style.

## Consequences

- An agent loading both skills has a stated precedence and no longer has to guess. The apparent contradiction is closed without either skill being weakened.
- `/claude-design` keeps a prescription (`no ornament`) that reads as opposing the official skill; anyone re-auditing will flag it again unless they read this ADR. Accepted cost — D-2 exists precisely to answer that re-audit.
- The grid tension (D-4) stays open and will resurface. That is intentional: it belongs to the template-parameterization decision, not here.
- The precedence rule is prose in an ADR, enforced by nothing. No hook, no gate. If it turns out agents ignore it, that is evidence for encoding the commitment in the skill body rather than in governance.

## Tests that would invalidate this design

- **D-1/D-3 falsified** if an agent with both skills loaded produces local component code that suppresses motion and background treatment while citing `/claude-design`'s `no ornament` — i.e. the prompt-scoped rule leaked into code the agent writes. Check: ask for a local component with no aesthetic brief, inspect whether animations and background depth are present.
- **D-2 falsified** if a claude.ai/design output built from a `sober / no ornament` commitment is graded worse than the same intent left unconstrained. That would mean the local commitment is not a legitimate vision under §40 but a handicap.
- **The whole ADR is voided** if `ClaudeDesign` becomes reachable (statsig `tengu_omelette_fouet` flips, canary: `ToolSearch(query="select:ClaudeDesign")` returns a schema, or the `design` command's `argumentHint` contains `<prompt>`). The native hub fetches live Claude Design instructions via `get_claude_design_prompt` *rather than shipping a vendored copy* `[OBSERVED binaire 2.1.220]` — at which point `/claude-design`'s frozen template, and therefore this precedence question, disappears with it.
- **The premise is falsified** if the official skill's §40 clause is removed upstream, making the ornament palette unconditional. Re-read `plugins/cache/claude-plugins-official/frontend-design/*/skills/frontend-design/SKILL.md` after any plugin update.
