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

Labels a pane for easy reference. Labels are stored in `/tmp/wezterm-bridge-labels/`.

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

## doctor

Runs diagnostics: checks wezterm, jq, environment, connectivity, labels, guards.

```
wezterm-bridge doctor
```
