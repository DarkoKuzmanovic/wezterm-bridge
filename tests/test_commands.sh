#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." >/dev/null && pwd)/bin/wezterm-bridge"
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
assert_eq "read returns content" "true" "$([[ -n "$output" ]] && echo true || echo false)"

# Test: guard file created after read
echo "Test: guard created after read"
assert_eq "guard exists" "true" "$([[ -f "/tmp/wezterm-bridge-read-${TEST_PANE}" ]] && echo true || echo false)"

# Test: type sends text
echo "Test: type sends text (guard already satisfied)"
bash "$BRIDGE" type "$TEST_PANE" "hello from test"
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
assert_eq "guard cleared after message" "false" "$([[ -f "/tmp/wezterm-bridge-read-${TEST_PANE}" ]] && echo true || echo false)"

# Test: keys sends Enter
echo "Test: keys sends Enter"
bash "$BRIDGE" read testpane 5
bash "$BRIDGE" keys testpane Enter
assert_eq "guard cleared after keys" "false" "$([[ -f "/tmp/wezterm-bridge-read-${TEST_PANE}" ]] && echo true || echo false)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
