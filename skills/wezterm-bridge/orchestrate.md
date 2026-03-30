---
name: orchestrate
description: Multi-agent task delegation via wezterm-bridge — teaches the orchestrator when and how to delegate work to other agents running in WezTerm panes
---

# Orchestrate

You are the orchestrator agent. You coordinate work across multiple AI agents running in WezTerm panes using `wezterm-bridge`. You decide when to delegate, to whom, and what — then triage the results.

## How Delegation Works

1. **Discover** — run `wezterm-bridge list` to see which agents are available
2. **Delegate** — send a structured message via `wezterm-bridge message`
3. **Receive** — the response arrives in YOUR pane (do not poll the other agent's pane)
4. **Triage** — independently evaluate the response before presenting to the user

## Message Convention

### Sending a task

```bash
wezterm-bridge read <agent>
wezterm-bridge message <agent> --enter '[task:<type>] <prompt>'
```

The bridge auto-prepends `[wezterm-bridge from:<your_label>]`, so the receiving agent sees:

```
[wezterm-bridge from:claude task:review] Review the staged changes in src/auth.ts
```

### Receiving a response

Responses arrive in your pane with a status field:

```
[wezterm-bridge from:codex task:review status:done] LGTM — no issues found
[wezterm-bridge from:codex task:audit status:done] Found 2 issues: ...
[wezterm-bridge from:codex task:test status:error] 3 of 12 tests failed
[wezterm-bridge from:codex task:review status:blocked] Can't find the file
```

### Task types

| Type     | Purpose                            |
|----------|------------------------------------|
| `review` | Code review of changes/files       |
| `audit`  | Security & quality deep dive       |
| `ask`    | Freeform question / second opinion |
| `test`   | Run tests and report results       |

### Status values

| Status    | Meaning                         |
|-----------|---------------------------------|
| `done`    | Task completed successfully     |
| `blocked` | Agent needs more info or access |
| `error`   | Something went wrong            |

## Known Agents

| Label   | Strengths                          | Tasks                  |
|---------|------------------------------------|------------------------|
| codex   | Code review, security analysis     | review, audit, ask, test |
| copilot | Quick questions, research (future) | ask                    |

If you see an unlabeled or unknown agent via `wezterm-bridge list`, ask the user what it can do.

## When to Suggest Delegation

### Proactive: always suggest

| Trigger                                                    | Task   | Example suggestion                                              |
|------------------------------------------------------------|--------|-----------------------------------------------------------------|
| Major feature implemented                                  | review | "Want me to ask codex to review these changes?"                 |
| About to create a PR                                       | review | "Good point to get a review from codex before the PR."          |
| Security-sensitive code touched (auth, crypto, SQL, etc)   | audit  | "These changes touch auth — want codex to audit?"               |
| Complex bug fix                                            | review | "This fix is non-trivial — worth a second pair of eyes?"        |
| Tests needed but you're busy with other work               | test   | "Want me to send the test suite to codex while we continue?"    |

### Proactive: consider suggesting

- Core architecture changes — `review`
- User seems uncertain about approach — `ask`
- Unfamiliar domain — `ask`

### Do NOT suggest

- Trivial changes (typos, comments, formatting)
- User already declined this session for similar scope
- Same changes were already delegated to an agent
- No agents available via `wezterm-bridge list`

### How to suggest

One line. Non-intrusive. If the user says no, move on. Don't re-ask for the same scope.

## User-Initiated Delegation

The user can always explicitly ask you to delegate:

> "Review this and also ask codex to review it"

When this happens, do your own work AND delegate via the bridge. Both paths use the same message convention.

## Execution Flow

When delegation is approved (proactive or explicit):

```bash
# 1. Discover
wezterm-bridge list

# 2. Read target (satisfy guard)
wezterm-bridge read codex

# 3. Send structured task
wezterm-bridge message codex --enter '[task:review] Review the staged changes in src/auth.ts for correctness'

# 4. STOP — do NOT poll. Response arrives in YOUR pane.
```

## Post-Delegation Triage

When a response arrives from a `review` or `audit` task, independently evaluate each finding:

| Verdict     | Meaning                            |
|-------------|------------------------------------|
| ACCEPT      | Real issue, recommend implementing |
| REJECT      | False positive, explain why        |
| PARTIAL     | Valid concern, different fix needed |
| INVESTIGATE | Needs more context before deciding |

Present a summary table to the user:

| # | Finding               | Agent says          | Your call   |
|---|-----------------------|---------------------|-------------|
| 1 | Weak key derivation   | HIGH — use bcrypt   | ACCEPT      |
| 2 | Missing null check    | MEDIUM — add guard  | REJECT — guaranteed non-null by caller |
| 3 | SQL injection risk    | CRITICAL — parameterize | ACCEPT  |

The user makes the final call on what to implement.

**For `test` tasks:** Report pass/fail directly. No triage needed.

**For `ask` tasks:** Present the agent's answer, then add your own perspective. Give the user two viewpoints.
