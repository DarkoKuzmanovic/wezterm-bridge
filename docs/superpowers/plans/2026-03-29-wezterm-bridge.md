# wezterm-bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a CLI bridge that lets AI agents (Claude Code, Codex) communicate with each other through WezTerm panes — read pane content, send text/keys, and exchange structured messages.

**Architecture:** A single bash script (`wezterm-bridge`) wrapping WezTerm CLI commands (`get-text`, `send-text`, `list`) with a read-guard safety system and file-based pane labeling. Agents learn the API through a SKILL.md prompt document injected into their context. An install script handles PATH setup and dependency checks.

**Tech Stack:** Bash (strict mode), WezTerm CLI, jq (for JSON parsing of `wezterm cli list --format json`)

---

## File Structure

```
~/source/wezterm-bridge/
├── bin/
│   └── wezterm-bridge              # Main CLI (~350 lines bash)
├── skills/
│   └── wezterm-bridge/
│       ├── SKILL.md                # Agent instruction document
│       └── references/
│           └── wezterm-bridge.md   # Detailed API reference
├── tests/
│   ├── test_guard.sh               # Read-guard unit tests
│   ├── test_labels.sh              # Label system unit tests
│   └── test_commands.sh            # Command integration tests (requires WezTerm)
├── install.sh                      # Install/uninstall/update script
├── CLAUDE.md                       # Project dev instructions
├── LICENSE                         # MIT
└── README.md                       # Usage docs
```

**Key design decisions:**
- **File-based labels** instead of tmux's `@name` metadata — WezTerm CLI has no pane-level metadata store. Labels stored at `/tmp/wezterm-bridge-labels/<pane_id>`.
- **jq dependency** for reliable JSON parsing of `wezterm cli list --format json`. The table output is fragile to parse.
- **Special keys via escape sequences** — WezTerm `send-text --no-paste` accepts raw bytes, so Enter = `\n`, Escape = `\x1b`, Ctrl+C = `\x03`, etc. No named key API like tmux's `send-keys Enter`.
- **`$WEZTERM_PANE`** env var for current pane ID (equivalent to tmux's `$TMUX_PANE`).

---

### Task 1: Project Scaffold and Core Utilities

**Files:**
- Create: `bin/wezterm-bridge`
- Create: `CLAUDE.md`
- Create: `.gitignore`

- [ ] **Step 1: Create .gitignore**

```gitignore
*.swp
*.swo
*~
.DS_Store
/tmp/
```

- [ ] **Step 2: Create CLAUDE.md**

```markdown
# wezterm-bridge

CLI bridge for AI agent communication through WezTerm panes.

## Dev

- Bash strict mode (`set -euo pipefail`) everywhere
- Test with: `bash tests/test_guard.sh && bash tests/test_labels.sh && bash tests/test_commands.sh`
- The script must work without WezTerm running for unit tests (mock guards/labels)
- jq is a required dependency

## Architecture

- `bin/wezterm-bridge` — single bash script, all commands
- Labels stored in `/tmp/wezterm-bridge-labels/`
- Read guards stored in `/tmp/wezterm-bridge-read-<pane_id>`
- Special keys sent as raw escape sequences via `send-text --no-paste`
```

- [ ] **Step 3: Create the script scaffold with argument parsing and utility functions**

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
LABEL_DIR="/tmp/wezterm-bridge-labels"
GUARD_PREFIX="/tmp/wezterm-bridge-read"

# --- Utilities ---

die() {
    echo "error: $*" >&2
    exit 1
}

require_args() {
    local need="$1" have="$2" cmd="$3"
    if (( have < need )); then
        die "'$cmd' requires at least $need argument(s). Run: wezterm-bridge help"
    fi
}

require_wezterm() {
    command -v wezterm >/dev/null 2>&1 || die "wezterm is not installed"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || die "jq is not installed. Install with: sudo pacman -S jq"
}

ensure_label_dir() {
    [[ -d "$LABEL_DIR" ]] || mkdir -p "$LABEL_DIR"
}

# --- Read Guard ---

guard_path() {
    local pane_id="$1"
    echo "${GUARD_PREFIX}-${pane_id}"
}

mark_read() {
    touch "$(guard_path "$1")"
}

require_read() {
    local guard
    guard="$(guard_path "$1")"
    if [[ ! -f "$guard" ]]; then
        die "must read pane $1 before interacting. Run: wezterm-bridge read $1"
    fi
}

clear_read() {
    rm -f "$(guard_path "$1")"
}

# --- Target Resolution ---

resolve_label() {
    ensure_label_dir
    local label="$1"
    for f in "$LABEL_DIR"/*; do
        [[ -f "$f" ]] || continue
        if [[ "$(cat "$f")" == "$label" ]]; then
            basename "$f"
            return 0
        fi
    done
    die "no pane found with label '$label'"
}

resolve_target() {
    local target="$1"
    # Numeric pane ID — use directly
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        echo "$target"
        return
    fi
    # Otherwise treat as label
    resolve_label "$target"
}

# --- Main Dispatch ---

show_help() {
    cat <<'USAGE'
wezterm-bridge — AI agent communication through WezTerm panes

COMMANDS:
  list                        List all panes with IDs, titles, labels
  read <target> [lines]       Read pane content (default: 50 lines). Satisfies read guard.
  type <target> <text>        Send text to pane (no Enter). Requires prior read.
  keys <target> <key>...      Send special keys (Enter, Escape, C-c, Tab, etc). Requires prior read.
  message <target> <text>     Send prefixed message for agent-to-agent chat. Requires prior read.
  name <target> <label>       Label a pane for easy reference
  resolve <label>             Show pane ID for a label
  id                          Print current pane ID ($WEZTERM_PANE)
  doctor                      Run diagnostics

OPTIONS:
  --version                   Print version
  --help, help                Show this help

EXAMPLES:
  wezterm-bridge list
  wezterm-bridge name 3 codex
  wezterm-bridge read codex 30
  wezterm-bridge message codex 'Please review src/auth.ts'
  wezterm-bridge keys codex Enter
USAGE
}

main() {
    case "${1:-help}" in
        list)       shift; cmd_list "$@" ;;
        read)       shift; cmd_read "$@" ;;
        type)       shift; cmd_type "$@" ;;
        keys)       shift; cmd_keys "$@" ;;
        message)    shift; cmd_message "$@" ;;
        name)       shift; cmd_name "$@" ;;
        resolve)    shift; cmd_resolve "$@" ;;
        id)         cmd_id ;;
        doctor)     cmd_doctor ;;
        --version)  echo "wezterm-bridge $VERSION" ;;
        help|--help) show_help ;;
        *)          die "unknown command '$1'. Run: wezterm-bridge help" ;;
    esac
}

main "$@"
```

- [ ] **Step 4: Make executable and verify it parses**

Run: `chmod +x bin/wezterm-bridge && bash bin/wezterm-bridge --version`
Expected: `wezterm-bridge 1.0.0`

Run: `bash bin/wezterm-bridge help`
Expected: Help text with all commands listed

Run: `bash bin/wezterm-bridge bogus 2>&1; echo "exit: $?"`
Expected: `error: unknown command 'bogus'...` with exit code 1

- [ ] **Step 5: Commit**

```bash
git add .gitignore CLAUDE.md bin/wezterm-bridge
git commit -m "feat: scaffold wezterm-bridge with arg parsing and utilities"
```

---

### Task 2: `id` Command

**Files:**
- Modify: `bin/wezterm-bridge` (add `cmd_id` function)

- [ ] **Step 1: Implement cmd_id**

Add before `main()`:

```bash
cmd_id() {
    if [[ -z "${WEZTERM_PANE:-}" ]]; then
        die "not running inside a WezTerm pane (\$WEZTERM_PANE not set)"
    fi
    echo "$WEZTERM_PANE"
}
```

- [ ] **Step 2: Test**

Run: `WEZTERM_PANE=5 bash bin/wezterm-bridge id`
Expected: `5`

Run: `unset WEZTERM_PANE; bash bin/wezterm-bridge id 2>&1; echo "exit: $?"`
Expected: `error: not running inside a WezTerm pane` with exit 1

- [ ] **Step 3: Commit**

```bash
git add bin/wezterm-bridge
git commit -m "feat: add id command"
```

---

### Task 3: Label System (`name`, `resolve`)

**Files:**
- Modify: `bin/wezterm-bridge` (add `cmd_name`, `cmd_resolve`)
- Create: `tests/test_labels.sh`

- [ ] **Step 1: Write label tests**

```bash
#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." && pwd)/bin/wezterm-bridge"
LABEL_DIR="/tmp/wezterm-bridge-labels"
PASS=0; FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        ((FAIL++))
    fi
}

assert_fails() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  FAIL: $desc (expected failure, got success)"
        ((FAIL++))
    else
        echo "  PASS: $desc"
        ((PASS++))
    fi
}

cleanup() {
    rm -rf "$LABEL_DIR"
}

echo "=== Label System Tests ==="

# Setup
cleanup

# Test: name creates label file
echo "Test: name creates label file"
bash "$BRIDGE" name 42 claude
assert_eq "label file exists" "claude" "$(cat "$LABEL_DIR/42")"

# Test: resolve finds labeled pane
echo "Test: resolve finds labeled pane"
result="$(bash "$BRIDGE" resolve claude)"
assert_eq "resolve returns pane id" "42" "$result"

# Test: resolve fails for unknown label
echo "Test: resolve fails for unknown label"
assert_fails "unknown label fails" bash "$BRIDGE" resolve nonexistent

# Test: name overwrites existing label
echo "Test: name overwrites existing label"
bash "$BRIDGE" name 42 codex
assert_eq "label updated" "codex" "$(cat "$LABEL_DIR/42")"
assert_fails "old label gone" bash "$BRIDGE" resolve claude

# Test: multiple panes with different labels
echo "Test: multiple labels"
bash "$BRIDGE" name 42 codex
bash "$BRIDGE" name 99 claude
result_codex="$(bash "$BRIDGE" resolve codex)"
result_claude="$(bash "$BRIDGE" resolve claude)"
assert_eq "codex resolves" "42" "$result_codex"
assert_eq "claude resolves" "99" "$result_claude"

# Cleanup
cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_labels.sh 2>&1`
Expected: Failures because `cmd_name` and `cmd_resolve` don't exist yet

- [ ] **Step 3: Implement cmd_name and cmd_resolve**

Add before `main()`:

```bash
cmd_name() {
    require_args 2 $# "name"
    local target="$1"
    local label="$2"
    # If target is a label, resolve it first
    if [[ ! "$target" =~ ^[0-9]+$ ]]; then
        target="$(resolve_label "$target")"
    fi
    ensure_label_dir
    echo "$label" > "$LABEL_DIR/$target"
    echo "pane $target labeled '$label'"
}

cmd_resolve() {
    require_args 1 $# "resolve"
    resolve_label "$1"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_labels.sh`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add bin/wezterm-bridge tests/test_labels.sh
git commit -m "feat: add name/resolve commands with file-based label system"
```

---

### Task 4: Read Guard System

**Files:**
- Create: `tests/test_guard.sh`

The guard functions are already in the scaffold. This task tests them in isolation.

- [ ] **Step 1: Write guard tests**

```bash
#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." && pwd)/bin/wezterm-bridge"
GUARD_PREFIX="/tmp/wezterm-bridge-read"
PASS=0; FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        ((FAIL++))
    fi
}

assert_fails() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  FAIL: $desc (expected failure, got success)"
        ((FAIL++))
    else
        echo "  PASS: $desc"
        ((PASS++))
    fi
}

cleanup() {
    rm -f ${GUARD_PREFIX}-*
}

echo "=== Read Guard Tests ==="

cleanup

# Test: type without read fails
echo "Test: type without read fails"
assert_fails "type before read" bash "$BRIDGE" type 42 "hello"

# Test: keys without read fails
echo "Test: keys without read fails"
assert_fails "keys before read" bash "$BRIDGE" keys 42 Enter

# Test: message without read fails
echo "Test: message without read fails"
assert_fails "message before read" env WEZTERM_PANE=1 bash "$BRIDGE" message 42 "hello"

# Test: guard file created by mark_read
# (We can't easily call read without a running WezTerm, so we test the guard file directly)
echo "Test: guard file creation"
touch "${GUARD_PREFIX}-42"
assert_eq "guard file exists" "true" "$([[ -f "${GUARD_PREFIX}-42" ]] && echo true || echo false)"

# Test: type succeeds with guard present (will fail on wezterm send-text but guard check passes)
# We test this by checking the error message — it should NOT be the guard error
echo "Test: type with guard passes guard check"
output="$(bash "$BRIDGE" type 42 "hello" 2>&1 || true)"
# Should fail with wezterm error, not guard error
if [[ "$output" == *"must read pane"* ]]; then
    echo "  FAIL: guard check still blocking"
    ((FAIL++))
else
    echo "  PASS: guard check passed (wezterm error expected)"
    ((PASS++))
fi

cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run tests — they should fail because cmd_type/cmd_keys/cmd_message aren't implemented yet**

Run: `bash tests/test_guard.sh 2>&1`
Expected: Script-level failures (function not found)

- [ ] **Step 3: Add stub commands that enforce guards but call wezterm**

These will be properly implemented in Tasks 5-7, but we need stubs for guard testing:

```bash
cmd_type() {
    require_args 2 $# "type"
    local target
    target="$(resolve_target "$1")"
    require_read "$target"
    require_wezterm
    echo "$2" | wezterm cli send-text --pane-id "$target" --no-paste
    clear_read "$target"
}

cmd_keys() {
    require_args 2 $# "keys"
    local target
    target="$(resolve_target "$1")"
    require_read "$target"
    shift # consume target
    require_wezterm
    local seq=""
    for key in "$@"; do
        case "$key" in
            Enter)   seq+='\n' ;;
            Escape)  seq+='\x1b' ;;
            Tab)     seq+='\t' ;;
            C-c)     seq+='\x03' ;;
            C-d)     seq+='\x04' ;;
            C-z)     seq+='\x1a' ;;
            C-l)     seq+='\x0c' ;;
            C-a)     seq+='\x01' ;;
            C-e)     seq+='\x05' ;;
            C-u)     seq+='\x15' ;;
            C-k)     seq+='\x0b' ;;
            C-w)     seq+='\x17' ;;
            Space)   seq+=' ' ;;
            BSpace)  seq+='\x7f' ;;
            Up)      seq+='\x1b[A' ;;
            Down)    seq+='\x1b[B' ;;
            Right)   seq+='\x1b[C' ;;
            Left)    seq+='\x1b[D' ;;
            *)       die "unknown key: $key. Supported: Enter, Escape, Tab, C-c, C-d, C-z, C-l, C-a, C-e, C-u, C-k, C-w, Space, BSpace, Up, Down, Left, Right" ;;
        esac
    done
    printf "$seq" | wezterm cli send-text --pane-id "$target" --no-paste
    clear_read "$target"
}

cmd_message() {
    require_args 2 $# "message"
    local target
    target="$(resolve_target "$1")"
    require_read "$target"
    require_wezterm
    local pane_id="${WEZTERM_PANE:-unknown}"
    local label=""
    ensure_label_dir
    if [[ -f "$LABEL_DIR/$pane_id" ]]; then
        label="$(cat "$LABEL_DIR/$pane_id")"
    fi
    local sender="${label:-pane:$pane_id}"
    local msg="[wezterm-bridge from:${sender}] $2"
    echo "$msg" | wezterm cli send-text --pane-id "$target" --no-paste
    clear_read "$target"
}
```

- [ ] **Step 4: Run guard tests**

Run: `bash tests/test_guard.sh`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add bin/wezterm-bridge tests/test_guard.sh
git commit -m "feat: add read guard system with type/keys/message stubs"
```

---

### Task 5: `read` Command

**Files:**
- Modify: `bin/wezterm-bridge` (add `cmd_read`)

- [ ] **Step 1: Implement cmd_read**

Add before `main()`:

```bash
cmd_read() {
    require_args 1 $# "read"
    require_wezterm
    local target
    target="$(resolve_target "$1")"
    local lines="${2:-50}"

    # Negative start-line = scrollback offset
    local start_line="-${lines}"
    wezterm cli get-text --pane-id "$target" --start-line "$start_line"
    mark_read "$target"
}
```

- [ ] **Step 2: Manual test (requires WezTerm)**

Run inside WezTerm with a second pane open:
```bash
# In pane A, find pane B's ID:
wezterm cli list --format json | jq '.[].pane_id'
# Then:
bin/wezterm-bridge read <pane_B_id> 10
```
Expected: Last 10 lines of pane B's terminal output, and guard file created at `/tmp/wezterm-bridge-read-<pane_B_id>`

- [ ] **Step 3: Commit**

```bash
git add bin/wezterm-bridge
git commit -m "feat: add read command with scrollback line control"
```

---

### Task 6: `list` Command

**Files:**
- Modify: `bin/wezterm-bridge` (add `cmd_list`)

- [ ] **Step 1: Implement cmd_list**

Add before `main()`:

```bash
cmd_list() {
    require_wezterm
    require_jq

    ensure_label_dir

    # Header
    printf "%-8s %-6s %-20s %-10s %s\n" "PANE_ID" "TAB" "TITLE" "LABEL" "CWD"
    printf "%-8s %-6s %-20s %-10s %s\n" "-------" "-----" "--------------------" "----------" "---"

    wezterm cli list --format json | jq -r '.[] | "\(.pane_id)\t\(.tab_id)\t\(.title)\t\(.cwd)"' | \
    while IFS=$'\t' read -r pane_id tab_id title cwd; do
        local label="-"
        if [[ -f "$LABEL_DIR/$pane_id" ]]; then
            label="$(cat "$LABEL_DIR/$pane_id")"
        fi
        # Shorten home dir
        cwd="${cwd/#$HOME/~}"
        # Truncate title
        if [[ ${#title} -gt 20 ]]; then
            title="${title:0:17}..."
        fi
        printf "%-8s %-6s %-20s %-10s %s\n" "$pane_id" "$tab_id" "$title" "$label" "$cwd"
    done
}
```

- [ ] **Step 2: Manual test (requires WezTerm)**

Run inside WezTerm:
```bash
bin/wezterm-bridge list
```
Expected: Table showing all panes with IDs, tab IDs, titles, labels (- if none), and working directories

- [ ] **Step 3: Commit**

```bash
git add bin/wezterm-bridge
git commit -m "feat: add list command with pane discovery and label display"
```

---

### Task 7: Finalize `type`, `keys`, `message` Commands

**Files:**
- Modify: `bin/wezterm-bridge` (refine implementations from Task 4 stubs)
- Create: `tests/test_commands.sh`

The stubs from Task 4 are already functional. This task adds the integration test.

- [ ] **Step 1: Write integration test script**

```bash
#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." && pwd)/bin/wezterm-bridge"
PASS=0; FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        ((FAIL++))
    fi
}

echo "=== Command Integration Tests ==="
echo "(These tests require a running WezTerm instance)"
echo ""

# Check if we're in WezTerm
if [[ -z "${WEZTERM_PANE:-}" ]]; then
    echo "SKIP: Not running inside WezTerm. Set WEZTERM_PANE to run these tests."
    exit 0
fi

MY_PANE="$WEZTERM_PANE"

# Create a test pane
echo "Setting up: creating test pane..."
TEST_PANE="$(wezterm cli split-pane --right -- bash -c 'sleep 30')"
sleep 1

cleanup() {
    wezterm cli kill-pane --pane-id "$TEST_PANE" 2>/dev/null || true
    rm -f /tmp/wezterm-bridge-read-* /tmp/wezterm-bridge-labels/*
}
trap cleanup EXIT

# Test: read captures content
echo "Test: read captures pane content"
output="$(bash "$BRIDGE" read "$TEST_PANE" 5)"
# Sleep command should show something
assert_eq "read returns content" "true" "$([[ -n "$output" ]] && echo true || echo false)"

# Test: guard file created after read
echo "Test: guard created after read"
assert_eq "guard exists" "true" "$([[ -f "/tmp/wezterm-bridge-read-${TEST_PANE}" ]] && echo true || echo false)"

# Test: type sends text
echo "Test: type sends text (guard already satisfied)"
bash "$BRIDGE" type "$TEST_PANE" "hello from test"
# Guard should be cleared
assert_eq "guard cleared after type" "false" "$([[ -f "/tmp/wezterm-bridge-read-${TEST_PANE}" ]] && echo true || echo false)"

# Test: name + resolve integration with read
echo "Test: label and read by label"
bash "$BRIDGE" name "$TEST_PANE" testpane
bash "$BRIDGE" read testpane 5
assert_eq "read by label works" "true" "$([[ -f "/tmp/wezterm-bridge-read-${TEST_PANE}" ]] && echo true || echo false)"

# Test: message includes prefix
echo "Test: message with prefix"
bash "$BRIDGE" name "$MY_PANE" tester
bash "$BRIDGE" message testpane "hello agent"
# Message was sent — verify guard cleared
assert_eq "guard cleared after message" "false" "$([[ -f "/tmp/wezterm-bridge-read-${TEST_PANE}" ]] && echo true || echo false)"

# Test: keys sends Enter
echo "Test: keys sends Enter"
bash "$BRIDGE" read testpane 5
bash "$BRIDGE" keys testpane Enter
assert_eq "guard cleared after keys" "false" "$([[ -f "/tmp/wezterm-bridge-read-${TEST_PANE}" ]] && echo true || echo false)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run tests inside WezTerm**

Run: `bash tests/test_commands.sh`
Expected: All tests pass (or SKIP if not in WezTerm)

- [ ] **Step 3: Commit**

```bash
git add tests/test_commands.sh
git commit -m "feat: add integration tests for type/keys/message commands"
```

---

### Task 8: `doctor` Command

**Files:**
- Modify: `bin/wezterm-bridge` (add `cmd_doctor`)

- [ ] **Step 1: Implement cmd_doctor**

Add before `main()`:

```bash
cmd_doctor() {
    local ok=true

    echo "wezterm-bridge $VERSION diagnostics"
    echo "=================================="

    # Check wezterm
    if command -v wezterm >/dev/null 2>&1; then
        echo "  [ok] wezterm found: $(wezterm --version)"
    else
        echo "  [!!] wezterm not found"
        ok=false
    fi

    # Check jq
    if command -v jq >/dev/null 2>&1; then
        echo "  [ok] jq found: $(jq --version)"
    else
        echo "  [!!] jq not found — install with your package manager"
        ok=false
    fi

    # Check WEZTERM_PANE
    if [[ -n "${WEZTERM_PANE:-}" ]]; then
        echo "  [ok] WEZTERM_PANE=$WEZTERM_PANE"
    else
        echo "  [!!] WEZTERM_PANE not set — not running inside WezTerm?"
        ok=false
    fi

    # Check WezTerm connectivity
    if wezterm cli list >/dev/null 2>&1; then
        local pane_count
        pane_count="$(wezterm cli list --format json | jq 'length')"
        echo "  [ok] WezTerm connected — $pane_count pane(s) visible"
    else
        echo "  [!!] Cannot connect to WezTerm — is it running?"
        ok=false
    fi

    # Check label dir
    ensure_label_dir
    local label_count
    label_count="$(find "$LABEL_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
    echo "  [ok] Label dir: $LABEL_DIR ($label_count label(s))"

    # Check guard files
    local guard_count
    guard_count="$(ls ${GUARD_PREFIX}-* 2>/dev/null | wc -l | tr -d ' ')"
    echo "  [ok] Active read guards: $guard_count"

    echo ""
    if $ok; then
        echo "All checks passed."
    else
        echo "Some checks failed. Fix the issues above."
        exit 1
    fi
}
```

- [ ] **Step 2: Test**

Run: `bash bin/wezterm-bridge doctor 2>&1`
Expected: Outputs diagnostics. Some checks may show `[!!]` if not inside WezTerm, but the script should not crash.

- [ ] **Step 3: Commit**

```bash
git add bin/wezterm-bridge
git commit -m "feat: add doctor command for diagnostics"
```

---

### Task 9: SKILL.md — Agent Instruction Document

**Files:**
- Create: `skills/wezterm-bridge/SKILL.md`
- Create: `skills/wezterm-bridge/references/wezterm-bridge.md`

- [ ] **Step 1: Write the SKILL.md**

```markdown
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
```

- [ ] **Step 2: Write the API reference**

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add skills/
git commit -m "feat: add SKILL.md and API reference for agent integration"
```

---

### Task 10: Install Script

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write install.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
INSTALL_DIR="$HOME/.wezterm-bridge"
BIN_DIR="$INSTALL_DIR/bin"
SKILL_DIR="$INSTALL_DIR/skills"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

info() { echo "  [*] $*"; }
ok()   { echo "  [ok] $*"; }
err()  { echo "  [!!] $*" >&2; }

detect_shell_rc() {
    case "$(basename "${SHELL:-bash}")" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        *)    echo "$HOME/.bashrc" ;;
    esac
}

cmd_install() {
    echo "wezterm-bridge $VERSION installer"
    echo "================================"

    # Check dependencies
    if ! command -v wezterm >/dev/null 2>&1; then
        err "wezterm not found. Install WezTerm first."
        exit 1
    fi
    ok "wezterm found"

    if ! command -v jq >/dev/null 2>&1; then
        err "jq not found. Install with your package manager (e.g., sudo pacman -S jq)"
        exit 1
    fi
    ok "jq found"

    # Create directories
    mkdir -p "$BIN_DIR" "$SKILL_DIR"
    ok "created $INSTALL_DIR"

    # Copy files
    cp "$SCRIPT_DIR/bin/wezterm-bridge" "$BIN_DIR/wezterm-bridge"
    chmod +x "$BIN_DIR/wezterm-bridge"
    ok "installed wezterm-bridge to $BIN_DIR"

    if [[ -d "$SCRIPT_DIR/skills" ]]; then
        cp -r "$SCRIPT_DIR/skills/"* "$SKILL_DIR/"
        ok "installed skills to $SKILL_DIR"
    fi

    # Update PATH
    local rc_file
    rc_file="$(detect_shell_rc)"
    local path_line="export PATH=\"$BIN_DIR:\$PATH\""

    if ! grep -qF "$BIN_DIR" "$rc_file" 2>/dev/null; then
        echo "" >> "$rc_file"
        echo "# wezterm-bridge" >> "$rc_file"
        echo "$path_line" >> "$rc_file"
        ok "added $BIN_DIR to PATH in $rc_file"
        info "run: source $rc_file"
    else
        ok "PATH already configured in $rc_file"
    fi

    echo ""
    echo "Done! Run 'wezterm-bridge doctor' to verify."
}

cmd_uninstall() {
    echo "Uninstalling wezterm-bridge..."

    rm -rf "$INSTALL_DIR"
    ok "removed $INSTALL_DIR"

    local rc_file
    rc_file="$(detect_shell_rc)"
    if grep -qF "wezterm-bridge" "$rc_file" 2>/dev/null; then
        sed -i '/# wezterm-bridge/d;/\.wezterm-bridge\/bin/d' "$rc_file"
        ok "removed PATH entry from $rc_file"
    fi

    # Clean temp files
    rm -f /tmp/wezterm-bridge-read-*
    rm -rf /tmp/wezterm-bridge-labels
    ok "cleaned temp files"

    echo "Done."
}

cmd_help() {
    cat <<'USAGE'
wezterm-bridge installer

COMMANDS:
  install       Install wezterm-bridge and add to PATH
  uninstall     Remove wezterm-bridge and clean up
  help          Show this help
USAGE
}

case "${1:-help}" in
    install)    cmd_install ;;
    uninstall)  cmd_uninstall ;;
    help|--help) cmd_help ;;
    *)          err "unknown command '$1'"; cmd_help; exit 1 ;;
esac
```

- [ ] **Step 2: Make executable and test help**

Run: `chmod +x install.sh && bash install.sh help`
Expected: Help text displayed

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add install/uninstall script"
```

---

### Task 11: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

```markdown
# wezterm-bridge

A CLI bridge for AI agent communication through WezTerm panes. Run Claude Code and Codex side by side and let them talk to each other.

Inspired by [smux](https://github.com/ShawnPana/smux/) — rebuilt from scratch for WezTerm.

## Requirements

- [WezTerm](https://wezfurlong.org/wezterm/) (recent version with `wezterm cli` support)
- [jq](https://jqlang.github.io/jq/) for JSON parsing
- Bash 4+

## Install

```bash
git clone https://github.com/YOUR_USER/wezterm-bridge.git
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
wezterm-bridge list                              # see all panes
wezterm-bridge read codex 20                     # read pane (required before write)
wezterm-bridge message codex 'Review auth.ts'    # send message
wezterm-bridge read codex 20                     # verify text landed
wezterm-bridge keys codex Enter                  # submit
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
| `type <target> <text>` | Send text (no Enter). Requires read guard. |
| `keys <target> <key>...` | Send special keys (Enter, Escape, C-c, etc). |
| `message <target> <text>` | Send prefixed agent-to-agent message. |
| `name <target> <label>` | Label a pane for easy reference. |
| `resolve <label>` | Get pane ID for a label. |
| `id` | Print current pane ID. |
| `doctor` | Run diagnostics. |

## How It Works

The bridge wraps three WezTerm CLI primitives:
- `wezterm cli get-text` — read pane scrollback
- `wezterm cli send-text` — inject text into a pane
- `wezterm cli list` — discover panes

A **read-guard** system (temp files in `/tmp/`) enforces a read-before-write discipline, preventing agents from blindly firing commands.

Pane **labels** are stored in `/tmp/wezterm-bridge-labels/` so agents can refer to each other by name instead of numeric IDs.

## Uninstall

```bash
bash install.sh uninstall
```

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with usage and setup instructions"
```

---

### Task 12: Run All Tests and Final Verification

**Files:**
- Modify: `CLAUDE.md` (update test command)

- [ ] **Step 1: Run unit tests (no WezTerm required)**

Run: `bash tests/test_guard.sh && bash tests/test_labels.sh`
Expected: All tests pass

- [ ] **Step 2: Run integration tests (inside WezTerm)**

Run: `bash tests/test_commands.sh`
Expected: All tests pass or SKIP if not in WezTerm

- [ ] **Step 3: Run doctor**

Run: `bash bin/wezterm-bridge doctor`
Expected: Diagnostics output (some checks may warn if not in WezTerm)

- [ ] **Step 4: Verify full help**

Run: `bash bin/wezterm-bridge help`
Expected: Complete help text with all commands

- [ ] **Step 5: Test install script (dry run)**

Run: `bash install.sh help`
Expected: Help text

- [ ] **Step 6: Final commit if any changes**

```bash
git add -A
git commit -m "chore: final verification pass"
```
