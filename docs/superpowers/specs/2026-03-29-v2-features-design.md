# wezterm-bridge v2 Features Design Spec

**Goal:** Add 6 features to wezterm-bridge that transform it from a simple text relay into a proper multi-agent orchestration tool.

**Features (build order):**
1. `wait` — block until pane content matches a condition
2. `read --new` — incremental reads via cursor tracking
3. `spawn` — split pane + start command + label in one step
4. `log` — append-only audit log of all bridge operations
5. `--json` — global flag for machine-readable output
6. `lock`/`unlock` — pane mutex to prevent concurrent writes

**Constraints:**
- All features add to the existing single bash script (`bin/wezterm-bridge`)
- No new dependencies beyond wezterm, jq, and standard coreutils
- State files stay in the existing `/tmp/wezterm-bridge-$UID/` directory
- Backward compatible — all existing commands work unchanged

---

## 1. `wait` Command

**Purpose:** Block until a pane's content matches a condition. This is the key missing piece for orchestration — without it, agents can't wait for results.

**Interface:**

```
wezterm-bridge wait <target> --match <regex> [--timeout <secs>] [--interval <secs>]
wezterm-bridge wait <target> --quiet <secs> [--timeout <secs>] [--interval <secs>]
wezterm-bridge wait <target> --prompt [--timeout <secs>] [--interval <secs>]
```

**Flags:**
- `--match <regex>` — wait until any line in the last 50 lines matches the extended regex (grep -E)
- `--quiet <secs>` — wait until pane output hasn't changed for N seconds (agent finished working)
- `--prompt` — shortcut for `--match '^[›$%#>] ?$'` (common shell/agent prompts)
- `--timeout <secs>` — maximum wait time before failing. Default: 120.
- `--interval <secs>` — poll interval. Default: 2.

**Exactly one** of `--match`, `--quiet`, or `--prompt` is required.

**Behavior:**
1. Resolve target, validate flags
2. Loop: read pane content via `wezterm cli get-text`, check condition
3. On match: print the matched line to stdout, set read guard (`mark_read`), exit 0
4. On timeout: print error to stderr, exit 1
5. `--quiet` works by hashing pane content each poll and tracking when it last changed

**State files:** None persistent. The content hash for `--quiet` is tracked in a local variable during the loop.

**Read guard:** `wait` satisfies the read guard on success (it just read the pane). On timeout, no guard is set.

**Implementation notes:**
- Uses `wezterm cli get-text --pane-id <id> --start-line -50` for each poll
- Regex matching via `grep -qE "$pattern"` on the captured text
- Content hashing via `md5sum` or `cksum` for `--quiet` mode
- The polling loop uses `sleep "$interval"` between checks

---

## 2. `read --new` (Incremental Reads)

**Purpose:** Return only new output since the last read of a target pane. Reduces noise and makes automation reliable.

**Interface:**

```
wezterm-bridge read <target> [lines]       # existing behavior, unchanged
wezterm-bridge read <target> --new         # only lines since last read
```

**Cursor system:**
- After every `read` (both normal and `--new`), store a cursor in `/tmp/wezterm-bridge-$UID/cursors/<pane_id>`
- Cursor file contains: line count + hash of the last line read
- On `--new`: read full visible content, find where the cursor left off, return only new lines
- If cursor doesn't exist or can't be matched (scrollback wrapped), fall back to last 50 lines

**Cursor file format:**
```
<line_count>:<hash_of_last_line>
```

Example: `142:a3f8b2c1` means "last read ended at line 142, last line hashed to a3f8b2c1."

**Matching algorithm for `--new`:**
1. Read all visible content with `wezterm cli get-text --pane-id <id> --start-line -500`
2. Load cursor (line count + hash)
3. Search backward from the expected position for the hashed line
4. Return everything after that line
5. If not found (content scrolled past), return all captured content with a warning prefix

**Read guard:** Both modes satisfy the read guard as before.

---

## 3. `spawn` Command

**Purpose:** Split a pane, start a command, and label it — one step instead of three.

**Interface:**

```
wezterm-bridge spawn <label> [--cmd <command>] [--cwd <dir>] [--horizontal]
```

**Flags:**
- `<label>` — required. Label for the new pane.
- `--cmd <command>` — command to run in the new pane. Default: user's `$SHELL`.
- `--cwd <dir>` — working directory. Default: current directory.
- `--horizontal` — split horizontally (side by side). Default: vertical (top/bottom).

**Behavior:**
1. Build `wezterm cli split-pane` command with flags
2. Capture the new pane ID from stdout
3. Label the new pane via the existing `cmd_name` logic
4. Print: `spawned pane <id> as '<label>'`

**Implementation:**

```bash
cmd_spawn() {
    require_args 1 $# "spawn"
    require_wezterm
    local label="$1"; shift
    local cmd="" cwd="" direction="--bottom"

    # Parse optional flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cmd)  cmd="$2"; shift 2 ;;
            --cwd)  cwd="$2"; shift 2 ;;
            --horizontal) direction="--right"; shift ;;
            *) die "unknown flag '$1' for spawn" ;;
        esac
    done

    local args=("wezterm" "cli" "split-pane" "$direction")
    [[ -n "$cwd" ]] && args+=(--cwd "$cwd")
    if [[ -n "$cmd" ]]; then
        args+=(--)
        args+=($cmd)
    fi

    local new_pane_id
    new_pane_id="$("${args[@]}")"

    # Label the new pane (reuse existing dedup logic)
    ensure_label_dir
    local f
    for f in "$LABEL_DIR"/*; do
        [[ -f "$f" ]] || continue
        if [[ "$(cat "$f")" == "$label" ]]; then
            rm -f "$f"
        fi
    done
    printf '%s\n' "$label" > "$LABEL_DIR/$new_pane_id"

    echo "spawned pane $new_pane_id as '$label'"
}
```

---

## 4. `log` (Audit Log)

**Purpose:** Record all bridge operations to a session log for observability and debugging.

**Interface:**

```
wezterm-bridge log [--tail <n>]     # view last N entries (default: 20)
wezterm-bridge log --clear          # clear the log file
```

**Log file:** `/tmp/wezterm-bridge-$UID/bridge.log`

**Log format:**
```
YYYY-MM-DDTHH:MM:SS ACTOR>TARGET COMMAND [SUMMARY]
```

Examples:
```
2026-03-29T12:34:56 0>1 message "Review auth.ts"
2026-03-29T12:34:58 0>1 keys Enter
2026-03-29T12:35:01 0<1 read 50
2026-03-29T12:35:30 0>1 wait --match "done" matched=28s
2026-03-29T12:36:00 0>- spawn codex pane=3
2026-03-29T12:36:05 0>1 lock acquired
2026-03-29T12:36:10 0>1 unlock released
```

**Implementation:**

Add a `log_event()` function called at the end of each command:

```bash
LOG_FILE="/tmp/wezterm-bridge-${UID:-$(id -u)}/bridge.log"

log_event() {
    local actor="${WEZTERM_PANE:-?}"
    local direction="$1"  # > or <
    local target="$2"
    local cmd="$3"
    local summary="${4:-}"
    ensure_dirs
    printf '%s %s%s%s %s %s\n' \
        "$(date -Iseconds)" "$actor" "$direction" "$target" "$cmd" "$summary" \
        >> "$LOG_FILE"
}
```

Each command calls `log_event` after its action succeeds. Failures are not logged (the command exits via `die` before reaching the log call).

**Viewing:**

```bash
cmd_log() {
    local tail_n=20
    if [[ "${1:-}" == "--clear" ]]; then
        > "$LOG_FILE"
        echo "log cleared"
        return
    fi
    if [[ "${1:-}" == "--tail" ]]; then
        tail_n="${2:-20}"
    fi
    if [[ -f "$LOG_FILE" ]]; then
        tail -n "$tail_n" "$LOG_FILE"
    else
        echo "(no log entries yet)"
    fi
}
```

---

## 5. `--json` Global Flag

**Purpose:** Machine-readable output for scripting and tool integration.

**Interface:**

```
wezterm-bridge --json <command> [args...]
```

**Implementation:**

Parse `--json` in `main()` before command dispatch. Set global `JSON_OUTPUT=true`.

```bash
JSON_OUTPUT=false

main() {
    if [[ "${1:-}" == "--json" ]]; then
        JSON_OUTPUT=true
        shift
    fi
    # ... existing dispatch
}
```

Add helper functions:

```bash
json_ok() {
    local cmd="$1"; shift
    # Remaining args are key=value pairs
    printf '{"status":"ok","command":"%s"' "$cmd"
    while [[ $# -gt 0 ]]; do
        local key="${1%%=*}" val="${1#*=}"
        printf ',"%s":"%s"' "$key" "$val"
        shift
    done
    printf '}\n'
}

json_error() {
    printf '{"status":"error","message":"%s"}\n' "$1"
}
```

Each command checks `$JSON_OUTPUT` and emits JSON instead of human-readable text. The `die()` function also checks it to emit JSON errors.

**JSON output examples:**

```json
{"status":"ok","command":"list","data":[{"pane_id":0,"tab_id":0,"title":"Claude Code","label":"claude","cwd":"~"}]}
{"status":"ok","command":"read","pane_id":"1","lines":50,"content":"..."}
{"status":"ok","command":"wait","pane_id":"1","matched_line":"done","elapsed_seconds":28}
{"status":"ok","command":"spawn","pane_id":"3","label":"codex"}
{"status":"error","message":"must read pane 1 before interacting"}
```

**Special handling:**
- `read` and `read --new`: output content as a `"content"` field (newlines escaped)
- `list`: output full pane array as `"data"` field
- `wait`: include `"matched_line"` and `"elapsed_seconds"`

---

## 6. `lock` / `unlock` Commands

**Purpose:** Mutex per pane to prevent two agents from typing into the same pane simultaneously.

**Interface:**

```
wezterm-bridge lock <target> [--timeout <secs>]
wezterm-bridge unlock <target>
```

**Lock file:** `/tmp/wezterm-bridge-$UID/locks/<pane_id>`

**Lock file content:**
```
<locking_pane_id>:<timestamp>:<timeout_secs>
```

Example: `0:1711712160:30` means "pane 0 locked this at epoch 1711712160, lock expires after 30 seconds."

**Behavior:**

`lock`:
1. Resolve target
2. Check if lock file exists and is not expired
3. If locked by another pane and not expired: fail with "pane locked by <label/id> (expires in Ns)"
4. If unlocked or expired: write lock file, read the pane (satisfies guard), print "locked pane <id>"
5. Default timeout: 30 seconds

`unlock`:
1. Resolve target
2. Check if lock exists and is owned by current pane
3. If owned: remove lock file, print "unlocked pane <id>"
4. If not owned: fail with "pane locked by <other>, cannot unlock"
5. If not locked: print "pane <id> not locked" (idempotent)

**Write commands check locks:**

`cmd_type`, `cmd_keys`, `cmd_message` gain a lock check before `require_read`:

```bash
check_lock() {
    local target="$1"
    local lock_file="/tmp/wezterm-bridge-${UID:-$(id -u)}/locks/$target"
    if [[ -f "$lock_file" ]]; then
        local owner ts timeout
        IFS=: read -r owner ts timeout < "$lock_file"
        local now
        now="$(date +%s)"
        local expires=$(( ts + timeout ))
        if (( now < expires )) && [[ "$owner" != "${WEZTERM_PANE:-}" ]]; then
            local remaining=$(( expires - now ))
            die "pane $target locked by pane $owner (expires in ${remaining}s)"
        fi
        # Expired or we own it — proceed
        if (( now >= expires )); then
            rm -f "$lock_file"
        fi
    fi
}
```

Lock checks are advisory — they prevent accidental concurrent writes but don't provide kernel-level guarantees. This is appropriate for the use case (coordinating cooperative agents, not adversarial processes).

---

## File Changes Summary

| File | Changes |
|------|---------|
| `bin/wezterm-bridge` | Add 6 commands (wait, read --new, spawn, log, lock, unlock), --json flag, log_event() calls in all commands, check_lock() in write commands |
| `tests/test_wait.sh` | Unit tests for wait (mock wezterm, test timeout, match, quiet) |
| `tests/test_incremental.sh` | Unit tests for cursor system |
| `tests/test_spawn.sh` | Unit tests for spawn flag parsing |
| `tests/test_log.sh` | Unit tests for log append and view |
| `tests/test_json.sh` | Unit tests for JSON output mode |
| `tests/test_lock.sh` | Unit tests for lock/unlock and expiry |
| `skills/wezterm-bridge/SKILL.md` | Document new commands |
| `skills/wezterm-bridge/references/wezterm-bridge.md` | API reference for new commands |
| `README.md` | Update with new commands |

## State Directory Layout (after v2)

```
/tmp/wezterm-bridge-$UID/
├── labels/          # pane label files
│   ├── 0            # contains "claude"
│   └── 1            # contains "codex"
├── read-0           # read guard for pane 0
├── read-1           # read guard for pane 1
├── cursors/         # NEW: incremental read cursors
│   ├── 0            # cursor for pane 0
│   └── 1            # cursor for pane 1
├── locks/           # NEW: pane lock files
│   └── 1            # lock on pane 1
└── bridge.log       # NEW: audit log
```
