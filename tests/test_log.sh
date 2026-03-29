#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." >/dev/null && pwd)/bin/wezterm-bridge"
LOG_FILE="/tmp/wezterm-bridge-${UID:-$(id -u)}/bridge.log"
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
    rm -f "$LOG_FILE"
}

echo "=== Log System Tests ==="

cleanup

# Test: log with no entries
echo "Test: log with no entries"
output="$(bash "$BRIDGE" log 2>&1)"
assert_contains "empty log message" "no log entries" "$output"

# Test: log_event appends to log (name command triggers logging)
echo "Test: name command logs"
bash "$BRIDGE" name 42 testpane >/dev/null
assert_eq "log file exists" "true" "$([[ -f "$LOG_FILE" ]] && echo true || echo false)"
line="$(cat "$LOG_FILE")"
assert_contains "log has name command" "name" "$line"
assert_contains "log has label" "testpane" "$line"

# Test: log --tail shows entries
echo "Test: log --tail"
bash "$BRIDGE" name 43 another >/dev/null
output="$(bash "$BRIDGE" log --tail 1)"
assert_contains "tail shows last entry" "another" "$output"

# Test: log --clear
echo "Test: log --clear"
bash "$BRIDGE" log --clear >/dev/null
assert_eq "log file empty" "0" "$(wc -c < "$LOG_FILE" | tr -d ' ')"

cleanup
rm -rf "/tmp/wezterm-bridge-${UID:-$(id -u)}/labels"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
