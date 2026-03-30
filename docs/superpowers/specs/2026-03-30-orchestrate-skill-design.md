# Orchestrate Skill Design

**Date:** 2026-03-30
**Status:** Approved

## Overview

A new `orchestrate.md` skill for wezterm-bridge that teaches the orchestrator agent (Claude) when and how to delegate work to other agents running in WezTerm panes. Replaces the standalone `/codex-*` skills with a unified, agent-agnostic delegation model built entirely on wezterm-bridge.

## Motivation

The existing `codex-integration`, `codex-review`, `codex-audit`, and `codex-ask` skills are one-sided (Claude-to-Codex only) and use a subprocess model. The user's workflow is moving entirely to wezterm-bridge as the coordination layer. This design:

- Makes delegation agent-agnostic (Codex today, Copilot tomorrow)
- Uses wezterm-bridge as the sole transport
- Keeps the orchestrator role with the primary agent (Claude)
- Retires the `/codex-*` skills

## Skill Structure

```
skills/wezterm-bridge/
├── SKILL.md                        # how to communicate (all agents load)
├── orchestrate.md                  # when/why to delegate (orchestrator only)
└── references/
    └── wezterm-bridge.md           # API reference
```

- **Orchestrator (Claude):** loads both `SKILL.md` and `orchestrate.md`
- **Other agents (Codex, Copilot):** load only `SKILL.md`

## Message Convention

Extends the existing `[wezterm-bridge from:<label>]` prefix with structured fields for delegation.

### Request format

```
[wezterm-bridge from:<label> task:<type>] <free-text prompt>
```

### Response format

```
[wezterm-bridge from:<label> task:<type> status:<status>] <free-text response>
```

### Task types (day one)

| Type     | Purpose                            |
|----------|------------------------------------|
| `review` | Code review of changes/files       |
| `audit`  | Security & quality deep dive       |
| `ask`    | Freeform question / second opinion |
| `test`   | Run tests and report results       |

### Designed for later

| Type        | Purpose                          |
|-------------|----------------------------------|
| `implement` | Build a function/feature         |
| `research`  | Investigate a library/API/topic  |

### Status values

| Status    | Meaning                        |
|-----------|--------------------------------|
| `done`    | Task completed successfully    |
| `blocked` | Agent needs more info or access |
| `error`   | Something went wrong           |

### Examples

```
[wezterm-bridge from:claude task:review] Review the staged changes in src/auth.ts for correctness
[wezterm-bridge from:codex task:review status:done] LGTM — no issues found

[wezterm-bridge from:claude task:audit] Audit src/crypto.ts for OWASP top 10
[wezterm-bridge from:codex task:audit status:done] Found 2 issues: 1) weak key derivation at line 42...

[wezterm-bridge from:claude task:test] Run bash tests/test_guard.sh and report results
[wezterm-bridge from:codex task:test status:error] 3 of 12 tests failed — see output above

[wezterm-bridge from:codex task:review status:blocked] Can't find the file — is it staged or committed?
```

### Design decisions

- Format extends existing `[wezterm-bridge from:<label>]` prefix — not a new format
- Free-text body after the bracket — agents aren't constrained to rigid schemas
- No `files:` or `cmd:` fields in the bracket — those go in the free-text body
- Receiving agents don't have to use the response format — orchestrator handles unstructured replies gracefully

## Proactive Suggestion Logic

### Step 1: Discovery

Run `wezterm-bridge list` to see which agents are available. No agents = no suggestions.

### Step 2: Match trigger to task type

**Always suggest:**

| Trigger                                          | Task type | Example                                                    |
|--------------------------------------------------|-----------|------------------------------------------------------------|
| Major feature implemented                        | `review`  | "Want me to ask codex to review these changes?"            |
| About to create a PR                             | `review`  | "Good point to get a review from codex before the PR."     |
| Security-sensitive code (auth, crypto, SQL, etc) | `audit`   | "These changes touch auth — want codex to audit?"          |
| Complex bug fix                                  | `review`  | "This fix is non-trivial — worth a second pair of eyes?"   |
| Tests needed but current agent is busy           | `test`    | "Want me to send the test suite to codex while we continue?" |

**Consider suggesting:**

- Core architecture changes — `review`
- User seems uncertain about approach — `ask`
- Unfamiliar domain — `ask`

**Don't suggest:**

- Trivial changes (typos, comments, formatting)
- User already declined this session for similar scope
- Same changes were already delegated
- No agents available via `wezterm-bridge list`

### Step 3: Suggest in one line

Non-intrusive. Example:

> "These changes touch auth middleware — want me to ask codex to audit the affected files?"

If the user says no, move on. Don't re-ask for the same scope.

### Step 4: On approval, execute

The orchestrator runs the bridge commands: `read` target, then `message` with the structured format.

## User-Initiated Delegation

The user can always explicitly ask for delegation:

> "Review this and also ask codex to review it"

The orchestrator does its own work AND delegates via the bridge. Both proactive and explicit paths use the same message convention and execution flow.

## Known Agents Table

The skill contains a reference table of known agents and their strengths:

| Label   | Strengths                          | Day-one tasks            |
|---------|------------------------------------|--------------------------|
| codex   | Code review, security analysis     | review, audit, ask, test |
| copilot | Quick questions, research (future) | ask                      |

Unknown labels — the orchestrator asks the user what the agent can do.

## Post-Delegation Triage

When a response comes back from `review` or `audit` tasks, the orchestrator independently evaluates each finding:

| Verdict       | Meaning                              |
|---------------|--------------------------------------|
| ACCEPT        | Real issue, recommend implementing   |
| REJECT        | False positive, explain why          |
| PARTIAL       | Valid concern, different fix needed   |
| INVESTIGATE   | Needs more context before deciding   |

The orchestrator presents a summary table. The user makes the final call.

For `test` tasks, the orchestrator reports pass/fail. For `ask` tasks, it synthesizes the answer with its own perspective.

## Changes to Existing Files

### Update: `SKILL.md`

Add a section on the structured message convention — just the receiving side. Teaches non-orchestrator agents to recognize `task:` fields and respond with `status:`.

### Update: `todo.md`

- Remove "Codex-integration bridge mode" (being built)
- Update "Task handoff primitives" to reference the new conventions as foundation

## Files to Retire

| Item               | Type    | Location                                          | Action |
|--------------------|---------|---------------------------------------------------|--------|
| codex-integration  | skill   | `~/.agents/skills/codex-integration/` (symlinked from `~/.claude/skills/`) | Delete dir + symlink |
| codex-review       | command | `~/.claude/commands/codex-review.md`              | Delete |
| codex-audit        | command | `~/.claude/commands/codex-audit.md`               | Delete |
| codex-ask          | command | `~/.claude/commands/codex-ask.md`                 | Delete |

Also update any references to `/codex-*` in other skill or command files.

## What Does NOT Change

- `bin/wezterm-bridge` — no CLI code changes
- `references/wezterm-bridge.md` — no new commands
- Tests — no new behavior to test (skill docs only)

## Future Path: Approach 3

The message conventions defined here are the spec for a future `delegate` CLI command:

```bash
# Future — not built now
wezterm-bridge delegate codex review --files src/auth.ts
# Generates: [wezterm-bridge from:claude task:review] Review src/auth.ts...
```

This is a natural promotion from convention to code once the protocol is battle-tested.
