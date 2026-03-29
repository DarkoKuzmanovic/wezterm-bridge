#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." >/dev/null && pwd)/bin/wezterm-bridge"
LABEL_DIR="/tmp/wezterm-bridge-${UID:-$(id -u)}/labels"
PASS=0; FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        (( PASS += 1 ))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        (( FAIL += 1 ))
    fi
}

assert_fails() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  FAIL: $desc (expected failure, got success)"
        (( FAIL += 1 ))
    else
        echo "  PASS: $desc"
        (( PASS += 1 ))
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
