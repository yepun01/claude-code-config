# ADR 0008 — claude-atlas-viewer unified architecture v4 (UX layer)

## Status

Proposed (2026-04-30). **Partially supersedes ADR 0004 D-2** (`.claude/decisions/0004-viewer-multi-plateforme.md:55` — "Navigation primaire : Command Palette comme entrée unique"). The primauté navigationnelle de la palette ⌘K est retirée : iter 4 a montré empiriquement que l'utilisateur pense par projet, pas par query. La sidebar de 22 projets (D-1 ci-dessous) devient le nav primaire ; ⌘K est conservé comme cross-content search différée (cf. *Out of scope* §). La **grammar parser-combinator** (ADR 0004 D-2 sub-decisions précédence/empty-query/saved-views) reste load-bearing pour cet usage cross-content search future et n'est PAS supersedée.

Le reste d'ADR 0004 reste valide : couche technique (PWA Preact + IndexedDB + `viewer-server.ts` + Tailscale Serve, 4 endpoints + assets statiques, security headers, indexer pipeline, claim atomicity D-1, NOTES.jsonl D-7). Cet ADR couvre la **information architecture et UX layer** — what is shown, how it is navigated, why those choices over the alternatives that were tried and rejected. Les deux ADRs évoluent à cadences différentes (technical perf tuning vs. UX iteration), coupled enough que tout breaking change de l'un référence les deux dans la supersede chain.

Implementation has not yet started. The 4 design iterations referenced below were carried in `claude.ai/design` (Anthropic's design tool, accessed via the `claude-in-chrome` MCP), with mockups discarded after each invalidation rather than progressively refined — `[OBSERVED: tmp/atlas-redesign-1777546871/claude-design-prompt-{P0,v2,v3,v4}.md]`.

## Context

### The 4 design iterations and their invalidations

The viewer was stuck at "looks fine but doesn't speak" through three successive proposals before the v4 unification landed. The trajectory matters because each rejection narrowed what the right answer could not be.

**Iteration 1 — Claim Palette (Vue 1) + Index Home (Vue 6).** Command palette as primary nav with `verdict:fail since:7d agent:reviewer` query syntax + a homepage of KPI tiles (refutability gate 87%, INTUITION ratio 22%, untested claims 12, recent activity, right rail). User feedback verbatim: *"c'est sympa mais peu compréhensible, beaucoup d'informations, je ne sais pas si elles sont vraiment pertinentes ou s'il y a des liens entre elles"* `[OBSERVED: tmp/atlas-redesign-1777546871/brief.md:15]`. **Invalidated** — the KPI tiles were epistemic-protocol jargon detached from any cause, and the same events appeared under three angles (recent activity / KPI / right rail) with no visible causal link between them.

**Iteration 2 — Saga Thread.** The JOURNAL rendered as a chat-bubble thread (system bubbles per session, user bubbles for the next-step prompts), with a violet "saga rail" linking the chained sessions (e.g. ADR 0003 design → step 5 scaffolding → step 6 hypotheses → step 7 prep) so the causal chain became visible at a glance. **Validated** — for the first time the viewer matched the user's mental model that *the user talks to the plugin through `/team`, and the plugin replies in narrative form*. Saga Thread becomes a reusable component the rest of the architecture composes on top of.

**Iteration 3 — P0 Wrapper.** Global header + 6 categorical tabs (Activity / Architecture / Agents / Skills / Hooks / Evals) + an "active teams" dock. **Invalidated on the categorical axis itself**: the user does not think *"I want to read about Agents in general"* — the user thinks *"what is happening in `TheTeacher` right now? what about `conductor-la-paz`?"*. Slicing by subject-matter category buries the working unit (the project) under a taxonomy of materials. Once stated this way it is obvious, but it took building the tabs to see it.

**Iteration 4 — Project Navigation.** Sidebar of 22 projects + a chat-hero per project. **Validated as direction**, not as final shape — the chat-hero crowded out the historical and decisional content the user also needs.

**Iteration 5 — Atlas Unified v4.** Consolidation: keep the 22-project sidebar from iter 4, keep the Saga Thread from iter 2, add a `Pulse` landing page so "what's running now" is the default answer, cap at 3 sub-pages per project, ship the Vibe Notch as a single sticky surface for permission events. User feedback: *"j'aime"*. This ADR freezes that consolidation.

### Two structural inversions that drove the answer

**Inversion 1 — categorical → project-centred.** Validates the design criteria item *"break at least one of: linear / mono-vue / file-centred"* `[SOURCE: .claude/decisions/0004-viewer-multi-plateforme.md:16]`. Iter 3 broke `mono-vue` but kept `categorical`, which was the wrong bone to break. Iter 4 swapped axes: each project becomes its own NavigationSplitView root; the categorical tabs disappear; cross-cutting concerns (the plugin itself) are demoted to a **single meta entry** in the sidebar rather than promoted to the primary axis.

**Inversion 2 — page proliferation → 3 sub-pages cap.** The earlier protos drifted toward "one page per type of artefact" (one for ADRs, one for sessions, one for hooks, one for evals…). The v4 cap is **3 sub-pages per project, full stop**: `Pulse` (now), `History` (narrative), `Decisions` (durable). Anything that does not belong in one of those three is either inline (chips, dock, notch) or it does not belong in the viewer.

### Mental model shipped: "the user talks to the plugin via /team"

This is the line that connects everything. The Saga Thread iteration surfaced it: every JOURNAL entry is the plugin replying to a user prompt, and every `Next:` line in an entry is the plugin handing back a half-formed prompt the user can edit and re-fire. The composer chat sticky-bottom (D-5 below) is the materialisation of that loop — *the prompt is always one keystroke away*, and the next-step suggestion is always pre-fillable from context.

### Hard repoussoirs (acted, not negotiable)

- **No abstract KPI tiles** without context (refutability gate %, INTUITION ratio %, untested claim count). They are protocol jargon, not user-facing signal. Allowed only inside Decisions when scoped to a single ADR.
- **No categorical decomposition** as primary axis (Agents/Skills/Hooks/Evals as top-level tabs). The `Plugin global` meta entry is the *only* place that aggregates across categories, and even there the inner shape is `Pulse / History / Decisions`, not `Agents / Skills / Hooks`.
- **No "rendered markdown in stylish cards" without semantic value-add**. Rendering an ADR or a JOURNAL entry must add a timeline, a saga rail, a verdict pill, a clickable link — not just typography.
- **No page proliferation past 3 per project**. The composer chat is *one thing present everywhere*, not a fourth page.

## Decision

The architecture is composed of **7 concrete sub-decisions** (D-1 through D-7). Each is small enough to be implemented and falsified in isolation; together they form the unified v4 shell.

### D-1 · Sidebar of 22 projects + Plugin-global meta entry

**Layout.** Fixed left column ~280 px on Mac (`≥900 px` viewport, `NavigationSplitView` semantic), drawer (hamburger) on iPhone (`<900 px`). Two sections, in order:

```
SECTION "Méta" (1 entry, pinned top)
  ● Plugin global — ~/.claude/

SECTION "Projets" (22 entries, scroll, fuzzy-searchable)
  ● TheTeacher              (violet)
  ○ conductor-la-paz        (teal)
  ○ conductor-almaty        (pink)
  ○ conductor-havana        (orange)
  ○ conductor-san-jose      (lime)
  ○ Epitech-Cloud           (amber)
  ○ Epitech-RGPD            (green)
  ○ Epitech-Cloud-functions (neutral)
  ○ RobloxGames             …
  + 14 more (scroll)
```

22 is the count observed in `~/.claude/projects/` `[OBSERVED: ls ~/.claude/projects/ | wc -l → 22 at 2026-04-30]`; the indexer reads this directory directly so the sidebar tracks reality without a separate registry. **Fuzzy search** (`⌘K` Mac, top input iPhone) is the primary access path past ~10 projects — scrolling 22 entries is acceptable but searching scales.

**Tone colorisation.** Each project gets one of 8 hues (`neutral / green / teal / pink / lime / orange / violet / amber`). The mapping is **deterministic from the project basename** (stable hash → palette index) so a project always renders the same colour across sessions and devices. Rationale: at 22 entries colour gives a faster scan-recognise loop than name alone — `[SOURCE community: nngroup.com/articles/visual-feedback-loop]` "scannability through colour-coded categories".

*Refutable by:* if a longitudinal study (the user himself, 2 weeks of usage) shows zero recognition lift — i.e. the user reads the project name letter-by-letter rather than recognising the colour glyph first — the colour is decorative and should be removed in favour of plain monochrome rows. Threshold: time-to-correct-project-click on the third+ sidebar visit per session, target <800 ms; if median >1500 ms, the colour failed.

**Plugin-global as meta-section.** The first sidebar entry is `● Plugin global — ~/.claude/`, scoped to the cross-cutting concerns of the plugin itself (the 6 plugin ADRs, the 9 agents, the 9 skills, the 11 hooks, the global JOURNAL). It uses the **same shell** as a regular project (header + 3 sub-pages) — no special template, just a different scope. This keeps the user's mental model symmetric: *plugin = special project*, not *plugin = the chrome around projects*.

### D-2 · Vibe Notch — sticky permission/event surface

The Vibe Notch is a top-centred sticky pill, ~480 px wide on Mac (centred on the main column, not the viewport), full-width on iPhone. It is *the* single visual surface for permission events and risky-action confirmations. The name (and reference) comes from Apple's Dynamic Island `[SOURCE community: developer.apple.com/design/human-interface-guidelines/live-activities]` — a single sticky surface that morphs between idle, ambient, and acute states depending on the system event. Adapted here for AI-agent permission events.

**Three states**:

| State | Trigger | Height | Tint | Affordances |
|---|---|---|---|---|
| `idle` | No pending event | ~32 px | discreet green tonal | "● 3 teams running · all auto-OK ▼" — click ▼ expands a bottom-sheet with the 3 teams and their live narration |
| `permission_pending` | `PreToolUse` hook emits a permission request | ~64 px | amber tonal | shows the *exact* path/command being requested, three buttons: `[Allow once]` `[Allow + remember]` `[Deny]`. Disappears the instant a button is clicked. |
| `risky_action` | sensitive op (`rm -rf`, `git push --force`, `.env` write blocked, etc.) | ~96 px expanded | red, bold border | `■ DESTRUCTIVE — atp-exec wants \`git push --force origin\`` with `[Pause team]` `[Allow]` `[Deny + reason]`. The `Allow` button is intentionally to the **right** of `Pause`, not the leftmost button, to defeat mis-click muscle-memory. |

**Latency target: <100 ms** from hook event to notch visible state change `[ENGINEERING — derived from Nielsen 1993 *Response Times: The 3 Important Limits*: 100 ms is the limit for "response feels instantaneous"; SOURCE community: nngroup.com/articles/response-times-3-important-limits]`. This bounds the implementation: the wire protocol between hook and frontend must be a server-sent event or websocket, not a poll, and the rendering path must avoid layout thrash.

*Refutable by:* if telemetry shows median notch-render latency >250 ms over 50 events, the notch breaks the "feels live" illusion and we must move it from sticky-overlay to a fixed status bar that the user *expects* to lag (different visual contract). Conversely, if the user clicks `Allow` in <300 ms median for `risky_action` events (i.e. ignores the bandeau), the bandeau is failing as a friction surface — treat as bug, widen friction (typed reason mandatory).

The Vibe Notch is the only sticky element competing for the top of the viewport; this is intentional — multiple sticky competitors degrade scan to the point users tune them all out `[SOURCE community: nngroup.com/articles/sticky-headers]`.

### D-3 · Project header (name + glyph + Trust chip + 3 tabs)

Sub-bar directly under the Vibe Notch, sticky, ~56 px:

```
📁 TheTeacher · Trust: [Normal ▼] · Last activity 2h ago
─────────────────────────────────────────────────────────
 [● Pulse]   History    Decisions
```

- **Name + glyph** — glyph is the file-emoji 📁 by default, overridable per-project via `~/.claude/projects/<name>/.viewer/glyph` (single emoji file, opt-in, not required).
- **Trust profile chip** — clickable dropdown, 4 levels (`Strict / Normal / Trusted / Full auto`), each with a 1-line description in the dropdown so the user does not have to remember the semantics. The chip itself is colour-tinted (Strict → warn-amber, Normal → text-muted, Trusted → pass-green tonal, Full-auto → accent-blue). When the project history is clean over the last N sessions a hint appears: *"💡 You could upgrade to Trusted (saves ~14 prompts/week)"*. Threshold for the hint = 10 consecutive sessions without a permission denial `[INTUITION — calibration target, refine after 4 weeks of telemetry]`.
- **3 tabs** — `Pulse` (default), `History`, `Decisions`. The active tab gets an underline in `--accent`. **No fourth tab is allowed**; if a future need surfaces, it lives inline within one of the three or it does not ship.
- **Last activity ETA** — relative time (`2h ago`), refreshed on focus.

*Refutable by:* if the Trust chip is clicked <1× per week per active project on average over 4 weeks, it is dead UI — demote to a settings page link.

### D-4 · 3 sub-pages — Pulse / History / Decisions

This is the cap. Three sub-pages per project. The shell is identical for `Plugin global`.

#### D-4a · Pulse (default landing)

Single column, sections stacked, each independently collapsible. Order:

1. **Active teams** — one card per running team with **live narration** (D-6 below). If 0 teams active, the section is **absent** (no skeleton, no empty-state copy — silence is the right answer).
2. **Last sessions (3)** — three condensed Saga Thread bubbles (1-line summary each: title + verdict glyph + linked ADR + relative time). Click → navigate to `History` with scroll-to-anchor.
3. **Active ADRs** — inline horizontal chips (`📎 ADR 0001 student-state-machine` `📎 ADR 0003 evaluation-protocol`). Click → navigate to `Decisions`.
4. **Composer chat** (D-5 below) — sticky bottom, never scrolls away.

Pulse is the **default landing** because the most frequent question the user asks the viewer is *"what's running, what's next?"* `[OBSERVED: tmp/atlas-redesign-1777546871/brief.md:48-55]`. Optimising for this single question dictates the layout.

*Refutable by:* if telemetry over 4 weeks shows the user lands on Pulse and immediately switches to History or Decisions in >40% of project visits, Pulse is the wrong default — switch to History. Threshold: switch-rate from Pulse-default within 3 seconds.

#### D-4b · History

**Reuses the Saga Thread component verbatim**, scoped to the current project. No regeneration, no new chrome. The saga rail (the violet vertical line linking chained sessions of the same ADR) carries through. The composer chat sticky-bottom is identical to Pulse. This sub-page exists *to consume* the validated iter-2 component.

#### D-4c · Decisions

Two-column layout on Mac (~60% list / ~40% preview), single-column with push-detail on iPhone. Left: ADR list ordered chronologically inverted, each entry as a minimal card (title, status [Active / Superseded / Proposed], date, 1-line context). Right: rendered preview of the selected ADR — clean markdown (headings, code blocks, lists, tables), no toolbar. **Two pseudo-entries pinned at the top** of the list: `🗺 ROADMAP.md` and `📌 STATE.md`, treated as first-class even though they are mutable (they are the *current state*, not durable decisions, but they belong in this sub-page because they are durable artefacts the user reasons over). Composer chat sticky-bottom is identical.

### D-5 · Composer chat sticky-bottom (scoped, omnipresent)

A ~80 px sticky bottom bar on every sub-page of every project (and on the Plugin-global shell). Anatomy:

```
┌──────────────────────────────────────────────────────────────┐
│  💬 Discuss with TheTeacher LLM                              │
│  ┌────────────────────────────────────────────────┐         │
│  │ /team go step 8                                │  [▶]    │
│  └────────────────────────────────────────────────┘         │
│  Context: 12 ADRs · JOURNAL 47 entries · STATE.md           │
└──────────────────────────────────────────────────────────────┘
```

Three properties together make this the right move:

1. **Always one keystroke from the prompt.** Materialises the mental model "user talks to plugin via /team". Scoped — the LLM has access to the **current project's** ADRs / JOURNAL / STATE / ROADMAP, not the union. Switching projects switches scope.
2. **Pre-fillable from context.** When a Saga Thread bubble or a Pulse next-step is clicked-with-modifier (or on iPhone, swipe-right), its `Next:` line pre-fills the composer. This is the actionable handoff the iter-2 review flagged as missing.
3. **Slash-commands auto-completed** from `~/.claude/skills/*/SKILL.md` — `/team`, `/discuss`, `/spec`, `/learn`, `/evals`, `/commit`, `/challenge`, `/ultra-review`, `/premortem`. Placeholder rotates examples (`/team go step 8`, `/discuss permission flow`, `/learn vibe-island patterns`).

*Refutable by:* if usage data over 4 weeks shows <1 composer submission per project-session on average, it is occupying ~80 px of vertical real estate for nothing — collapse it to a 32 px expandable bar `[SOURCE community: nngroup.com/articles/utility-vs-usability — utility threshold: a feature must be used].`

### D-6 · Live narration in active team cards (NOW / NEXT / QUEUE)

Each active team card in the `Pulse > Active teams` section renders a 3-line live narration, fed by the `TaskList` and `STATUS` performatives the existing teammate-comm protocol already emits `[OBSERVED: .claude/decisions/0001-team-comms.md]`:

```
✦ atlas-redesign-1777546871 · running 38min
"Repenser visuellement le viewer claude-atlas"

▶ Now: code-reviewer reading agents/code-reviewer.md
   Task 5/9 · ~90s remaining

⏭ Next: scan compliance markers across 6 docs
⏸ Queue: 2 decisions pending (1 risky)

[Voir thread complet]  [Pause]
```

Mapping:

| Line | Source |
|---|---|
| **Now** | the in-flight task in the lead's `TaskList` (the one whose status flipped to `in_progress` most recently) and the active teammate's last `STATUS` performative |
| **Next** | the next `pending` task in the same TaskList |
| **Queue** | the count of `pending` tasks beyond `Next` + a flag if any of them is tagged risky |

ETA (`~90s remaining`) is computed from the median duration of the same `subagent_type` over the last 20 runs, fallback "—" if <5 samples available `[ENGINEERING — derived from existing token-tracker.sh metrics]`.

*Refutable by:* if the `Now` line is wrong (i.e. the actual current operation diverges from what is shown) more than 5% of the time over 100 events, the polling-cadence or the protocol mapping is broken and the feature must be hidden behind a feature flag until fixed.

### D-7 · Scope segregation — Plugin-global vs Project

Two **scopes**, sharing the same shell:

- **Plugin-global** (`~/.claude/`): aggregates the plugin's own ADRs (currently 0001 team-comms, 0002 agent-synergy, 0003 evaluation-protocol, 0004 viewer-multi-plateforme, 0005 evals-skill-design, 0006 evals-skill-multifile + this one), the global JOURNAL (`state/JOURNAL.md`), the global ROADMAP, the agents/skills/hooks definitions. The composer chat at this scope is the *meta LLM* — it can answer questions about the plugin itself.
- **Project**: aggregates the project's local `.claude/decisions/`, `.claude/state/`, scoped slice of the global JOURNAL (entries tagged with the project name). The composer chat is scoped to the project's content only.

Routing rule: clicking a sidebar entry sets the scope; the URL reflects it (`/p/TheTeacher/pulse`, `/meta/decisions`); refreshing preserves it. There is no "all projects mixed" view — that view was iter-3, and it was wrong.

## Consequences

### Positive

- **Scope clarity at scan-time.** The user knows in <1 second what they are looking at: tone-colour glyph + project name in the sidebar (highlighted) + project name + glyph + tabs in the header. The two redundant signals are intentional — the sidebar can be off-screen on iPhone, the header is always visible.
- **Narrative-first viewer.** Saga Thread (History) is the durable narrative; Pulse is the live one; Decisions is the durable index. Each answers a different question the user already asks today. No KPI dashboard fights for attention.
- **Page count is a budget.** 3 sub-pages × 23 scopes (22 projects + meta) = 69 logical pages, but only 3 templates to design and maintain. Adding a feature means deciding which of `Pulse / History / Decisions` it belongs in — or rejecting it.
- **The Vibe Notch pattern is transposable.** It generalises beyond permission events: future "agent X just shipped a verdict" toasts, "tester started running" affordances, etc. all fit into the same single sticky surface without competing with anything.
- **Composer chat surfaces the mental model.** "I talk to the plugin through /team" stops being implicit lore and becomes a UI element.
- **Project-centred axis aligns with how `~/.claude/projects/` is already structured.** Zero-cost source-of-truth: the indexer reads the directory; the viewer reflects it.

### Negative

- **3 sub-pages = 3 transitions to design.** Pulse → History scroll-anchor, Pulse → Decisions chip-click, History → Decisions ADR-tap. Each transition has its own "preserve scroll position" semantics. Estimated +1 dev week vs. 1 sub-page.
- **Vibe Notch = 3 states + transitions to wire to the hook layer.** Requires a new SSE/websocket channel between `viewer-server.ts` and the frontend (ADR 0004 currently only documents `POST /notes` and `POST /token/rotate`). This is a real new surface that ADR 0004 must amend in a follow-up. Risk: if the wire protocol is naive (e.g. polling at 1 Hz), the <100 ms latency target fails — see D-2 *Refutable by*.
- **Sidebar 22 entries must stay performant.** With virtualised scrolling unnecessary at 22 (acceptable to render all rows), but the **fuzzy search** must run <16 ms per keystroke. At 22 names × ~30 chars, this is trivial in JS, but if/when the user accumulates 100+ projects (already plausible with `conductor-workspaces`), the implementation must switch to an incremental match index. **Threshold to revisit: 50 sidebar entries.**
- **The `Plugin global` entry being one of the sidebar rows (rather than a chrome-level affordance) means it is one click away, never one glance away.** Acceptable trade because the symmetry it gains is worth more than the half-second click cost; documented for the future "did we regret this?" check.
- **Tone colour mapping is deterministic but not curated.** Two adjacent projects could collide on the same hue. With 22 projects and 8 hues, ~3 collisions per palette draw expected (pigeonhole). Mitigation: when 2 sidebar-adjacent rows share a hue, the second one switches to its hue's *secondary* tint. Adds complexity; tracked as residual risk.

### Neutral

- **This ADR does not cover the technical layer.** Wire protocol, IndexedDB schema, SPA bundle size, security headers, query grammar — all live in ADR 0004. Any breaking change to either should reference both.
- **No commitment on motion specifics.** Tab-switch transitions, Vibe Notch state morphs, scroll-anchor easing — left to the implementation phase, constrained only by the 250 ms / `cubic-bezier(0.4, 0, 0.2, 1)` token from ADR 0004.
- **Telemetry is required for most refutability clauses.** That telemetry does not yet exist in the plugin; building it is a prerequisite for falsifying this design after the fact, and is in scope for the implementation ADR that follows.

## Tests that would invalidate this design

These are the falsifiable claims the design is staking. Each has a concrete component, a trigger condition, and a measurable signal — a failure of any one is grounds for a superseding ADR rather than a silent patch.

- **T1 — 5-second scope-recognition test (D-1 + D-3).** *Component:* sidebar + project header. *Trigger:* present the viewer to the user (n=1 minimum, n=5 ideal `[SOURCE: Nielsen 1994 *Usability Inspection Methods* — 5e personne expose ~85% des problèmes de surface ; aligné sur ADR 0004:120]`) showing an arbitrary project page, ask *"which project are you looking at?"*. *Signal:* correct answer within 5 seconds, ≥4/5 cases. **If <60% answer correctly within 5 s, the scope-cue redundancy (sidebar highlight + header) is insufficient — the design is broken on its primary scan-recognise contract.**
- **T2 — Permission-pending visibility test (D-2).** *Component:* Vibe Notch in `permission_pending` state. *Trigger:* fire a `PreToolUse` hook event mid-session while the user is reading any sub-page. *Signal:* user notices the notch and resolves it within 3 seconds (Allow/Deny click). **If median time-to-resolve >5 s over 20 events, the notch is failing as a real-time surface — the location/colour/animation does not draw the eye.**
- **T3 — Live narration accuracy test (D-6).** *Component:* `Now` line of an active team card. *Trigger:* run a `/team` task with ≥3 sub-tasks, observe the card every 30 s while polling the actual TaskList in parallel. *Signal:* `Now` line matches the TaskList's `in_progress` task. **If divergence >5% over 100 events, the protocol mapping is buggy — feature flag off until fixed.**
- **T4 — Composer chat utility test (D-5).** *Component:* sticky-bottom composer. *Trigger:* 4 weeks of usage telemetry. *Signal:* ≥1 composer submission per project-session on average. **If <1, the composer is dead UI taking 80 px — collapse to 32 px expandable bar.**
- **T5 — Pulse default-landing test (D-4a).** *Component:* `Pulse` as default sub-page. *Trigger:* 4 weeks of usage telemetry. *Signal:* user remains on Pulse for ≥3 seconds in <40% of project visits before switching tabs. **If switch-within-3s rate ≥40%, Pulse is the wrong default; promote History or Decisions instead.**
- **T6 — Trust-chip discoverability test (D-3).** *Component:* Trust profile chip in project header. *Trigger:* 4 weeks of usage. *Signal:* chip clicked ≥1× per week on at least one active project. **If <1 click/week across all projects, the chip is dead UI — demote to a settings-page link.**
- **T7 — Sidebar fuzzy-search performance test (D-1).** *Component:* fuzzy-search input over 22 sidebar entries. *Trigger:* keystroke profiling under DevTools. *Signal:* per-keystroke render <16 ms (60 fps budget). **If >16 ms median, switch the implementation to an incremental match index even at 22 entries; revisit threshold for 50+.**

## Suggested implementation order

Sequencing optimised for risk-front-loading: validate the surfaces that cannot be cleanly refactored before building the cheaper pieces.

1. **Sidebar + Plugin-global meta entry (D-1, D-7).** Read `~/.claude/projects/`, render rows, hash-tone-colourise, fuzzy search. Validates the indexer + scope routing.
2. **Project header with tabs (D-3).** Pure layout; the Trust chip can be a static dropdown initially (no telemetry-driven hint yet).
3. **`Pulse` skeleton (D-4a).** With the 3 sections empty / static-mocked. Live narration (D-6) wired in step 5.
4. **Vibe Notch (D-2).** Hook channel design + 3 states. **This is the riskiest piece** because of the <100 ms latency contract; build the canary early.
5. **Live narration wiring (D-6).** Reads `TaskList` + `STATUS` performatives, computes ETA from token-tracker history.
6. **Composer chat (D-5).** Slash-completion from `~/.claude/skills/*/SKILL.md`, scoped LLM context assembly.
7. **History sub-page (D-4b).** Mostly mounting the existing Saga Thread component into the project shell.
8. **Decisions sub-page (D-4c).** Two-column layout, ADR-list + preview, pinned ROADMAP/STATE entries.

Each step ships behind its own feature flag; T1–T7 above can be exercised once steps 1–6 are live.

## Explicit out-of-scope

- **Authentication / multi-user.** ADR 0004 already addresses Tailscale + bearer token rotation; this UX layer assumes single-user context.
- **Offline-first behaviour.** The PWA is installable per ADR 0004; offline-degraded UI states are deferred.
- **Mobile-degraded UI (smaller than iPhone 13 mini).** Touch targets and layout target ≥375 px width; below that, the sidebar drawer remains usable but the project header may overflow — accepted.
- **Search across project content (full-text on JOURNAL/ADR bodies).** `⌘K` here scopes to project-name fuzzy search only. Cross-content search is deferred to a future ADR; the parser-combinator query grammar from ADR 0004 D-2 is the natural target.
- **Multi-window / multi-project comparison.** A project-centred axis means one project at a time; if the user wants to compare, they switch. No "split view of two projects" affordance.

## Identified risks

| Risk | Mitigation | Residual |
|---|---|---|
| Vibe Notch wire protocol latency >100 ms | SSE/websocket from day 1, canary T2 in step 4 of implementation | If unfixable, fall back to fixed status bar with different visual contract |
| Tone-colour collisions in 22-row sidebar | Adjacent-row secondary-tint fallback | Acceptable visual ambiguity ~3 cases/palette |
| `Plugin global` lost in 23-row sidebar | Pinned to top of `Méta` section, distinct section header | If telemetry shows <2 visits/week to the meta entry, promote to chrome (re-visit decision) |
| Telemetry needed to falsify T4–T7 does not exist yet | Build minimal usage-event log (project_visit, tab_switch, composer_submit, chip_click) as part of the implementation ADR | Without it, T4–T7 cannot be exercised, design becomes ossified-by-default |
| 3-sub-page cap pressure as plugin grows | Document the cap as a *budget*, not a *limit*; supersede this ADR rather than silently adding tabs | Acceptable governance overhead |
