#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." >/dev/null && pwd)/bin/wezterm-bridge"
GUARD_PREFIX="/tmp/wezterm-bridge-${UID:-$(id -u)}/read"
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
echo "Test: guard file creation"
touch "${GUARD_PREFIX}-42"
assert_eq "guard file exists" "true" "$([[ -f "${GUARD_PREFIX}-42" ]] && echo true || echo false)"

# Test: type succeeds with guard present (will fail on wezterm send-text but guard check passes)
echo "Test: type with guard passes guard check"
output="$(bash "$BRIDGE" type 42 "hello" 2>&1 || true)"
if [[ "$output" == *"must read pane"* ]]; then
    echo "  FAIL: guard check still blocking"
    (( FAIL += 1 ))
else
    echo "  PASS: guard check passed (wezterm error expected)"
    (( PASS += 1 ))
fi

# Test: type --enter without text fails
echo "Test: type --enter without text fails"
touch "${GUARD_PREFIX}-42"
assert_fails "type --enter no text" bash "$BRIDGE" type 42 --enter

# Test: message --enter without text fails
echo "Test: message --enter without text fails"
touch "${GUARD_PREFIX}-42"
assert_fails "message --enter no text" env WEZTERM_PANE=1 bash "$BRIDGE" message 42 --enter

# Test: type --enter with text passes guard check
echo "Test: type --enter with text passes guard check"
touch "${GUARD_PREFIX}-42"
output="$(bash "$BRIDGE" type 42 --enter "hello" 2>&1 || true)"
if [[ "$output" == *"requires text argument"* ]]; then
    echo "  FAIL: text validation rejected valid input"
    (( FAIL += 1 ))
elif [[ "$output" == *"must read pane"* ]]; then
    echo "  FAIL: guard check still blocking"
    (( FAIL += 1 ))
else
    echo "  PASS: --enter with text passes validation (wezterm error expected)"
    (( PASS += 1 ))
fi

cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
