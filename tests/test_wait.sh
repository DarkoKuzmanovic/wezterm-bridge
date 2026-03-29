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

echo "=== Wait Command Tests ==="

# Test: wait requires a condition flag
echo "Test: wait without condition fails"
assert_fails "no condition" bash "$BRIDGE" wait 42

# Test: wait rejects multiple conditions
echo "Test: wait with two conditions fails"
assert_fails "two conditions" bash "$BRIDGE" wait 42 --match "foo" --quiet 5

# Test: wait validates timeout
echo "Test: wait with bad timeout fails"
assert_fails "bad timeout" bash "$BRIDGE" wait 42 --match "foo" --timeout abc

# Test: wait validates interval
echo "Test: wait with bad interval fails"
assert_fails "bad interval" bash "$BRIDGE" wait 42 --match "foo" --interval abc

# Test: wait validates quiet seconds
echo "Test: wait with bad quiet fails"
assert_fails "bad quiet" bash "$BRIDGE" wait 42 --quiet abc

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
