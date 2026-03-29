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
    if ( "$@" ) >/dev/null 2>&1; then
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

echo "=== Workflow Parser Tests ==="

# Test: parse valid workflow
echo "Test: parse valid workflow"
cat > "$TMPDIR_TEST/review.wb" <<'WB'
#! name: code-review
#! description: Review code
#! var: TARGET=codex
#! var: FILE=src/auth.ts

# A comment
read $TARGET 20
message $TARGET --enter "Review $FILE"
WB
parse_workflow "$TMPDIR_TEST/review.wb"
assert_eq "name" "code-review" "$WF_NAME"
assert_eq "description" "Review code" "$WF_DESCRIPTION"
assert_eq "body line count" "2" "${#WF_BODY[@]}"
assert_eq "body line 0" 'read $TARGET 20' "${WF_BODY[0]}"
assert_eq "body line 1" 'message $TARGET --enter "Review $FILE"' "${WF_BODY[1]}"

# Test: variable defaults parsed
echo "Test: variable defaults"
local_var_result="$(wf_var_lookup TARGET)"
assert_eq "TARGET default" "codex" "$local_var_result"
local_var_result="$(wf_var_lookup FILE)"
assert_eq "FILE default" "src/auth.ts" "$local_var_result"

# Test: undefined var lookup fails
echo "Test: undefined var lookup fails"
assert_fails "undefined var" wf_var_lookup NOPE

# Test: empty file
echo "Test: empty file"
cat > "$TMPDIR_TEST/empty.wb" <<'WB'
#! name: empty
WB
parse_workflow "$TMPDIR_TEST/empty.wb"
assert_eq "empty body" "0" "${#WF_BODY[@]}"

# Test: rejects run in body
echo "Test: rejects run in body"
cat > "$TMPDIR_TEST/nested.wb" <<'WB'
#! name: nested
run other-workflow
WB
assert_fails "nested run" parse_workflow "$TMPDIR_TEST/nested.wb"

# Test: missing file
echo "Test: missing file"
assert_fails "missing file" parse_workflow "$TMPDIR_TEST/nonexistent.wb"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
