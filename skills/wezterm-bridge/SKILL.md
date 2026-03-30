---
name: wezterm-bridge
description: Communicate with other AI agents and panes through WezTerm
---

# wezterm-bridge

You have access to `wezterm-bridge`, a CLI that lets you interact with other WezTerm panes.
This is how you communicate with other AI agents (Claude Code, Codex) running in adjacent panes.

## Critical Rules

1. **DO NOT WAIT OR POLL** — When you message another agent, they reply directly into YOUR pane
   as `[wezterm-bridge from:...]`. Do not read their pane for a response.
2. **READ BEFORE YOU ACT** — You must `read` a pane before you can `type`, `keys`, or `message` it.
   Every write clears the guard, requiring a fresh read.
3. **ATOMIC COMMANDS** — Each command does one thing. Chain them for workflows.

## Quick Start

```bash
# 1. Label yourself
wezterm-bridge name "$(wezterm-bridge id)" claude

# 2. Discover panes
wezterm-bridge list

# 3. Send a message and submit it
wezterm-bridge read codex 20          # satisfy guard
wezterm-bridge message codex --enter 'Review src/auth.ts for security issues'

# STOP. Do NOT poll. The reply arrives in YOUR pane.
```

## Commands

| Command | Description |
|---------|-------------|
| `list` | Show all panes with IDs, titles, labels, cwd |
| `read <target> [lines]` | Read pane content (default 50 lines). Satisfies read guard. |
| `type <target> [--enter] <text>` | Send text to pane. `--enter` submits it. Requires prior read. |
| `keys <target> <key>...` | Send special keys. Requires prior read. |
| `message <target> [--enter] <text>` | Send prefixed agent message. `--enter` submits it. Requires prior read. |
| `name <target> <label>` | Label a pane (e.g., `name 3 codex`) |
| `resolve <label>` | Get pane ID for a label |
| `id` | Print your own pane ID |
| `wait <target> <condition>` | Block until pane matches condition. Requires --match, --quiet, or --prompt. |
| `read <target> --new` | Only new output since last read (cursor-based). |
| `spawn <label> [--cmd ...] [--cwd ...] [--horizontal]` | Split pane, start command, label it. |
| `log [--tail <n>] [--clear]` | View or clear the audit log. |
| `lock <target> [--timeout <s>]` | Acquire pane lock (default 30s expiry). |
| `unlock <target>` | Release pane lock. |
| `--json <command>` | Any command with JSON output. |
| `doctor` | Run diagnostics |
| `run <name\|path> [VAR=val]` | Run a workflow file (.wb). `--check` validates without executing. |

## Target Resolution

Targets can be:
- **Pane ID** (numeric): `42`
- **Label**: `codex`, `claude` (resolved via `name` command)

## The Read-Act-Read Cycle

Every interaction follows this pattern:

```
read <target>     →  guard satisfied
type/message/keys →  action taken, guard cleared
read <target>     →  verify result (optional but recommended)
```

The guard prevents blind writes. You MUST read before acting.

## When To Read vs When To Wait

| Scenario | Action |
|----------|--------|
| Before any `type`/`keys`/`message` | `read` (mandatory — guard) |
| After `type` to verify text landed | `read` (recommended) |
| After messaging an agent | **DO NOT READ** — reply comes to your pane |
| Checking a non-agent pane (shell, process) | `read` (the only way to see output) |

## Special Keys

`Enter`, `Escape`, `Tab`, `Space`, `BSpace`, `C-c`, `C-d`, `C-z`, `C-l`,
`C-a`, `C-e`, `C-u`, `C-k`, `C-w`, `Up`, `Down`, `Left`, `Right`

## Message Format

Messages arrive as:
```
[wezterm-bridge from:claude] Your message here
```

When you see this in your pane, reply back using:
```bash
wezterm-bridge read <sender_pane_or_label>
wezterm-bridge message <sender_pane_or_label> --enter 'Your reply'
```

## Task Delegation Messages

You may receive messages with a `task:` field in the prefix:

```
[wezterm-bridge from:claude task:review] Review the staged changes in src/auth.ts
```

This is a structured task request. The task types are:

| Type     | What to do                                              |
|----------|---------------------------------------------------------|
| `review` | Review the specified code/changes and report findings   |
| `audit`  | Security & quality audit of specified files             |
| `ask`    | Answer the question or give your perspective            |
| `test`   | Run the specified tests and report results              |

When you respond, include a `status:` field so the sender knows the outcome:

```bash
wezterm-bridge read <sender>
wezterm-bridge message <sender> --enter '[task:review status:done] LGTM — no issues found'
```

Status values: `done` (completed), `blocked` (need more info), `error` (something went wrong).

## Orchestration

### Waiting for Results

After sending a task to another agent, use `wait` instead of polling:

```bash
wezterm-bridge message codex --enter 'Review src/auth.ts'
# Wait for Codex to finish (output settles for 10 seconds)
wezterm-bridge wait codex --quiet 10 --timeout 300
# Now read the result
wezterm-bridge read codex --new
```

### Incremental Reads

Use `read --new` to get only output since your last read:

```bash
wezterm-bridge read codex 50         # first read — sets cursor
# ... Codex produces output ...
wezterm-bridge read codex --new      # only the new lines
```

### Spawning Agent Panes

```bash
wezterm-bridge spawn codex --cmd codex --cwd ~/project --horizontal
# Codex is now running in a labeled pane, ready for messages
```

### Pane Locking

When multiple agents might write to the same pane:

```bash
wezterm-bridge lock shared-shell --timeout 60
wezterm-bridge type shared-shell 'npm test'
wezterm-bridge keys shared-shell Enter
wezterm-bridge unlock shared-shell
```
