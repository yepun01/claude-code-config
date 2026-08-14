---
description: Create a structured git commit
allowed-tools: ["Bash(git *)"]
---

## Current state
- Status: !`git status --short`
- Modified files: !`git diff --stat`
- Staged: !`git diff --staged --stat`

## Instructions

Analyze these changes and create a commit with a clear message.

1. Propose a concise commit message (in English, conventional: feat/fix/docs/refactor/test)
2. Add **trailers** after a blank line at the end of the message:
   - `Scope-risk: LOW | MEDIUM | HIGH` — assess the risk of the change (HIGH = touches auth, data, critical infra)
   - `Not-tested: [description]` — what was NOT tested (edge cases, specific env, etc.). If everything is tested, omit this trailer.
   - `Confidence: LOW | MEDIUM | HIGH` — confidence level that the change is correct and complete

Full message example:
```
feat(api): add rate limiting to auth endpoints

Scope-risk: HIGH
Not-tested: rate limit reset after server restart
Confidence: HIGH
```

3. Commit directly — invoking `/commit` counts as consent.

IMPORTANT: NEVER add a signature or attribution like "Generated with Claude Code", "Co-Authored-By: Claude", or similar. The commit must be clean, without any mention of AI.
