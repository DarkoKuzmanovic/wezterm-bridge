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
    rm -rf "/tmp/wezterm-bridge-${UID:-$(id -u)}/labels"
}

echo "=== JSON Output Tests ==="

cleanup

# Test: --json version
echo "Test: --json version"
output="$(bash "$BRIDGE" --json --version 2>&1)"
assert_contains "json has status" '"status"' "$output"
assert_contains "json has ok" '"ok"' "$output"

# Test: --json id (with WEZTERM_PANE set)
echo "Test: --json id"
output="$(WEZTERM_PANE=5 bash "$BRIDGE" --json id 2>&1)"
assert_contains "json has pane_id" '"pane_id"' "$output"
assert_contains "json has 5" '"5"' "$output"

# Test: --json name
echo "Test: --json name"
output="$(bash "$BRIDGE" --json name 42 testjson 2>&1)"
assert_contains "json has status ok" '"ok"' "$output"
assert_contains "json has label" '"testjson"' "$output"

# Test: --json resolve
echo "Test: --json resolve"
output="$(bash "$BRIDGE" --json resolve testjson 2>&1)"
assert_contains "json has pane_id" '"pane_id"' "$output"
assert_contains "json has 42" '"42"' "$output"

# Test: --json error
echo "Test: --json error on unknown command"
output="$(bash "$BRIDGE" --json bogus 2>&1 || true)"
assert_contains "json error" '"error"' "$output"

# Test: --json error on missing read guard
echo "Test: --json error on guard failure"
output="$(bash "$BRIDGE" --json type 42 hello 2>&1 || true)"
assert_contains "json error guard" '"error"' "$output"
assert_contains "json error message" '"must read' "$output"

cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
