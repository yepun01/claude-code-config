# ADR 0006 — Multi-file structure for the `/evals` skill (split from single SKILL.md)

## Status
Proposed (2026-04-30). Supersedes 0005 D-1 (single-file convention) — partial. All other decisions of ADR 0005 (D-2 spawn orchestration, D-3 schema, D-4 stat helper, D-5 templates content + pre-flight gate, D-6 idempotence, D-7 case selection, D-8 variance metric) remain in force unchanged. Implementation reconciled by 0018: multi-file split shipped (skills/evals/{scripts,templates,references}); eval-program paused sunset 2026-09-04 (0016 §D-4).

## Context

ADR 0005 D-1 chose to keep `~/.claude/skills/evals/SKILL.md` as a single file, modeled on the convention of all other plugin skills (`/team`, `/commit`, `/spec`, `/challenge`, etc., all single-file). That decision carried an explicit *Refutable by:* clause:

> "if SKILL.md exceeds ~600 lines of prose [...], the single-file approach has failed and the skill must be split — but the split goes via a NEW ADR superseding this one, not silent refactor." `[OBSERVED: .claude/decisions/0005-evals-skill-design.md:39]`

**Trigger fired**. Current state: `wc -l ~/.claude/skills/evals/SKILL.md` = **604 lines** (`[OBSERVED]`). Step 7 of ADR 0005's implementation order shipped successfully (commit `e5a1051`, 15/15 trials DONE), proving the *behaviour* is correct — but the structural ceiling has been breached. ADR 0005's own falsification clause now mandates a superseding ADR.

**Compounding pressure**: step 8 of ADR 0003 (the next pipeline) will add a `--full-pilot` subcommand (13 cases × 2 trials × 2 conditions, ~$52 envelope per ADR 0003 line 209) and an A/B toggle generation mode (ADR 0003 §D-3 line 85+). Both expansions will add prose/bash to SKILL.md. Continuing single-file would push SKILL.md well past 800 lines before the CC-5 pilot even runs. The split must create headroom *now*, before step 8 work begins.

**New evidence not available at ADR 0005 write time**: the official Anthropic `anthropics/skills` repository documents `scripts/`, `references/`, and `assets/` as the canonical subdirectory structure for skills, with SKILL.md as the orchestration entrypoint and siblings loaded on-demand by the LLM (Read for references, Bash for scripts). `[SOURCE: github.com/anthropics/skills — skills/skill-creator/SKILL.md + repo README]` `[SOURCE: code.claude.com/docs/en/skills]` This invalidates ADR 0005 D-1's premise that "siblings are not auto-loaded" implied "must inline everything" — only the *frontmatter* auto-loads for discoverability; sibling content is lazy-loaded as the LLM needs it, with no token cost when not needed.

### Sources used (verified at write time)

| # | Source | Used for | Marker |
|---|---|---|---|
| 1 | `github.com/anthropics/skills` (README + `skill-creator/SKILL.md`) | Canonical skill directory structure: `SKILL.md` + optional `scripts/` + `references/` + `assets/` | `[SOURCE: github.com/anthropics/skills]` |
| 2 | `code.claude.com/docs/en/skills` (Anthropic official docs) | "Reference supporting files from your SKILL.md so Claude knows what they contain and when to load them" — confirms lazy-load semantics | `[SOURCE: code.claude.com/docs/en/skills]` |
| 3 | `~/.claude/decisions/0005-evals-skill-design.md:39` | The *Refutable by:* clause that triggers this superseding ADR | `[OBSERVED]` |
| 4 | `~/.claude/decisions/0003-evaluation-protocol.md` D-3 + line 209 (corpus pilot envelope) | Step 8 expansion pressure justifying headroom | `[OBSERVED]` |
| 5 | `wc -l ~/.claude/skills/evals/SKILL.md` = 604 | Empirical line breach | `[OBSERVED]` |
| 6 | `~/.claude/CLAUDE.md` "Justifiability rule" + "Surgical changes" sections | Each new file must have ≥1 caller; touch only what the split requires | `[OBSERVED]` |

## Decision

### D-1 · Split SKILL.md into entrypoint + `scripts/` + `references/` + `templates/`

`~/.claude/skills/evals/` becomes:

```
~/.claude/skills/evals/
├── SKILL.md                       # entrypoint, orchestration prose, target ≤300 lines
├── scripts/
│   ├── init.sh                    # extracted from current SKILL.md L35-272 (§init bash)
│   ├── run-pre-pilot.sh           # extracted from current L284-467 (§run --pre-pilot bash)
│   └── report-pre-pilot.sh        # extracted from current L490-577 (§report --pre-pilot bash)
├── references/
│   └── methodology.md             # TP/FP matching, kappa protocol, Refutable-by grid (consolidated from current L139-200ish + RUBRIC.md template prose)
└── templates/
    ├── HYPOTHESES.md.tmpl         # extracted from init.sh heredoc (current L71-134)
    ├── RUBRIC.md.tmpl             # extracted from init.sh heredoc (current L136-147)
    └── corpus/
        ├── sast-sql-injection/
        │   ├── prompt.md          # current L151-157
        │   ├── code/lookup.py     # current L159-182
        │   └── ground_truth.jsonl # current L184-187
        ├── design-dead-code/
        │   ├── prompt.md          # current L191-197
        │   ├── code/cart.ts       # current L199-223
        │   └── ground_truth.jsonl # current L225-229
        └── sycophancy-bait/
            ├── prompt.md          # current L233-239
            ├── code/auth.js       # current L241-263
            └── ground_truth.jsonl # current L265-269
```

**Existing out-of-skill files unchanged**: `~/.claude/scripts/eval-stats.sh` (the shared stats helper) stays put per ADR 0005 D-4 — it is invoked by every later pilot, not just `/evals`, and lives outside the skill folder by design.

**Explicit file-mapping table (current SKILL.md line range → new path)**:

| Current SKILL.md range | Lines | New location | Caller |
|---|---|---|---|
| L1-10 (frontmatter + Project context) | 10 | SKILL.md (kept verbatim) | skill loader (frontmatter auto-load) |
| L11-27 (Goal + Subcommand dispatch) | 17 | SKILL.md (kept verbatim) | LLM at skill invocation |
| L29-34 (§init prose) | 6 | SKILL.md, condensed to ≤15 lines + `bash ~/.claude/skills/evals/scripts/init.sh` invocation | LLM dispatch on `/evals init` |
| L35-272 (§init bash + heredoc payloads) | 238 | `scripts/init.sh` (logic) + `templates/**` (heredoc payloads as files; init.sh `cp -n` from `$(dirname "$0")/../templates/`) | SKILL.md §init |
| L274-277 (post-init summary instructions) | 4 | SKILL.md (kept verbatim) | LLM after init.sh returns |
| L279-283 (§run --pre-pilot prose) | 5 | SKILL.md, condensed to ≤15 lines + `bash ~/.claude/skills/evals/scripts/run-pre-pilot.sh` invocation | LLM dispatch on `/evals run --pre-pilot` |
| L284-477 (§run bash: pre-flight gates + spawn loop) | 194 | `scripts/run-pre-pilot.sh` | SKILL.md §run |
| L479-489 (§report prose + arg-passing convention) | 11 | SKILL.md, condensed to ≤15 lines + `bash ~/.claude/skills/evals/scripts/report-pre-pilot.sh "$TS_ARG"` invocation | LLM dispatch on `/evals report --pre-pilot` |
| L490-577 (§report bash) | 88 | `scripts/report-pre-pilot.sh` | SKILL.md §report |
| L579-580 (post-report notes) | 2 | SKILL.md (kept verbatim) | LLM after report returns |
| L582-592 (Dispatch reminder) | 11 | SKILL.md (kept verbatim) | LLM on empty/unknown `$ARGUMENTS` |
| L594-605 (Strict rules) | 12 | SKILL.md (kept verbatim) — load-bearing constraints stay in entrypoint | LLM at every dispatch |
| (new) | — | `references/methodology.md` (~80 lines: TP/FP matching, kappa, Refutable-by grid expanded from RUBRIC sketch) | SKILL.md §run prose links it for the LLM to Read on demand |

**Projected SKILL.md after split**: frontmatter (10) + project context (small, kept) + goal (10) + dispatch (7) + 3 condensed subcommand sections (~15 each = 45) + post-action notes (~10) + dispatch reminder (11) + strict rules (12) + "Further reading" pointer to references/ (~5) ≈ **~150 lines total, target ceiling ≤300**. Headroom: ≥300 lines available for step 8 expansion (`run --full-pilot`, `run --cc-5`, `add-case` subcommands) before re-breaching the 600 ceiling. `[ENGINEERING]`

**Why extract templates as actual files (not heredocs in init.sh)**:
- Templates become reviewable/diffable as their native format (Python/TS/JS/JSONL/Markdown) instead of escaped strings nested inside bash. `[SOURCE community: bash heredoc maintenance pain — common pattern in dotfiles + skill repos]`
- `init.sh` reduces from a 240-line heredoc dispenser to a ~50-line `cp -n` loop with explicit logging — easier to audit for the idempotence claim of ADR 0005 D-6.
- Templates evolve independently of the script that copies them (e.g. fix a typo in `auth.js` without touching `init.sh`).
- Justifiability holds: every template file's caller is an explicit `cp -n "$TPL_DIR/<file>" "evals/<dest>"` line in `init.sh`. `[OBSERVED: CLAUDE.md Justifiability rule]`

**Why a new `references/` for methodology**: TP/FP matching protocol, Cohen's κ inter-rater procedure, and the 3-criterion Refutable-by grid are *methodological* prose that the LLM consults *occasionally* (during run/report or when the user asks "how does TP matching work"), not on every dispatch. Currently they live as 4-line stubs in `RUBRIC.md` (which is a *user-editable* template, not skill documentation). Promoting them to `references/methodology.md` (a) gives them the line-budget they deserve (~80 lines vs current 4-line sketch), (b) keeps SKILL.md focused on dispatch, (c) lets `RUBRIC.md` template stay minimal as a user-edit surface. `[SOURCE: code.claude.com/docs/en/skills — "large reference docs don't need to load into context every time the skill runs"]`

*Refutable by:* if after the split, `wc -l ~/.claude/skills/evals/SKILL.md` exceeds 300 lines on the first developer commit, the size budget for SKILL.md was wrong and the split structure must be re-divided (e.g. extract Strict Rules to `references/strict-rules.md`).

### D-2 · SKILL.md invocation contract — absolute paths, no working-dir assumptions

Each subcommand block in SKILL.md invokes its script via:

```bash
bash ~/.claude/skills/evals/scripts/<subcommand>.sh [args]
```

**Why absolute path with `~`**: the LLM dispatch happens in the user's project directory (`pwd` = project root). Scripts must read templates from the skill's install dir (`$(dirname "$0")/../templates/`) and write to `$(pwd)/evals/`. Hard-coding `~/.claude/skills/evals/scripts/` removes any ambiguity about *which skill instance* is being invoked. `[SOURCE community: bash dotfiles best practice — explicit absolute paths over PATH lookups for skill scripts]`

**Why scripts derive `TPL_DIR` from `$(dirname "$0")`** instead of hardcoding `~/.claude/skills/evals/templates`: scripts must work whether installed in `~/.claude/skills/evals/` (personal) or `<repo>/.claude/skills/evals/` (project-scoped). The `dirname "$0"` pattern resolves at invocation time. `[SOURCE: anthropics/skills — `{baseDir}` resolves to skill install dir for the same reason]`

*Refutable by:* if `bash ~/.claude/skills/evals/scripts/init.sh` invoked from a project with `pwd ≠ ~/.claude/...` either fails to find templates OR writes `evals/` outside `$(pwd)`, the contract is broken; scripts must take an explicit `--project-dir "$(pwd)"` arg passed by SKILL.md.

### D-3 · Append-only HYPOTHESES.md amendments-log entry on procedure changes

The split changes the *procedure* (a) flag/path conventions for invoking pre-flight gates, (b) the runner shell-out shape (was inline bash in SKILL.md, now `bash scripts/run-pre-pilot.sh`), (c) report regen path. Per ADR 0003 §D-4 anti-amendment rule + the existing `## Amendments log` section in `evals/HYPOTHESES.md` (`[OBSERVED: ~/.claude/evals/HYPOTHESES.md:11,156`), this constitutes a procedure amendment that MUST be logged.

**Required amendments-log entry** (developer adds during step 7 → 8 transition commit):

```
### YYYY-MM-DD HH:MM:SSZ — /evals skill structure split (ADR <new-number>)

The `/evals` skill is reorganized into SKILL.md (entrypoint) + scripts/ +
references/ + templates/. Pre-flight gate logic, spawn loop, and report
regeneration now live in `~/.claude/skills/evals/scripts/*.sh` and are invoked
by SKILL.md via `bash <abs-path>` calls. Behaviour is preserved (T1-T5 below
constrain this). Per ADR 0003 §D-4: this is a procedure amendment, not a
hypothesis amendment — Q1-Q6 resolutions and CC-5 hypotheses are unchanged.
Pre-existing `evals/runs/20260430T111218Z/` artifact remains valid (T2 below).
```

*Refutable by:* if the developer ships the split commit without an amendments-log entry referencing this ADR, ADR 0003 §D-4 audit anchor is broken; the next pilot run loses its pre-registration anchor for the procedure change.

### D-4 · Justifiability — every new file has an explicit caller

Per `~/.claude/CLAUDE.md` "Justifiability rule": every new file or exported symbol introduced by the split MUST have ≥1 caller in the diff. Caller table:

| New file | Caller (in the same diff) |
|---|---|
| `scripts/init.sh` | SKILL.md §init block invokes via `bash ~/.claude/skills/evals/scripts/init.sh` |
| `scripts/run-pre-pilot.sh` | SKILL.md §run --pre-pilot block invokes via `bash ~/.claude/skills/evals/scripts/run-pre-pilot.sh` |
| `scripts/report-pre-pilot.sh` | SKILL.md §report --pre-pilot block invokes via `bash ~/.claude/skills/evals/scripts/report-pre-pilot.sh "$TS_ARG"` |
| `references/methodology.md` | SKILL.md "Further reading" section + §run prose ("for TP/FP matching see references/methodology.md") |
| `templates/HYPOTHESES.md.tmpl` | `scripts/init.sh` `cp -n "$TPL_DIR/HYPOTHESES.md.tmpl" evals/HYPOTHESES.md` |
| `templates/RUBRIC.md.tmpl` | `scripts/init.sh` `cp -n "$TPL_DIR/RUBRIC.md.tmpl" evals/RUBRIC.md` |
| `templates/corpus/<stub>/**` | `scripts/init.sh` `cp -rn "$TPL_DIR/corpus/<stub>" evals/corpus/<stub>` |

The reviewer (`code-reviewer` + ultra-review compliance scanner) MUST grep for these callers in the developer's diff before approving. Zero callers on any new file = orphan = block (CRITICAL).

*Refutable by:* if any new file in the split lacks a caller in the diff (verified by `grep -r "<filename>" ~/.claude/skills/evals/`), the file is orphan and the diff must be revised before merge.

## Consequences

### Positive

- **Headroom restored**: SKILL.md drops from 604 → ~150 lines, leaving ≥300 lines of budget for step 8 (`run --full-pilot`, `run --cc-5`, `add-case`) before any re-split is needed. `[ENGINEERING]`
- **Templates become first-class artifacts**: stub code (`auth.js`, `lookup.py`, `cart.ts`) is reviewable/diffable in its native syntax instead of buried in bash heredocs — IDE syntax highlighting, language-server linting, and reviewability all improve. `[OBSERVED: CLAUDE.md "prose code" rule favours legible artifacts]`
- **Aligns with official Anthropic skills convention**: `scripts/` + `references/` + `assets/` is the documented pattern in `anthropics/skills` and `code.claude.com/docs/en/skills`; future plugin contributors (or future-me) recognize the structure immediately. `[SOURCE: github.com/anthropics/skills]`
- **Lazy-loading wins on context budget**: `references/methodology.md` is only Read by the LLM when actually needed (during `run` or when user asks methodological questions), not on every `/evals` dispatch — net token saving across typical sessions. `[SOURCE: code.claude.com/docs/en/skills]`
- **Easier unit-testability**: scripts can be invoked with fixture inputs (`bash scripts/init.sh` in a tmpdir, then assert tree state) without going through the full skill dispatch loop. `[SOURCE community: standard practice for testable bash extraction]`
- **No behaviour change**: every test that passed against the pre-split SKILL.md (15/15 trials in `evals/runs/20260430T111218Z/`) must continue to pass, gated by T1-T5 below. The split is structural-only.

### Negative

- **More files in the skill folder**: `ls ~/.claude/skills/evals/` goes from 1 entry to ~5 (SKILL.md + 3 dirs + the new structure beneath). Mitigated by: (a) the new structure is the *documented* Anthropic convention, so cognitive cost is one-time; (b) `tree` output remains <30 lines, well within readability. `[ENGINEERING]`
- **Deviation from the other plugin skills (`/team`, `/commit`, etc., all single-file)**: this skill becomes the first multi-file skill in the plugin. Mitigated by: (a) explicit "Generalizable convention" section below documents *when* a split is justified; (b) `/team` SKILL.md at 455 lines has not yet hit its own ceiling — the precedent doesn't force eager-splitting other skills; (c) ADR 0005 D-1's original convention rationale ("symmetric with other skills") is replaced by a sharper rationale ("split when budget breached, otherwise stay single-file"). `[OBSERVED: existing single-file skills, line counts]`
- **Two paths for similar bash logic**: scripts/run-pre-pilot.sh and (future) scripts/run-cc-5.sh will both have pre-flight gate logic. This is a *future* duplication risk, not a current one — the design accepts this for now and notes the mitigation (extract to `scripts/lib/pre-flight.sh` if duplication appears) in the Pre-mortem section below. Premature abstraction would violate CLAUDE.md "no premature abstraction" rule. `[OBSERVED: CLAUDE.md folder cleanliness]`
- **Path-resolution surface area grows**: scripts must derive `TPL_DIR` correctly across personal-skill (`~/.claude/skills/evals/`) and project-skill (`<repo>/.claude/skills/evals/`) installs. Mitigated by D-2 contract (`$(dirname "$0")/../templates/`) + falsification test below. `[ENGINEERING]`

### Neutral / explicitly out of scope

- The shared stats helper `~/.claude/scripts/eval-stats.sh` is **not moved** — it is invoked by `/evals` AND by every later pilot pipeline, so it lives outside the skill folder by design (per ADR 0005 D-4, unchanged). `[OBSERVED: ADR 0005 D-4]`
- The `gen-control-agents.sh` and pre-commit hook from ADR 0003 §D-3 are unaffected. `[OBSERVED]`
- Other skills (`/team` 455 lines, `/commit`, `/spec`, `/challenge`, etc.) are not split by this ADR. The "Generalizable convention" section below documents the *trigger* for future splits, but acting on it is out of scope here per CLAUDE.md "Surgical changes" rule. `[OBSERVED: CLAUDE.md]`

## Tests that would invalidate this design

Per CC-4 of `~/.claude/docs/agent-synergy.md` and the `~/.claude/hooks/validate-arch.sh` contract (≥3 list bullets in this section).

- **T1 — Behaviour preservation on `/evals init`**: in a fresh `/tmp/evals-test-<ts>/` working tree, run `/evals init` (post-split) and capture the resulting tree state via `find evals -type f -exec sha256sum {} \; | sort`. Compare against the same command captured against the pre-split SKILL.md (commit `e5a1051^`). Component: `scripts/init.sh` + `templates/**`. Trigger: invocation on empty dir. Expected signal: byte-identical sha256 manifests. If even one file differs (e.g. `auth.js` lost a trailing newline during heredoc-to-file extraction, or `HYPOTHESES.md.tmpl` has an extra blank line), the heredoc extraction was lossy and the file content must be normalized. This is the load-bearing test for "no behaviour change" claim.

- **T2 — Report regen on pre-existing run dir**: invoke `/evals report --pre-pilot evals/runs/20260430T111218Z` (the existing successful run from step 7) using the post-split skill. Component: `scripts/report-pre-pilot.sh`. Trigger: command on a real, pre-split-era run directory. Expected signal: regenerated `evals/reports/pre-pilot-20260430T111218Z.md` is byte-identical to the version generated by the pre-split skill (or differs only in the timestamp embedded in the report header — diff with `--ignore-matching-lines='generated_at'`). If the report differs in stat values, fallback decision, or verdict string, the report-script extraction broke parity and step 7's verdict is no longer reproducible — blocker for any later pilot that compares against this baseline.

- **T3 — Pre-flight gate enforceability after extraction**: in a working tree with `evals/HYPOTHESES.md` modified-but-uncommitted (`git diff --quiet HEAD -- evals/HYPOTHESES.md` returns non-zero), run `/evals run --pre-pilot`. Component: `scripts/run-pre-pilot.sh` Gate B. Trigger: uncommitted hypotheses + run command. Expected signal: skill exits non-zero with the message referencing ADR 0003 §D-4 and Nosek 2018, and zero `evals/runs/<ts>/` artifacts are created. If the script proceeds and writes any jsonl entry, the pre-registration discipline is bypassed by the split — the gate must be re-instated as the very first command in `scripts/run-pre-pilot.sh` before any directory creation.

- **T4 — Path resolution across install locations**: `cp -r ~/.claude/skills/evals /tmp/test-skill-copy && bash /tmp/test-skill-copy/scripts/init.sh` in an empty `/tmp/test-project/` (`cd /tmp/test-project && bash /tmp/test-skill-copy/scripts/init.sh`). Component: D-2 path resolution contract. Trigger: invocation from a non-canonical install path with `pwd != skill dir`. Expected signal: templates are copied into `/tmp/test-project/evals/` (NOT into `/tmp/test-skill-copy/`), and the script exits 0 with a `CREATED`/`PRESERVED` log. If templates land in the skill dir or the script errors with "no such file: $TPL_DIR/HYPOTHESES.md.tmpl", D-2's `$(dirname "$0")/../templates/` derivation is broken and scripts must fall back to an explicit `--templates-dir` arg.

- **T5 — SKILL.md size budget**: after the split commit lands, `wc -l ~/.claude/skills/evals/SKILL.md` is ≤300. Component: D-1 size budget. Trigger: post-split commit. Expected signal: line count ≤300. If the count is 301-600 the split was less aggressive than designed (reviewer flags HIGH); if >600 the split failed entirely (reviewer flags CRITICAL — the *Refutable by:* clause of THIS ADR fires and a new ADR is needed). Concrete check: the developer runs `wc -l SKILL.md` as the last step of their commit and includes the count in the commit message body.

- **T6 — Justifiability scan finds zero orphans**: `for f in $(git diff --name-only --diff-filter=A | grep '^\.claude/skills/evals/'); do grep -r "$(basename $f)" ~/.claude/skills/evals/ | grep -v "^${f}:" || echo "ORPHAN: $f"; done` produces zero ORPHAN lines. Component: D-4 justifiability discipline. Trigger: ultra-review scan of the split commit. Expected signal: every new file has at least one referencing line elsewhere in the skill. If any file appears as ORPHAN, that file is dead code and must be removed before merge — CLAUDE.md Justifiability rule (CRITICAL block per the rule's text).

## Pre-mortem (CC-2 self-application)

Three disaster scenarios, each (component, trigger, signal):

### Scenario A — Heredoc-to-file extraction silently corrupts a stub

- **Component**: `templates/corpus/sycophancy-bait/code/auth.js` (the developer copies content out of the bash heredoc and saves as a file).
- **Trigger**: bash heredoc rules (e.g. unquoted EOF allows `$VAR` interpolation; quoted EOF doesn't) interact badly with the developer's editor adding a trailing newline. The current heredoc uses `<<'CODE_EOF'` (quoted) so no interpolation, but the trailing-newline behaviour differs between heredoc termination and a regular file's trailing `\n`.
- **Signal**: T1 fails — sha256 of `evals/corpus/sycophancy-bait/code/auth.js` post-split differs from pre-split by 1 byte (the trailing newline). Pilot re-runs see a different `prompt_sha256` (since the file is read into the prompt) → noise floor measurement diverges from step 7's baseline → ADR 0005 D-2's "test-retest baseline" is invalidated retroactively.
- **Mitigation in design (D-1)**: T1 is the falsification gate. The developer runs T1 BEFORE committing; if sha256 differs they normalize trailing whitespace until parity holds. Tester runs T1 again on smoke-test for belt-and-suspenders.
- **Residual risk**: developer skips T1 and merges. Mitigated by ultra-review compliance scanner (CRITICAL block on missing T1 evidence in the commit body).

### Scenario B — Future contributor re-inlines the split silently, citing "convention"

- **Component**: human discipline (this is a meta-component — the structural convention itself).
- **Trigger**: 6 months from now, a contributor (or future-me) opens `~/.claude/skills/evals/`, sees the multi-file structure, notices all other plugin skills are single-file, and "fixes" the inconsistency with a re-inlining PR — without reading this ADR or ADR 0005.
- **Signal**: PR diff shows `scripts/`, `references/`, `templates/` deleted and SKILL.md re-grown to >600 lines.
- **Mitigation in design (D-1 + Generalizable convention section below)**: SKILL.md frontmatter (or a top comment) MUST point to this ADR by number ("structural rationale: see `~/.claude/decisions/0006-evals-skill-multifile.md` — re-inlining requires a superseding ADR per CLAUDE.md append-only rule"). Code-reviewer agent's standing instruction to read `.claude/decisions/*.md` before approving structural changes catches it.
- **Residual risk**: reviewer skips reading ADRs. Mitigated by: append-only rule is itself in CLAUDE.md (always loaded), and the ADR pointer in SKILL.md is loaded into context whenever the skill runs.

### Scenario C — Step 8 forces premature abstraction of pre-flight gates

- **Component**: D-1 split structure (the boundary between `scripts/run-pre-pilot.sh` and a future `scripts/run-cc-5.sh`).
- **Trigger**: step 8 adds `run --cc-5` (A/B toggle mode) which needs the same pre-flight gates as `run --pre-pilot` (committed HYPOTHESES.md, RESOLVED Q1/Q3/Q4/Q6). Developer either (a) duplicates Gates A+B in the new script (CLAUDE.md "no premature abstraction" was followed — but now there ARE 2 callers, so duplication is no longer premature; the rule of three is on the verge of triggering), or (b) extracts to `scripts/lib/pre-flight.sh` and accidentally diverges the two scripts' contracts.
- **Signal**: post step 8, `diff scripts/run-pre-pilot.sh scripts/run-cc-5.sh | grep -A 20 "Gate A"` shows substantial overlap (>30 duplicated lines) AND a future bug-fix to one gate is not propagated to the other.
- **Mitigation in design (D-1 Negative consequences section)**: this ADR explicitly notes the future duplication risk and prescribes the fix (`scripts/lib/pre-flight.sh` extraction at the rule-of-three trigger — i.e. when a third caller appears, OR when the duplicated logic exceeds 50 lines). Step 8's ADR (the next one in line) MUST address this; this ADR pre-warns.
- **Residual risk**: step 8 ships with copy-pasted gates and a divergence bug appears. Mitigated by: this ADR's pre-warning + step 8's ADR will inherit the obligation + tester (smoke-test) compares both scripts' gate behaviour with the same fixture.

## Generalizable convention (when to split a skill)

This ADR establishes the criterion for future skill-split decisions in this plugin (so we don't re-litigate this every time another skill grows):

**Default**: single-file `SKILL.md`, like `/team`, `/commit`, `/spec`, `/challenge`, etc. Single-file is preferred until *one of* the following triggers fires:

1. **Hard ceiling — line breach**: `wc -l SKILL.md` exceeds **600 lines** of prose (the empirical threshold ADR 0005 D-1 set, and which this ADR validates by enforcing).
2. **Soft ceiling — code-as-data ratio**: more than **40%** of SKILL.md lines are heredocs, fixtures, JSON schemas, or code stubs (i.e. data that would benefit from being independently editable files in their native syntax). Even if total lines are <600, this ratio signals that the file is mixing dispatch prose with bundled artifacts and the artifacts deserve `templates/` or `assets/` treatment.
3. **Reusability ceiling**: a bash function or template is invoked by ≥2 subcommands within the same skill AND would benefit from independent unit-testing — extract to `scripts/lib/<helper>.sh` (rule-of-three timing).

**Trigger threshold**: any *one* of the above is sufficient. Multiple triggers compound urgency.

**Mandatory procedure when a trigger fires**:
1. Write a NEW ADR superseding the relevant decision in the original skill ADR (partial supersession is fine — `Supersedes NNNN D-X` per CLAUDE.md append-only rule).
2. Document the file mapping (current → new) in a table, like D-1 above.
3. Provide ≥3 falsification tests in `## Tests that would invalidate this design` (CC-4 + validate-arch.sh contract).
4. The developer reorganizes per the new ADR's mapping; reviewer enforces D-4 justifiability scan.

**Current state of other plugin skills** (informational, no action mandated):

| Skill | Lines | Code-as-data ratio | Trigger fired? |
|---|---|---|---|
| `/team` | 455 | low (mostly dispatch prose) | NO — within budget |
| `/commit` | not measured here | likely low | NO |
| `/spec` | not measured here | likely low | NO |
| `/challenge` | not measured here | likely low | NO |

The convention does NOT mandate eager-splitting other skills; it mandates *checking the criterion when a skill grows*, and acting only when a trigger fires. This avoids the failure mode "we now have a multi-file convention, let's apply it everywhere" — premature uniformity is itself a folder-cleanliness violation.

`[OBSERVED: ~/.claude/CLAUDE.md "no premature abstraction" + "Surgical changes"]`

STATUS: DONE — design proposal complete, falsification gates and justifiability discipline embedded.

