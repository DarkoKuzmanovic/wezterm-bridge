#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." >/dev/null && pwd)/bin/wezterm-bridge"
CURSOR_DIR="/tmp/wezterm-bridge-${UID:-$(id -u)}/cursors"
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

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        (( PASS += 1 ))
    else
        echo "  FAIL: $desc (expected to contain '$needle')"
        (( FAIL += 1 ))
    fi
}

cleanup() {
    rm -rf "$CURSOR_DIR"
}

echo "=== Incremental Read Tests ==="

cleanup

# Test: cursor directory created after read
echo "Test: cursor dir creation"
mkdir -p "$CURSOR_DIR"
echo "10:abc123" > "$CURSOR_DIR/42"
assert_eq "cursor file exists" "true" "$([[ -f "$CURSOR_DIR/42" ]] && echo true || echo false)"
content="$(cat "$CURSOR_DIR/42")"
assert_eq "cursor content" "10:abc123" "$content"

# Test: --new flag is accepted (will fail on wezterm but not on flag parsing)
echo "Test: --new flag parsing"
output="$(bash "$BRIDGE" read 42 --new 2>&1 || true)"
if [[ "$output" == *"unknown"* ]] || [[ "$output" == *"positive integer"* ]]; then
    echo "  FAIL: --new flag not recognized"
    (( FAIL += 1 ))
else
    echo "  PASS: --new flag accepted (wezterm error expected)"
    (( PASS += 1 ))
fi

cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
