# wezterm-bridge API Reference

## list

Enumerates all panes in the current WezTerm instance.

```
wezterm-bridge list
```

Output columns: PANE_ID, TAB, TITLE, LABEL, CWD

---

## read <target> [lines]

Captures the last N lines (default 50) from the target pane's terminal output.
Sets the read guard for the target, allowing subsequent write operations.

```
wezterm-bridge read 3 30       # last 30 lines from pane 3
wezterm-bridge read codex      # last 50 lines from pane labeled "codex"
```

---

## type <target> <text>

Sends literal text to the target pane. Does NOT send Enter — use `keys` for that.
Requires a prior `read` of the target (read guard). Clears the guard after execution.

```
wezterm-bridge type codex 'ls -la'
```

---

## keys <target> <key>...

Sends one or more special keys to the target pane. Requires prior `read`. Clears guard.

```
wezterm-bridge keys codex Enter
wezterm-bridge keys codex C-c
wezterm-bridge keys codex Escape
```

Supported keys: Enter, Escape, Tab, Space, BSpace, C-c, C-d, C-z, C-l,
C-a, C-e, C-u, C-k, C-w, Up, Down, Left, Right

---

## message <target> <text>

Sends a prefixed message for agent-to-agent communication. The message is
automatically prefixed with `[wezterm-bridge from:<your_label>]`.

Requires prior `read`. Clears guard.

```
wezterm-bridge message codex 'Please review src/auth.ts'
```

The target sees:
```
[wezterm-bridge from:claude] Please review src/auth.ts
```

---

## name <target> <label>

Labels a pane for easy reference. Labels are stored in `/tmp/wezterm-bridge-$UID/labels/`.

```
wezterm-bridge name 3 codex
```

---

## resolve <label>

Returns the pane ID associated with a label.

```
wezterm-bridge resolve codex    # prints: 3
```

---

## id

Prints the current pane's ID from `$WEZTERM_PANE`.

```
wezterm-bridge id    # prints: 5
```

---

## wait <target> <condition>

Blocks until the target pane's content matches a condition. Polls every `--interval` seconds.

Conditions (exactly one required):
- `--match <regex>` — wait for a line matching the extended regex
- `--quiet <secs>` — wait for output to stop changing for N seconds
- `--prompt` — shortcut for `--match '^[›$%#>] ?$'`

Options:
- `--timeout <secs>` — max wait time (default: 120)
- `--interval <secs>` — poll interval (default: 2)

On success: prints the matched line (for --match/--prompt) or a status message, sets read guard, exits 0.
On timeout: exits 1.

```
wezterm-bridge wait codex --match "PASS" --timeout 60
wezterm-bridge wait codex --quiet 10
wezterm-bridge wait codex --prompt
```

---

## read <target> --new

Returns only output that appeared since the last `read` of this target.

Uses a cursor system: after each read, a cursor (line count + hash) is saved. On `--new`, only lines after the cursor are returned. If the cursor can't be matched (scrollback wrapped), all content is returned with a warning.

```
wezterm-bridge read codex --new
```

---

## spawn <label> [options]

Splits the current pane, starts a command, and labels the new pane.

Options:
- `--cmd <command>` — command to run (default: `$SHELL`)
- `--cwd <dir>` — working directory
- `--horizontal` — side-by-side split (default: top/bottom)

```
wezterm-bridge spawn codex --cmd codex --cwd ~/project --horizontal
wezterm-bridge spawn worker --cmd 'npm run dev'
```

---

## log [--tail <n>] [--clear]

View or clear the audit log. All bridge operations are logged automatically.

```
wezterm-bridge log                   # last 20 entries
wezterm-bridge log --tail 50         # last 50 entries
wezterm-bridge log --clear           # clear log
```

---

## lock <target> [--timeout <secs>]

Acquires an advisory lock on a pane. Write commands (`type`, `keys`, `message`) check locks before executing. Locks auto-expire after the timeout.

Default timeout: 30 seconds.

```
wezterm-bridge lock codex --timeout 60
```

---

## unlock <target>

Releases a lock you own on a pane. Idempotent if pane is not locked.

```
wezterm-bridge unlock codex
```

---

## --json (global flag)

Prefix any command with `--json` to get machine-readable JSON output.

```
wezterm-bridge --json list
wezterm-bridge --json read codex 10
wezterm-bridge --json wait codex --match "done"
```

Output format:
```json
{"status":"ok","command":"...","key":"value"}
{"status":"error","message":"..."}
```

---

## doctor

Runs diagnostics: checks wezterm, jq, environment, connectivity, labels, guards.

```
wezterm-bridge doctor
```
