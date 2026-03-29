#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." >/dev/null && pwd)/bin/wezterm-bridge"
PASS=0; FAIL=0
TMPDIR_TEST="$(mktemp -d)"

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
    rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

source "$BRIDGE" --source-only

echo "=== Workflow Resolution Tests ==="

# Test: explicit path with /
echo "Test: explicit path"
mkdir -p "$TMPDIR_TEST/sub"
touch "$TMPDIR_TEST/sub/review.wb"
result="$(resolve_workflow "$TMPDIR_TEST/sub/review.wb")"
assert_eq "path with /" "$TMPDIR_TEST/sub/review.wb" "$result"

# Test: explicit .wb suffix
echo "Test: .wb suffix"
touch "$TMPDIR_TEST/review.wb"
result="$(resolve_workflow "$TMPDIR_TEST/review.wb")"
assert_eq ".wb suffix" "$TMPDIR_TEST/review.wb" "$result"

# Test: project-local lookup
echo "Test: project-local lookup"
mkdir -p "$TMPDIR_TEST/project/.wezterm-bridge/workflows"
touch "$TMPDIR_TEST/project/.wezterm-bridge/workflows/deploy.wb"
result="$(cd "$TMPDIR_TEST/project" && resolve_workflow "deploy")"
assert_eq "project-local" "$TMPDIR_TEST/project/.wezterm-bridge/workflows/deploy.wb" "$result"

# Test: global lookup
echo "Test: global lookup"
mkdir -p "$TMPDIR_TEST/fakehome/.wezterm-bridge/workflows"
touch "$TMPDIR_TEST/fakehome/.wezterm-bridge/workflows/setup.wb"
result="$(HOME="$TMPDIR_TEST/fakehome" resolve_workflow "setup")"
assert_eq "global" "$TMPDIR_TEST/fakehome/.wezterm-bridge/workflows/setup.wb" "$result"

# Test: not found
echo "Test: not found"
assert_fails "not found" bash -c "source '$BRIDGE' --source-only; HOME='$TMPDIR_TEST/empty' resolve_workflow 'nonexistent'"

# Test: explicit path not found
echo "Test: explicit path not found"
assert_fails "missing path" bash -c "source '$BRIDGE' --source-only; resolve_workflow '$TMPDIR_TEST/nope.wb'"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
