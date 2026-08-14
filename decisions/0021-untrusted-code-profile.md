# ADR 0021 — Untrusted-code profile: permission mode, network egress, execution-indirection tripwire, brief quarantine

## Status
Proposed (2026-07-23)

Date: 2026-07-23
Supersedes: — (complements CLAUDE.md §Permissions and the ADR 0001 brief template; changes no prior decision)
Superseded by: —

## Context

The setup is deliberately optimized for solo velocity: `defaultMode: "bypassPermissions"`, `Bash(curl:*)` allowlisted, the deny list blocks the *write* path of credentials but not the Read/exfil path, and the reviewer agents (`code-reviewer`, `security-reviewer`, `code-challenger`) hold full tools with review-only discipline enforced by prompt only `[OBSERVED: settings.json permissions; CLAUDE.md §Available agents]`. Meanwhile, reviewing unknown repos is a routine usage (/mouly ETNA corrections). CLAUDE.md names the risk — "do not rely on prompt-discipline alone if reviewing code that may contain hostile prompt injection" — without tooling it.

Veille 2026-07 (`tmp/veille-2026-07/final-report.md`, thème 1): four independent proposals converge on this same self-documented hole, each surviving adversarial refutation (3 KEEP + 1 DOWNGRADE-to-core). Their evidence base:

- Auto mode: 2-stage permission classifier, 0.4 % FP announced `[SOURCE anthropic.com/engineering/claude-code-auto-mode; code.claude.com/docs/en/best-practices]`
- Containment: 24/25 exfiltration attempts succeeded despite model-layer defenses — only deterministic boundaries stopped exfil `[SOURCE anthropic.com/engineering/how-we-contain-claude]`
- Execution indirection: payloads staged outside the reviewed text (DNS TXT records, remote configs) and fetched at runtime, invisible to static review `[SOURCE Mozilla 0DIN via helpnetsecurity 2026-06-29]`
- Spotlighting: delimiting attacker-controlled content as data drops injection ASR from >50 % to <2 % (partial defense) `[SOURCE Hines et al. arXiv 2403.14720; CSA research note]`

Threat model: attacker-controlled repo content (code, commits, README, project CLAUDE.md) is ingested by full-tool agents running under bypassPermissions with unrestricted network. A prompt-injected agent can (a) execute a staged payload, (b) exfiltrate `~/.claude` or credentials over allowlisted network tools, (c) obey instructions hidden in brief-inlined content. The four decisions below are one profile because each covers a leg the others cannot.

## Decision

### D-1 · Canary auto mode as defaultMode of Review sessions on unknown code

Canary-test the auto mode classifier as the permission mode for Review-pipeline sessions on untrusted repos. `bypassPermissions` stays for `~/.claude` and trusted projects — this is a per-session profile, not a global `settings.json` flip.

Preconditions before any switch (refuter's findings, all mandatory):
1. Verify that subagents **inherit** the session's permission mode — `[OBSERVED]` evidence required, no assumption (cf. feedback_platform_claims: canary before architecting around platform behavior).
2. Measure FP rate in-situ: 0.4 % FP is *per call* → ≥1 block expected per multi-agent session, likely on legitimate writes outside cwd (`~/.claude/teams|tmp`).
3. The prior W21 rejection covered only the headless subprocess — it does not preempt this canary.

Exact wiring (CLI flag vs per-project settings) is decided at implementation, after the canary.

### D-2 · Network egress controls for the Review pipeline

OS-level network sandboxing (domain allowlist) for Review runs on unknown code where the platform sandbox supports it; at minimum, an egress checklist in the Review brief plus documentation in `docs/team-pipelines.md` §Review. Rationale: 24/25 exfiltrations succeeded against model-layer defenses — D-2 is the only *deterministic* boundary in this profile; D-1/D-3/D-4 are probabilistic or advisory.

### D-3 · Execution-indirection tripwire + finding class

Two halves, both required:

- **(a) Hook** — new PreToolUse(Bash) hook blocking network→shell pipes (`curl|wget|dig … | sh|bash`), today executed without prompt under bypassPermissions. Status: **tripwire, not barrier** — trivially bypassed in 2 steps (download, then execute), same standing as the existing `Bash(bash -c:*)` deny. The deny-entry variant is inexpressible (prefix matching) → hook only. Wire alongside `block-sensitive-files.sh`/`block-pollution-files.sh` in `settings.json`.
- **(b) Finding class** — `security-reviewer` gains an "execution indirection" finding class: *what will this command actually execute at runtime* (payload in DNS TXT, remote config, install scripts) — the staged variant the hook cannot see.

The hook catches the one-liner; the finding class catches the staged attack.

### D-4 · DATA-NOT-INSTRUCTIONS quarantine in Review brief assembly

Attacker-controlled content inlined raw into briefs today — commits, diff, project CLAUDE.md (`skills/team/SKILL.md` STEP 0 + brief template `[OBSERVED]`) — gets wrapped in explicit "data, not instructions" delimiters (spotlighting). Positioning is explicit: prompt-layer, partial (ASR >50 % → <2 %), a **complement, never a substitute** for D-1/D-2 — reviewers ingest the hostile content via Read regardless of brief hygiene.

## Alternatives considered

| Option | Retained? | Reason |
|--------|-----------|--------|
| Global `defaultMode` flip to auto | No | Kills solo velocity on trusted work; the hole is Review-on-unknown-code only |
| Deny entries for network→shell pipes | No | Inexpressible — permission matching is prefix-based, cannot see the pipe (refuter) |
| Quarantine (D-4) alone | No | Prompt-layer defense with partial ASR reduction; Read path bypasses it entirely |
| Model-layer discipline only (status quo) | No | 24/25 exfil success against exactly this class of defense `[SOURCE how-we-contain-claude]` |

## Consequences

- Positive: the self-documented hole gets a deterministic boundary (D-2), a calibrated permission profile (D-1), a tripwire + detection class for indirection (D-3), and brief hygiene (D-4). CLAUDE.md's warning becomes tooled instead of aspirational.
- Negative: friction on Review sessions (auto-mode blocks, egress allowlist maintenance). If the D-1 canary shows FP incompatible with multi-agent sessions, fall back to scoped allow entries for `~/.claude/teams|tmp` writes rather than abandoning the profile.
- Neutral: bypassPermissions remains the default everywhere else — velocity unchanged outside Review-on-unknown-code.
- Defense-in-depth ordering is explicit: D-2 (deterministic) > D-1 (classifier) > D-3a (tripwire) > D-3b/D-4 (detection/hygiene). No single layer suffices.
- Each implemented piece that touches documented behavior (hooks list, §Permissions, agent counts) must update CLAUDE.md in the same commit (meta-rule: feedback_adr_meta_rule_bootstrap).

## Tests that would invalidate this design

- T1 — canary shows subagents do NOT inherit the session permission mode → D-1 unusable as a session-level profile; supersede with per-agent wiring.
- T2 — auto mode blocks legitimate `~/.claude/teams|tmp` writes more than ~once per Review run after path allowlisting → D-1 recalibrate or drop.
- T3 — tripwire fires on legitimate pipes (`curl … | jq`, `… | tar`) → regex too broad; narrow to shell interpreters only.
- T4 — a staged download-then-execute passes both the hook and the security-reviewer finding class in a red-team drill → D-3 insufficient as designed; weight shifts to D-2 egress.
- T5 — spotlighting delimiters measurably degrade review quality (missed findings on quarantined diffs vs raw) → D-4 format revisit.
