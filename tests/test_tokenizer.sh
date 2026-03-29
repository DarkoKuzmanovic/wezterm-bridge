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

# Source the bridge to access tokenize_line directly
source "$BRIDGE" --source-only

# Provide a test variable lookup
_test_vars() {
    case "$1" in
        TARGET) echo "codex" ;;
        FILE)   echo "src/auth.ts" ;;
        SPACE)  echo "hello world" ;;
        *) return 1 ;;
    esac
}

echo "=== Tokenizer Tests ==="

# Test: simple words
echo "Test: simple words"
tokenize_line "read codex 20" _test_vars
assert_eq "token count" "3" "${#TOKENS[@]}"
assert_eq "token 0" "read" "${TOKENS[0]}"
assert_eq "token 1" "codex" "${TOKENS[1]}"
assert_eq "token 2" "20" "${TOKENS[2]}"

# Test: double-quoted string
echo "Test: double-quoted string"
tokenize_line 'message codex "hello world"' _test_vars
assert_eq "token count" "3" "${#TOKENS[@]}"
assert_eq "token 0" "message" "${TOKENS[0]}"
assert_eq "token 1" "codex" "${TOKENS[1]}"
assert_eq "token 2" "hello world" "${TOKENS[2]}"

# Test: variable expansion
echo "Test: variable expansion"
tokenize_line 'read $TARGET 20' _test_vars
assert_eq "token count" "3" "${#TOKENS[@]}"
assert_eq "token 1" "codex" "${TOKENS[1]}"

# Test: variable in quoted string
echo "Test: variable in quoted string"
tokenize_line 'message $TARGET "Review $FILE"' _test_vars
assert_eq "token count" "3" "${#TOKENS[@]}"
assert_eq "token 1" "codex" "${TOKENS[1]}"
assert_eq "token 2" "Review src/auth.ts" "${TOKENS[2]}"

# Test: variable value with spaces is literal (not re-tokenized)
echo "Test: variable with spaces stays one token"
tokenize_line 'type codex $SPACE' _test_vars
assert_eq "token count" "3" "${#TOKENS[@]}"
assert_eq "token 2" "hello world" "${TOKENS[2]}"

# Test: escaped dollar
echo "Test: escaped dollar"
tokenize_line 'type codex "price is \$5"' _test_vars
assert_eq "token 2" 'price is $5' "${TOKENS[2]}"

# Test: escaped quote inside quotes
echo "Test: escaped quote"
tokenize_line 'type codex "say \"hello\""' _test_vars
assert_eq "token 2" 'say "hello"' "${TOKENS[2]}"

# Test: escaped backslash
echo "Test: escaped backslash"
tokenize_line 'type codex "path\\here"' _test_vars
assert_eq "token 2" 'path\here' "${TOKENS[2]}"

# Test: --enter flag preserved
echo "Test: flags preserved"
tokenize_line 'message codex --enter "hello"' _test_vars
assert_eq "token count" "4" "${#TOKENS[@]}"
assert_eq "token 2" "--enter" "${TOKENS[2]}"
assert_eq "token 3" "hello" "${TOKENS[3]}"

# Test: undefined variable fails
echo "Test: undefined variable fails"
assert_fails "undefined var" bash -c "source '$BRIDGE' --source-only; _no_vars() { return 1; }; tokenize_line 'read \$NOPE' _no_vars"

# Test: $(...) rejected
echo "Test: command substitution rejected"
assert_fails "cmd substitution" bash -c "source '$BRIDGE' --source-only; _nv() { return 1; }; tokenize_line 'type codex \$(date)' _nv"

# Test: backtick rejected
echo "Test: backtick rejected"
assert_fails "backtick" bash -c "source '$BRIDGE' --source-only; _nv() { return 1; }; tokenize_line 'type codex \`date\`' _nv"

# Test: ${...} rejected
echo "Test: brace expansion rejected"
assert_fails "brace expansion" bash -c "source '$BRIDGE' --source-only; _nv() { return 1; }; tokenize_line 'type codex \${FOO}' _nv"

# Test: single quotes rejected
echo "Test: single quotes rejected"
assert_fails "single quotes" bash -c "source '$BRIDGE' --source-only; _nv() { return 1; }; tokenize_line \"type codex 'hello'\" _nv"

# Test: unterminated quote rejected
echo "Test: unterminated quote rejected"
assert_fails "unterminated quote" bash -c "source '$BRIDGE' --source-only; _nv() { return 1; }; tokenize_line 'type codex \"hello' _nv"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
