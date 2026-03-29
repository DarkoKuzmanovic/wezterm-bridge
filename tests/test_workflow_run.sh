#!/usr/bin/env bash
set -euo pipefail

BRIDGE="$(cd "$(dirname "$0")/.." >/dev/null && pwd)/bin/wezterm-bridge"
PASS=0; FAIL=0
TMPDIR_TEST="$(mktemp -d)"
LABEL_DIR="/tmp/wezterm-bridge-${UID:-$(id -u)}/labels"
GUARD_PREFIX="/tmp/wezterm-bridge-${UID:-$(id -u)}/read"

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
    rm -rf "$TMPDIR_TEST"
    rm -f ${GUARD_PREFIX}-*
}
trap cleanup EXIT

echo "=== Workflow Runner Tests ==="

# Test: --check validates a good workflow
echo "Test: --check valid workflow"
cat > "$TMPDIR_TEST/good.wb" <<'WB'
#! name: good
#! var: T=codex

list
name 42 mytest
resolve mytest
WB
output="$(bash "$BRIDGE" run --check "$TMPDIR_TEST/good.wb" 2>&1)"
assert_eq "--check exits 0" "0" "$?"

# Test: --check catches undefined variable
echo "Test: --check undefined var"
cat > "$TMPDIR_TEST/badvar.wb" <<'WB'
#! name: badvar
read $UNDEFINED 20
WB
assert_fails "--check undefined var" bash "$BRIDGE" run --check "$TMPDIR_TEST/badvar.wb"

# Test: --check catches nested run
echo "Test: --check nested run"
cat > "$TMPDIR_TEST/nested.wb" <<'WB'
#! name: nested
run other
WB
assert_fails "--check nested run" bash "$BRIDGE" run --check "$TMPDIR_TEST/nested.wb"

# Test: --check catches bad syntax
echo "Test: --check bad syntax"
cat > "$TMPDIR_TEST/badsyntax.wb" <<'WB'
#! name: badsyntax
type codex $(date)
WB
assert_fails "--check bad syntax" bash "$BRIDGE" run --check "$TMPDIR_TEST/badsyntax.wb"

# Test: --check catches unknown command
echo "Test: --check unknown command"
cat > "$TMPDIR_TEST/badcmd.wb" <<'WB'
#! name: badcmd
frobnicate codex
WB
assert_fails "--check unknown cmd" bash "$BRIDGE" run --check "$TMPDIR_TEST/badcmd.wb"

# Test: variable override
echo "Test: variable override"
cat > "$TMPDIR_TEST/override.wb" <<'WB'
#! name: override
#! var: T=codex
list
WB
output="$(bash "$BRIDGE" run --check "$TMPDIR_TEST/override.wb" T=claude 2>&1)"
assert_eq "override exits 0" "0" "$?"

# Test: unknown override variable
echo "Test: unknown override variable"
assert_fails "unknown override" bash "$BRIDGE" run --check "$TMPDIR_TEST/override.wb" NOPE=val

# Test: --check tracks spawn labels
echo "Test: --check spawn label tracking"
cat > "$TMPDIR_TEST/spawnlabel.wb" <<'WB'
#! name: spawnlabel
#! var: T=codex
spawn $T --cmd codex
read $T 20
WB
output="$(bash "$BRIDGE" run --check "$TMPDIR_TEST/spawnlabel.wb" 2>&1)"
assert_eq "spawn+read validates" "0" "$?"

# Test: --check tracks name labels
echo "Test: --check name label tracking"
cat > "$TMPDIR_TEST/namelabel.wb" <<'WB'
#! name: namelabel
name 42 worker
read worker 20
WB
output="$(bash "$BRIDGE" run --check "$TMPDIR_TEST/namelabel.wb" 2>&1)"
assert_eq "name+read validates" "0" "$?"

# Test: step failure reporting (run without wezterm — will fail on wezterm commands)
echo "Test: step failure reports step number"
cat > "$TMPDIR_TEST/failstep.wb" <<'WB'
#! name: failstep
list
WB
output="$(bash "$BRIDGE" run "$TMPDIR_TEST/failstep.wb" 2>&1 || true)"
assert_contains "reports step" "step 1/" "$output"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
