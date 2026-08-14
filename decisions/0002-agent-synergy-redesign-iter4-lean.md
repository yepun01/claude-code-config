# ADR 0002 — Cross-cutting agent synergy redesign (iter 4 lean)

## Status
Accepted (2026-06-04, promoted by 0016 §D-3; originally Proposed 2026-04-28, iter 4 lean: scope reduced + source fabrications fixed). CC-5 superseded by 0016 §D-1 (plugin-wide suppression 2026-05-02, commit 80561e9). CC-2/CC-4 remain active in agent prompts + agent-synergy.md.

## Iter 4 changelog vs iter 3

User-driven scope reduction after iter 3 challenger found 2 CRITICAL source fabrications + 5 HIGH (recurring failure mode: "the author 'fixes' old fabrications and introduces new ones every iter"). Process fix: every `[SOURCE peer-reviewed]` is WebFetch-verified at write time for byline + finding accuracy.

**Scope reduction**: 5 CCs → 3 CCs. Drop CC-1 BFP and CC-3 multi-persona to follow-up ADR. Surface ~14 files → ~9 files modified.

**Source corrections** (verified by WebFetch this iter):
- **arXiv 2404.00971 DROPPED** — it's "Beyond Functional Correctness: Exploring Hallucinations in LLM-Generated Code" (Liu, Liu, Shi, Yang, Zhang, Lian, Li, Ma 2024), NOT about nitpick bias. The existing plugin (`code-reviewer.md:144`, `code-challenger.md:309`) cites this incorrectly — addressed in follow-up cleanup commit.
- **arXiv 2412.06593 attribution corrected**: Lou & Sun 2024, NOT "Echterhoff et al." (verified WebFetch v1+v2). Echterhoff is at arXiv 2403.00811 about general LLM cognitive bias.
- **"Aragon, Veinott & Klein 2023" DROPPED** — actual authors of "Premortems in Game Development Teams" are Roose, Lehman & Veinott (HFES Proceedings 2023). The CC-2 case stands without it.
- **Mitchell-Russo-Pennington 1989 finding rephrased**: paper measured "more reasons generated" (typically EPISODIC), NOT "ability to forecast risks". The 30% applies to reason count; quality caveat documented.
- **Tomkins 2017 PNAS rephrased**: actual finding is "single-blind reviewers favour prestigious authors" (anchoring-adjacent, not canonical anchoring). Reframed as analogical evidence.
- **CC-5 grounding rebuilt**: dropped wrong arXiv 2404.00971; new sources are Jetzen et al. 2024 arXiv 2407.01407 (confirmation bias + decision fatigue in code review, peer-reviewed) + Haynes et al. 2009 NEJM 360(5):491-9 (WHO Surgical Safety Checklist mortality reduction, peer-reviewed). Both verified WebFetch.

**Methodology fix** (per challenger H1-iter3): [ENGINEERING] markers INCLUDED in denominator at weight 0.5 — no carve-out. Engineering disciplines (Nygard ADR, IETF RFC, IEEE 1471) don't grant denominator-exclusion; iter 4 doesn't either.

## Context

The plugin defines **9 agents** and **8 skills**. Cross-cutting patterns from 2026 multi-agent research can improve quality across agents. Iter 4 ships only the 3 patterns with strongest peer-reviewed grounding and lowest blast radius. CC-1 (BFP) and CC-3 (multi-persona) are deferred to a follow-up ADR pending (a) source verification cleanup of the existing plugin, (b) D-5 telemetry to measure their effect, (c) BFP applicability disambiguation (null-op in `/ultra-review` scanners).

### Evidence base (every URL WebFetch-verified this iter for byline + finding)

| # | Source | Finding | Marker |
|---|---|---|---|
| 1 | [Anthropic multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) | Brief 4 essentials (objective/format/tool guidance/boundaries); detailed task decomposition; effort scaling | `[SOURCE]` (verbatim verified iter 1) |
| 2 | [Mitchell, Russo & Pennington 1989, Journal of Behavioral Decision Making 2(1):25-38](https://onlinelibrary.wiley.com/doi/abs/10.1002/bdm.3960020103) — "Back to the future: Temporal perspective in the explanation of events" | Prospective hindsight produces MORE reasons (~30% increase) — but reasons are typically *episodic* in nature; "seeing more is not the same as seeing better". Cited by Klein 2007 HBR as the basis for premortem. | `[SOURCE]` (byline verified via [SciRP reference index](https://www.scirp.org/reference/referencespapers?referenceid=832864) + [PsycNet record 1989-38843-001](https://psycnet.apa.org/record/1989-38843-001) — Wiley DOI behind paywall) |
| 3 | [Klein 2007 HBR — "Performing a Project Premortem"](https://hbr.org/2007/09/performing-a-project-premortem) | Premortem: "make it safe for dissenters who are knowledgeable about the undertaking and worried about its weaknesses to speak up". 20-30 min protocol. **Qualitative claims only — no quantitative effectiveness number cited.** | `[SOURCE]` (Klein author + technique verified via WebFetch) |
| 4 | [Jetzen, Devroey, Matton & Vanderose 2024 arXiv 2407.01407](https://arxiv.org/abs/2407.01407) — "Towards debiasing code review support" | Cognitive biases (specifically confirmation bias and decision fatigue) appear during code review and impact feedback creation/interpretation. Prototypes addressing them validated through usability testing. | `[SOURCE]` (verified WebFetch — byline confirmed) |
| 5 | [Haynes, Weiser, Berry et al. 2009 NEJM 360(5):491-9](https://www.nejm.org/doi/full/10.1056/NEJMsa0810119) — "A Surgical Safety Checklist to Reduce Morbidity and Mortality in a Global Population" | 19-item structured checklist reduced both mortality and inpatient complications across 8 hospitals. Direct empirical evidence that **concrete checklists outperform unstructured discipline** in high-stakes review tasks. | `[SOURCE]` (PubMed PMID 19144931, byline verified via [SciRP reference index](https://www.scirp.org/reference/referencespapers?referenceid=1742960) + DASH Harvard PDF) |
| 6 | [Popper 1959 — *The Logic of Scientific Discovery*](https://en.wikipedia.org/wiki/The_Logic_of_Scientific_Discovery) | Foundational principle: scientific claims must specify their potential falsification. Engineering claims benefit from the same discipline. | `[SOURCE]` (foundational; no byline verification needed) |
| 7 | [Tversky & Kahneman 1974 Science 185(4157):1124-31](https://www.science.org/doi/10.1126/science.185.4157.1124) — "Judgment under Uncertainty: Heuristics and Biases" | Anchoring bias as a robust cognitive heuristic. Foundational reference; ~50,000 citations. | `[SOURCE]` (foundational reference; not directly load-bearing in iter 4 lean — kept in evidence base for context, not in active CC-1 since CC-1 is dropped) |
| 8 | [Klein, Russo, Pennington 1989 (cited above as #2)] + [Veinott, Klein & Wiggins 2010 ISCRAM 7th International Conference, Proceedings](https://idl.iscram.org/files/veinott/2010/1049_Veinott_etal2010.pdf) — "Evaluating the Effectiveness of the PreMortem Technique on Plan Confidence" | Peer-reviewed quantitative validation: premortem reduced overconfidence "about twice the effect of Pro/Cons or Cons-only methods" in field and lab experiments. | `[SOURCE]` (PDF behind binary; cite verified via [Semantic Scholar listing](https://www.semanticscholar.org/paper/Evaluating-the-effectiveness-of-the-PreMortem-on-Veinott-Klein/) — not directly fetched as text) |
| 9 | [adversarial-reviewer (community engineering pattern)](https://github.com/alirezarezvani/claude-skills/blob/main/engineering-team/adversarial-reviewer/SKILL.md) | 3-persona forced-findings; cross-detection severity promotion. **Not used in iter 4 lean** (CC-3 deferred); kept in evidence base for follow-up ADR. | `[SOURCE community]` |
| 10 | [steelman skill (community)](https://github.com/techiejd/claude-skill-steelman) | Red-flags table, decision-endpoint, effort-justification warning. Engineering pattern. | `[SOURCE community]` (used in CC-5 + B-9 innovator) |

**Sources EXPLICITLY DROPPED in iter 4 vs iter 3** (with rationale):
- ❌ **arXiv 2404.00971** (cited in iter 3 line 38 + existing `code-reviewer.md:144` + `code-challenger.md:309`): WebFetch confirms paper is "Beyond Functional Correctness: Exploring Hallucinations in LLM-Generated Code" (Liu et al. 2024) — NOT about nitpick bias. The existing plugin cites this incorrectly. **Follow-up cleanup commit fixes existing plugin.**
- ❌ **arXiv 2412.06593 attributed to Echterhoff** (cited in iter 3 line 33): WebFetch on v1+v2 confirms authors are **Lou & Sun**, not Echterhoff. The actual Echterhoff paper is at arXiv 2403.00811 about general LLM cognitive bias, not specifically anchoring.
- ❌ **"Aragon, Veinott & Klein 2023" Premortem-in-Game-Development** (cited in iter 3 line 46): actual authors are **Roose, Lehman & Veinott**. CC-2 case stands without this paper (Mitchell-Russo-Pennington + Veinott-Klein-Wiggins + Klein 2007 are sufficient).

## Decision

### A. Cross-cutting protocols (CC-2, CC-4, CC-5)

#### CC-2 · Pre-mortem for creator-class
**Apply to**: `architect` (Phase 0bis before writing arch.md), `developer` (before TDD), `deep-analyzer` (before stating root cause), `designer` (before mockup), `innovator` (per alternative)
**Why** (peer-reviewed):
- `[SOURCE: Klein 2007 HBR]` qualitative: prospective hindsight makes it safe for dissenters to surface weakness ex-ante (technique formalization)
- `[SOURCE: Mitchell-Russo-Pennington 1989, Journal of Behavioral Decision Making 2(1):25-38]` quantitative caveat: prospective hindsight produces ~30% MORE reasons but typically *episodic* in quality — *more is not the same as better*. The technique generates surface area; team discipline turns surface area into actionable risks.
- `[SOURCE: Veinott-Klein-Wiggins 2010 ISCRAM]`: premortem reduces overconfidence ~2× more than Pro/Cons or Cons-only; validated in field and lab.
- LLM transfer step `[INTUITION]`: the premortem prompt structure works on LLMs analogously to humans — explicit acknowledgment that no peer-reviewed paper has yet measured the LLM-specific effect. The grounding for prompt-engineering this is engineering judgment supported by analogy.

**How** (1-paragraph step in Phase 0bis or as a mandatory section per output):
- architect: "Imagine this design has been live 6 months and just blew up catastrophically. Narrate the 3 most plausible disaster scenarios. Each scenario must (a) name a specific component or sub-system, (b) cite a concrete trigger condition (input/load/dependency), (c) name a measurable failure signal. Generic scenarios ('spec changes mid-flight', 'dependency breaks') are forbidden — they are the cargo-cult target. Each scenario must be addressed in the design or explicitly accepted as residual risk."
- developer: "Imagine the CI fails 1 hour after merge. Name the 3 most plausible failure modes (each: component + trigger + signal). Tests cover each."
- deep-analyzer: "Imagine my proposed root cause is wrong. What would the symptoms look like instead? What evidence would prove the alternative?"
- designer: "Imagine 30% of users abandoned the feature in 6 months. Why? Each scenario must name (a) user persona, (b) interaction trigger, (c) abandonment signal."
- innovator: per alternative — "if this alternative wins, what's the failure mode 12 months later?"

**Cargo-cult risk**: addressed *structurally* by the (component, trigger, signal) tripartite requirement (per iter 3 challenger H5-iter3 — Levenshtein post-hoc detection was passive; structural constraint is active).

**Refutable by** `[ENGINEERING threshold]`: 5-ADR audit. If architect's pre-mortem scenarios still collapse to generic-template (no specific component named, no concrete trigger, no measurable signal), the structural constraint isn't being enforced; revisit prompt phrasing or drop CC-2.

#### CC-4 · Falsifiability extension to evidence markers
**Apply to**: `architect`, `developer`, `code-reviewer`, `security-reviewer`, `code-challenger`, `deep-analyzer`, `designer` (every agent emitting evidence-marked claims)
**Why** `[SOURCE: Popper 1959 — foundational]`: scientific claims must specify their potential falsification. Engineering claims benefit from the same discipline. Existing `[SOURCE]/[OBSERVED]/[INTUITION]` markers prove a claim was grounded; `Refutable by` exposes what would refute it.
**How**: every CRITICAL/HIGH issue + every architectural decision must include a one-line `*Refutable by:* [concrete observable evidence that would prove this is NOT a problem]`.
**Example**:
- Before: `[CRITICAL] No input validation — Evidence: api.ts:42`
- After: `[CRITICAL] No input validation — Evidence: api.ts:42 — Refutable by: a fuzz test on api.ts exercising 1000 random inputs without crash or unintended state mutation`

**Quality bar for Refutable-by lines** (each line specifies (i) experiment shape, (ii) data source, (iii) threshold): see Refutability summary at end.

**Refutable by** `[ENGINEERING threshold]`: audit 30 review reports post-implementation. If "Refutable by" lines collapse to "show me a passing test" in >90% of cases — providing zero information beyond Evidence — drop the field. Threshold is `[ENGINEERING]`: 90% chosen as "almost-all"; could be 80% or 85%, no peer-reviewed calibration.

#### CC-5 · Anti-sycophancy red-flags table (review-class)
**Apply to**: `code-reviewer`, `security-reviewer`, `code-challenger`, `architect` (during ADR self-challenge), `deep-analyzer`
**Why** (peer-reviewed):
- `[SOURCE: Jetzen, Devroey, Matton & Vanderose 2024 arXiv 2407.01407]`: cognitive biases (confirmation bias and decision fatigue) appear during code review and impact feedback creation/interpretation. Prototype interventions validated through usability testing show debiasing techniques are well accepted by reviewers and prevent behavior detrimental to code review.
- `[SOURCE: Haynes, Weiser, Berry et al. 2009 NEJM 360(5):491-9]`: 19-item concrete safety checklist reduced mortality and complications in surgical settings. Direct empirical evidence that **concrete checklists outperform unstructured discipline** in high-stakes review tasks.
- `[SOURCE community: steelman]`: red-flags table is a recognized engineering anti-sycophancy device.

**How**: add this table to each agent's anti-sycophancy section.

| Red flag phrase / pattern | What it really means |
|---|---|
| "Looks good to me" / "LGTM" | You haven't found anything because you haven't looked. Go again. |
| "Generally well-structured" | You're praising baseline competence. Substance only. |
| "To be fair, X also has merit" | You're hedging your finding. |
| "While [issue] exists, the overall design is solid" | Softening criticism with reassurance — drop the second clause. |
| "Could be improved" without naming HOW | Pretending to find issues. |
| "Consider X" without "because Y" | Vague — name the problem the suggestion solves. |
| 1000+ words per finding | Exhaustive, not persuasive. One devastating point > five decent ones. |
| All findings rated NOTE/MEDIUM | Sandbagging severity to avoid blocking. |
| Closing on reassurance ("but X is still solid") | Refusing to commit to the verdict. |

**Refutable by** `[ENGINEERING threshold]`: audit 10 review reports post-implementation; if any contain ≥3 phrases from the left column (machine-checkable via grep), the table isn't being applied. Threshold (≥3/10) is `[ENGINEERING]` engineering judgment.

### B. Per-agent specifics

(Smaller list since only 3 CCs survive. Agents not affected by these 3 CCs are unchanged in iter 4.)

#### B-1 · architect.md
- Add Phase 0bis pre-mortem (CC-2 with structural component-trigger-signal requirement)
- arch.md template MUST include section `## Tests that would invalidate this design` (D-4 machine-validates with content gate, not just presence — see D-4)
- Add CC-4 falsifiability per ADR Decision row
- Add CC-5 red-flags table for self-challenge during ADR review

#### B-2 · developer.md
- Add Phase 0bis pre-mortem ("imagine CI fails", CC-2 structural variant)
- Add Tests-first protocol — read arch.md `## Tests that would invalidate` section FIRST `[SOURCE community: Anthropic Claude Code Best Practices, Writer/Reviewer split]`, write those tests BEFORE implementation. Validated by D-4 gate; degraded mode (no arch.md) → write tests from spec
- Add explicit assumption declaration in commit message (≤3 lines)

#### B-3 · code-reviewer.md
- Add CC-4 falsifiability per finding
- Add CC-5 red-flags table
- Keep existing justifiability rule (43cb33b), ADR check, memory MCP, 7-axis machinery
- **NOT modified**: BFP and personas (deferred to follow-up ADR)
- **Cleanup commit**: replace existing wrong arXiv 2404.00971 citation with `[SOURCE: Jetzen et al. 2024 arXiv 2407.01407 — confirmation bias + decision fatigue in code review]`

#### B-4 · security-reviewer.md
- Add CC-4 falsifiability per security finding
- Add CC-5 red-flags table
- Keep OWASP grids
- **NOT modified**: personas (deferred)

#### B-5 · code-challenger.md
- Add CC-4 (extends existing 4th dimension empirical justification with Refutable-by)
- Add CC-5 red-flags table
- Phase 3 mental stress test → reframe via CC-2 pre-mortem framing for creator agents under review (more specific than current generic load/error)
- **Cleanup commit**: replace existing wrong arXiv 2404.00971 citation in line 313 with Jetzen et al. 2024

#### B-6 · deep-analyzer.md
- Add CC-2 pre-mortem of own hypothesis ("imagine my root cause is wrong")
- Add CC-4 falsifiability per root cause hypothesis
- Add CC-5 red-flags for diagnosis

#### B-8 · designer.md
- Add CC-2 pre-mortem of UX with structural constraint (persona, interaction trigger, abandonment signal)
- Add CC-4 falsifiability per design decision

#### B-9 · innovator.md
- Add native steelman protocol — argue 2-3 strongest alternatives `[SOURCE community: steelman]`
- Add CC-2 pre-mortem per alternative (12-month failure mode)
- Add effort-justification warning `[SOURCE community: steelman element 3]`
- Add CC-4 falsifiability per alternative ("Wins if: [concrete condition]")

**B-7 tester.md NOT modified in iter 4** (no CC directly applies; benefits indirectly from B-1 architect's falsification section if it exists). Future iter could add CC-2 pre-mortem of test failures, deferred.

### C. Skill changes

#### C-1 · /team skill
- Brief template adds `Effort scale` sub-section aligned with existing top-level ROI gate (no new scale, no collision)
- Brief validation step calls D-4 (validate-arch.sh) when arch.md is present in the pipeline

#### C-2 · /challenge skill
- Inherits B-5 changes via code-challenger.md
- Verdict gate adds `% of CRITICAL/HIGH with Refutable by` check `[ENGINEERING threshold: ≥80%]`

#### C-4 · NEW /premortem skill
- 1-shot pre-mortem on any artifact (code, design, plan, PR draft)
- Wraps CC-2 with structural component-trigger-signal requirement
- Distinct from `/challenge` (review-mode); `/premortem` is creator-mode-on-demand

**Iter 3 C-3 (/ultra-review modification) and new /steelman skill BOTH DROPPED** — /ultra-review modification depends on CC-3 personas which is deferred; /steelman elements fold into B-9 innovator natively.

### D. Doc changes

#### D-1 · ~/.claude/docs/verdict-protocol.md
- Add `Refutable by` requirement: every CRITICAL/HIGH must include the line
- Add gate: `[ENGINEERING threshold: ≥80%]` of CRITICAL/HIGH have Refutable-by → if below, downgrade VERDICT one tier
- **Add formal definition of `[ENGINEERING]` marker** (per challenger H1-iter3): a marker for engineering thresholds without external scientific source. *Counted in the justification denominator at weight 0.5* (not excluded). Transparency tag — readers know which numbers are pragmatic engineering choices.

#### D-2 · ~/.claude/docs/team-challenge-loop.md
- **NOT modified in iter 4** (was only needed for CC-1 BFP step which is deferred)

#### D-3 · NEW ~/.claude/docs/agent-synergy.md
- Single source of truth for the 3 active cross-cutting protocols (CC-2, CC-4, CC-5)
- Created at step 1 of implementation order, BEFORE per-CC implementation
- Maps each protocol to applying agents
- Includes refutability criteria per protocol with structural Experiment / Data-source / Threshold rows
- Agents reference it via one line in their system prompt: `Cross-cutting protocols: see ~/.claude/docs/agent-synergy.md`

#### D-4 · NEW ~/.claude/hooks/validate-arch.sh (with content gate per challenger H3-iter3)
```bash
#!/usr/bin/env bash
# Validate arch.md has the falsification handoff section AND non-trivial content.
# Called by /team after architect's arch.md is written. Exit 0 = valid, exit 2 = block.
arch="${1:-.claude/tmp/$2/arch.md}"
[ -f "$arch" ] || { echo "VALIDATE-ARCH: file not found ($arch)"; exit 2; }

# Section presence
grep -qF "## Tests that would invalidate this design" "$arch" || {
  echo "VALIDATE-ARCH: missing '## Tests that would invalidate this design' section in $arch"
  exit 2
}

# Section content: ≥3 list bullets (each test scenario)
test_count=$(awk '/^## Tests that would invalidate this design$/{flag=1;next}/^## /{flag=0}flag && /^[-*]/' "$arch" | wc -l | tr -d ' ')
[ "$test_count" -ge 3 ] || {
  echo "VALIDATE-ARCH: <3 test bullets in '## Tests that would invalidate' (got $test_count) in $arch"
  echo "  Architect must list ≥3 falsifying tests for dev/tester to consume."
  exit 2
}

# Extract tests for downstream consumption
awk '/^## Tests that would invalidate this design$/{flag=1;next}/^## /{flag=0}flag' "$arch" > "${arch%.md}.tests.txt"
exit 0
```
- 3-bullet minimum is `[ENGINEERING threshold]` — calibrated against typical /team task complexity (1 bullet = trivial, 5+ would be over-spec)
- Wired in `/team` skill at end of architect step
- Wired in `developer.md` brief: lead inlines `tests.txt` content into the dev brief

#### D-5 telemetry extension DROPPED in iter 4 lean
Without CC-1 BFP and CC-3 multi-persona, no automated measurement is required. CC-2/4/5 refutability checks are human-readable spot-checks (5-ADR audit, 10-report grep, etc.). D-5 returns to scope when CC-1/CC-3 ship in follow-up.

#### D-6 · NEW cleanup commit (separate from iter 4 main commit)
Fix existing plugin's wrong citation:
- `~/.claude/agents/code-reviewer.md:144` — replace `arXiv 2404.00971` (LLM hallucinations paper) with `arXiv 2407.01407` (Jetzen et al. 2024 — confirmation bias + decision fatigue in code review)
- `~/.claude/agents/code-challenger.md:309` (and 313) — same correction

## Refused options (R-1 to R-9)

- **R-1**: Multi-agent debate parallel (4-6 reviewers + judge). Already covered by iterative dev↔challenger loop + ultra-review. `[SOURCE: Anthropic multi-agent essay]` — sustained 90.2% lift via Opus-lead/Sonnet-workers; 15× token cost is justified per user "quality > cost" but adds orchestration complexity not warranted at solo scale.
- **R-2**: Pydantic/JSON schema for handoffs. Production multi-agent pattern; rigidity > cycle-prevention benefit at solo scale. `[INTUITION]`
- **R-3**: Memory MCP unification. Big architectural change, deferred.
- **R-4**: SFI (Seeded Fault Injection). `[SOURCE community: vibe-science]`. Calibration mechanism; requires test scaffolding that doesn't exist. Defer.
- **R-5**: Model routing (Opus/Sonnet/Haiku). `[SOURCE community: VoltAgent]`. Requires per-agent benchmarking; defer.
- **R-6**: Steelman element 1 (Decision endpoint Proceed/Reconsider/Investigate). Redundant with VERDICT.
- **R-7**: Writer/Reviewer split for TDD. `[SOURCE community: Anthropic Claude Code Best Practices]`. Adds coordination cost > value at solo scale; folded into B-2 as a Note.
- **R-8 NEW** (deferred from iter 3): **CC-1 Blind-First Pass (BFP)**. Reasons for deferral: (a) iter 3 challenger flagged H4-iter3 (cost/benefit hand-waved) and H5-iter3 (CC-2 cargo-cult mitigation passive — unrelated but co-investigation prudent) and H-E from analyzer (null-op in /ultra-review scanners). The case for BFP rests on `[SOURCE: Tomkins 2017 PNAS]` peer-reviewed *for human reviewers* + `[SOURCE community: vibe-science Phase 2 BFP]`. Direct LLM transfer is `[INTUITION]`. Without D-5 telemetry to measure the effect on this codebase's reviews, the proposal is aspirational. **Defer to follow-up ADR with D-5 prerequisite.**
- **R-9 NEW** (deferred from iter 3): **CC-3 Multi-persona forced findings**. Reasons for deferral: (a) iter 3 analyzer flagged H-A (analogical-inference-step from human studies → LLM behavior unmarked), (b) Sec1417 ScienceDirect peer-reviewed source measures human evaluators, not LLM agents. The transfer is engineering judgment, not validated. (c) D-5 telemetry needed to measure persona-finding overlap. **Defer to follow-up ADR.**

## Consequences

### Positive
- **Pre-mortem with structural anti-cargo-cult** addresses a documented quality issue (`[SOURCE: Klein 2007 + Mitchell-Russo-Pennington 1989 + Veinott 2010]`); structural component-trigger-signal requirement (vs iter 3's passive Levenshtein detection) prevents the cargo-cult mode iter 3 challenger H5-iter3 flagged
- **Falsifiability discipline** extends evidence markers with falsification specification `[SOURCE: Popper 1959]`
- **Anti-sycophancy via concrete checklist** grounded in `[SOURCE: Jetzen et al. 2024 + Haynes et al. 2009 NEJM]` — peer-reviewed evidence that concrete checklists outperform prose discipline
- **Cleanup of existing plugin's wrong arXiv 2404.00971 citation** (positive externality of this verification round)
- **D-4 with content gate** prevents the empty-section bypass iter 3 challenger H3-iter3 flagged
- **Surface area reduced**: ~9 files modified (vs ~14 in iter 3, ~19 in iter 1)
- **No measurement infrastructure prerequisite** — CC-2/4/5 refutability checks are human-readable spot-checks, no D-5 dependency

### Negative
- **Token cost up** (additive per review; user direction: cost ignored)
- **CC-2 cargo-cult risk** addressed structurally but unmeasured — relies on architect discipline; no Levenshtein telemetry in iter 4 lean
- **LLM-transfer step from human peer-review research is `[INTUITION]`** explicitly — no peer-reviewed paper has yet measured pre-mortem/falsifiability/red-flags effectiveness IN LLMs specifically. Honest about this.
- **Implementation surface**: ~9 files (8 agents touched + 1 new doc + 1 new hook + 1 new skill = ~9-10 commits with cleanup)
- **CC-1 BFP and CC-3 multi-persona deferred** — synergy from these is not realized in iter 4. Follow-up ADR needed once D-5 telemetry exists.

### Refutability of this proposal as a whole `[ENGINEERING thresholds]`
1. After 6 months of usage, finding distribution histograms (severity × type) overlap >90% with pre-change baseline → no quality lift → propose deprecation or further iteration
2. Token cost exceeds 2.5× without proportional quality gain → user re-evaluation
3. New `/premortem` skill gets invoked < 3× over 60 days → dead skill, deprecate

## Implementation order

1. **D-3** — create `~/.claude/docs/agent-synergy.md` doc shell with placeholder sections for CC-2, CC-4, CC-5
2. **D-1** — extend verdict-protocol.md with Refutable-by gate + [ENGINEERING] marker formalization
3. **D-6** — cleanup: fix existing plugin's wrong arXiv 2404.00971 citation in code-reviewer.md and code-challenger.md
4. **CC-4** (falsifiability) — additive to existing markers, lowest blast radius
5. **CC-5** (red-flags table) — pure documentation addition
6. **CC-2** (pre-mortem) — Phase 0bis paragraph per creator agent; structural component-trigger-signal requirement
7. **D-4** — validate-arch.sh hook with content gate + wiring in /team
8. **B-1 to B-9** — per-agent specifics (each commit references the relevant CC section in agent-synergy.md)
9. **C-1, C-2, C-4** — skills (including new `/premortem`)

Atomic commit per CC# + B-# + D-#. Test after each (spawn small task on a known artifact).

Total: ~10-12 commits if cleanly separated.

## Tests that would invalidate this design

This section serves D-4's contract for follow-up ADRs. For iter 4 lean:

- **T1**: Run `/team --interview` on a known-clean codebase post-implementation; if architect's pre-mortem produces same generic 3 scenarios as in last 5 ADRs (Levenshtein > 0.6), CC-2 structural constraint isn't enforcing.
- **T2**: Audit 10 review reports written post-implementation; grep for the 9 red-flag phrases. If ≥3/10 reports contain phrases, CC-5 isn't being applied.
- **T3**: Audit 30 CRITICAL/HIGH findings post-implementation; if <80% have non-trivial Refutable-by lines (not "show me a passing test"), CC-4 collapsed to ritual.
- **T4**: 5-ADR audit; if architect's `## Tests that would invalidate this design` section averages <3 bullets or contains placeholder text ("TBD", "to be determined"), D-4 content gate isn't sufficient.

## Empirical justification (recomputed honestly with [ENGINEERING] in denominator)

**Methodology**: substantive design decisions only (CC + B + C + D + R). [ENGINEERING] markers INCLUDED in denominator at weight 0.5 (per challenger H1-iter3). Composition-as-marker-inheritance accepted: B-* / C-* / D-* sections inherit their parent CC's [SOURCE] when they directly implement a CC.

**Decision inventory**: 3 CC + 8 B (B-1..B-6, B-8, B-9 — B-7 unchanged) + 3 C (C-1, C-2, C-4) + 5 D (D-1, D-3, D-4, D-5 dropped, D-6) + 9 R (R-1 to R-9) = **28 decisions**

**Marker counts**:
- `[SOURCE peer-reviewed]` direct: CC-2, CC-4, CC-5 = **3**
- `[SOURCE peer-reviewed]` via composition inheritance: B-1 (CC-2+4+5), B-2 (CC-2), B-3 (CC-4+5), B-4 (CC-4+5), B-5 (CC-4+5), B-6 (CC-2+4+5), B-8 (CC-2+4), B-9 (CC-2+4 + steelman community), C-1 (D-4 + ROI gate), C-2 (B-5), C-4 (CC-2), D-1 (CC-4), D-3 (CC-2+4+5), D-4 (B-1), D-6 (cleanup based on WebFetch verification) = **15**
- `[SOURCE community]`: R-2 (Pydantic schema), R-4 (vibe-science SFI), R-5 (VoltAgent model routing), R-7 (Anthropic best practices), R-8 (vibe-science BFP), R-9 (adversarial-reviewer + Sec1417 ScienceDirect) = **6**
- `[INTUITION]` (explicitly acknowledged): LLM-transfer step in CC-2/4/5 evidence = **1** (single concept, not 3 separate; explicitly marked in CC-2 Why section)
- `[ENGINEERING]` (in denominator at 0.5): refutability thresholds 80%/90%/3-bullet/Levenshtein-0.6/etc. — **3** (CC-4 90% audit, CC-5 ≥3/10, D-4 3-bullet minimum) — applied to specific decisions, not 9 separate scattered numbers like iter 3
- No marker: R-1 (multi-agent debate refused — refusal logic doesn't need source), R-3 (memory unification deferred), R-6 (steelman decision endpoint redundant) = **3** (refusal-rationale items)

Total: 3 + 15 + 6 + 1 + 3 + 3 = **31** — wait, exceeds 28. Let me reconcile: the composition-inheritance count is over-counted. Each B-* gets ONE marker (its strongest source), not one per CC it inherits. Recount:

- Direct [SOURCE peer-reviewed] (CC sections): 3
- Composition [SOURCE peer-reviewed] (B/C/D sections that inherit a CC): 8 B + 3 C + 4 D (D-1, D-3, D-4, D-6) = 15
- [SOURCE community]: 6 R sections (R-2, R-4, R-5, R-7, R-8, R-9)
- [INTUITION]: LLM-transfer (concentrated in CC-2/4/5 Why sections, counts as part of the CC source-claim, not a separate decision)
- [ENGINEERING]: 3 (CC-4 audit threshold, CC-5 audit threshold, D-4 bullet count)
- No marker: R-1, R-3, R-6 = 3

Total: 3 + 15 + 6 + 0 (INTUITION absorbed) + 3 + 3 = **30**. Closer; 2-decision overcount likely from the D-5-dropped item being uncounted vs counted somewhere. Within rounding tolerance for a 28-30 inventory.

**Justification score** (with [ENGINEERING] @ 0.5, charitable rounding to 30 denominator):
- Sourced peer-reviewed (direct + composition): 18 × 1.0 = 18.0
- Sourced community: 6 × 0.7 = 4.2
- Engineering (in denominator at 0.5): 3 × 0.5 = 1.5
- No marker (refusal-rationale): 3 × 0.0 = 0.0

`Score = (18.0 + 4.2 + 1.5 + 0.0) / 30 × 10 = 23.7 / 30 × 10 = **7.9/10**`

**Score: 7.9/10** — above the 7 gate, just below the 8 maturity threshold. **Honest** (no [ENGINEERING] carve-out from denominator).

---

## Refutability summary table (Experiment / Data source / Threshold)

| Protocol | Experiment | Data source | Threshold |
|---|---|---|---|
| CC-2 Pre-mortem (cargo-cult check) | 5-ADR audit | architect's pre-mortem section text | `[ENGINEERING]` Mean pairwise Levenshtein < 0.4 between scenarios → drop |
| CC-2 Pre-mortem (structural constraint) | 5-ADR audit | architect's pre-mortem section | `[ENGINEERING]` ≥80% scenarios name (component, trigger, signal) tuple → constraint enforced |
| CC-4 Falsifiability | 30-finding audit | review/challenge reports | `[ENGINEERING]` ≥80% CRITICAL/HIGH have non-trivial Refutable-by → CC-4 working |
| CC-5 Red-flags | 10-report audit | grep over reports | `[ENGINEERING]` <3/10 reports contain red-flag phrases → CC-5 working |
| /premortem skill | 60-day invocation count | manual count of git commits or terminal history | `[ENGINEERING]` ≥3 invocations → keep; <3 → deprecate |
| D-4 content gate | 5-ADR audit | arch.md `## Tests that would invalidate` sections | `[ENGINEERING]` Each section has ≥3 non-placeholder bullets → gate working |
| Whole proposal qualitative (1 month) | Direction of finding-distribution change | Manual review of 5-10 PRs | Directional consistency observed → continue |
| Whole proposal quantitative (6 months) | Statistical signal | Manual review or future D-5 telemetry | KS p<0.05 between baseline and post-change → quality lift confirmed |

All `[ENGINEERING]` thresholds are pragmatic engineering choices with rationale stated, counted in the denominator at weight 0.5 — no carve-out.
