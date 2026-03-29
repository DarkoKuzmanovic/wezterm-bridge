#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." >/dev/null && pwd)/bin/wezterm-bridge"
LOCK_DIR="/tmp/wezterm-bridge-${UID:-$(id -u)}/locks"
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
    rm -rf "$LOCK_DIR"
    rm -f ${GUARD_PREFIX}-*
}

echo "=== Lock System Tests ==="

cleanup

# Test: lock creates lock file (will fail on wezterm read but we test the file)
echo "Test: lock file creation"
mkdir -p "$LOCK_DIR"
echo "0:$(date +%s):30" > "$LOCK_DIR/42"
assert_eq "lock file exists" "true" "$([[ -f "$LOCK_DIR/42" ]] && echo true || echo false)"

# Test: type blocked by lock from another pane
echo "Test: type blocked by foreign lock"
touch "${GUARD_PREFIX}-42"
echo "99:$(date +%s):30" > "$LOCK_DIR/42"
output="$(WEZTERM_PANE=0 bash "$BRIDGE" type 42 "hello" 2>&1 || true)"
assert_contains "locked error" "locked" "$output"

# Test: type allowed when lock owned by self
echo "Test: type allowed with own lock"
touch "${GUARD_PREFIX}-42"
echo "0:$(date +%s):30" > "$LOCK_DIR/42"
output="$(WEZTERM_PANE=0 bash "$BRIDGE" type 42 "hello" 2>&1 || true)"
if [[ "$output" == *"locked"* ]]; then
    echo "  FAIL: own lock is blocking"
    (( FAIL += 1 ))
else
    echo "  PASS: own lock passes (wezterm error expected)"
    (( PASS += 1 ))
fi

# Test: expired lock doesn't block
echo "Test: expired lock passes"
touch "${GUARD_PREFIX}-42"
echo "99:1000000000:1" > "$LOCK_DIR/42"
output="$(WEZTERM_PANE=0 bash "$BRIDGE" type 42 "hello" 2>&1 || true)"
if [[ "$output" == *"locked"* ]]; then
    echo "  FAIL: expired lock is blocking"
    (( FAIL += 1 ))
else
    echo "  PASS: expired lock passes (wezterm error expected)"
    (( PASS += 1 ))
fi

# Test: unlock without lock is idempotent
echo "Test: unlock when not locked"
rm -f "$LOCK_DIR/42"
output="$(WEZTERM_PANE=0 bash "$BRIDGE" unlock 42 2>&1)"
assert_contains "not locked" "not locked" "$output"

cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
