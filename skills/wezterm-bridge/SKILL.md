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

# 3. Send a message (read-act-read cycle)
wezterm-bridge read codex 20          # satisfy guard
wezterm-bridge message codex 'Review src/auth.ts for security issues'
wezterm-bridge read codex 20          # verify text landed
wezterm-bridge keys codex Enter       # submit

# STOP. Do NOT poll. The reply arrives in YOUR pane.
```

## Commands

| Command | Description |
|---------|-------------|
| `list` | Show all panes with IDs, titles, labels, cwd |
| `read <target> [lines]` | Read pane content (default 50 lines). Satisfies read guard. |
| `type <target> <text>` | Send text without Enter. Requires prior read. |
| `keys <target> <key>...` | Send special keys. Requires prior read. |
| `message <target> <text>` | Send prefixed agent message. Requires prior read. |
| `name <target> <label>` | Label a pane (e.g., `name 3 codex`) |
| `resolve <label>` | Get pane ID for a label |
| `id` | Print your own pane ID |
| `doctor` | Run diagnostics |

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
wezterm-bridge message <sender_pane_or_label> 'Your reply'
wezterm-bridge read <sender_pane_or_label>
wezterm-bridge keys <sender_pane_or_label> Enter
```
