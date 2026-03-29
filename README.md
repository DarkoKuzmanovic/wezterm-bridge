# wezterm-bridge

A CLI bridge for AI agent communication through WezTerm panes. Run Claude Code and Codex side by side and let them talk to each other.

Inspired by [smux](https://github.com/ShawnPana/smux/) — rebuilt from scratch for WezTerm.

## Requirements

- [WezTerm](https://wezfurlong.org/wezterm/) (recent version with `wezterm cli` support)
- [jq](https://jqlang.github.io/jq/) for JSON parsing
- Bash 4+

## Install

```bash
git clone https://github.com/quzma/wezterm-bridge.git
cd wezterm-bridge
bash install.sh install
```

Then restart your shell or run `source ~/.zshrc`.

Verify: `wezterm-bridge doctor`

## Quick Start

Open WezTerm and split into two panes. Start Claude Code in one, Codex in the other.

```bash
# In Claude Code's pane:
wezterm-bridge name "$(wezterm-bridge id)" claude

# In Codex's pane:
wezterm-bridge name "$(wezterm-bridge id)" codex
```

Now either agent can communicate:

```bash
wezterm-bridge list                                      # see all panes
wezterm-bridge read codex 20                             # read pane (required before write)
wezterm-bridge message codex --enter 'Review auth.ts'    # send and submit
```

## Agent Integration

Add the skill to your agent's context:

- **Claude Code**: Reference `skills/wezterm-bridge/SKILL.md` in your CLAUDE.md
- **Codex**: Include the skill content in your agent instructions

The SKILL.md teaches agents the full protocol: pane discovery, read-guard discipline, messaging conventions, and the read-act-read cycle.

## Commands

| Command | Description |
|---------|-------------|
| `list` | Show all panes with IDs, titles, labels |
| `read <target> [lines]` | Read pane content (default 50). Sets read guard. |
| `type <target> [--enter] <text>` | Send text. `--enter` submits it. Requires read guard. |
| `keys <target> <key>...` | Send special keys (Enter, Escape, C-c, etc). |
| `message <target> [--enter] <text>` | Send prefixed agent-to-agent message. `--enter` submits it. |
| `name <target> <label>` | Label a pane for easy reference. |
| `resolve <label>` | Get pane ID for a label. |
| `id` | Print current pane ID. |
| `wait <target> <condition>` | Block until pane content matches (--match, --quiet, --prompt) |
| `read <target> --new` | Only new output since last read |
| `spawn <label> [options]` | Split pane + start command + label |
| `log [--tail] [--clear]` | View/clear the audit log |
| `lock <target>` | Acquire pane lock (auto-expires) |
| `unlock <target>` | Release pane lock |
| `--json <command>` | JSON output for any command |
| `doctor` | Run diagnostics. |

## How It Works

The bridge wraps three WezTerm CLI primitives:
- `wezterm cli get-text` — read pane scrollback
- `wezterm cli send-text` — inject text into a pane
- `wezterm cli list` — discover panes

A **read-guard** system (temp files in `/tmp/`) enforces a read-before-write discipline, preventing agents from blindly firing commands.

Pane **labels** are stored in `/tmp/wezterm-bridge-$UID/labels/` so agents can refer to each other by name instead of numeric IDs.

## Uninstall

```bash
bash install.sh uninstall
```

## License

MIT
