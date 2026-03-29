# Declarative Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `run` command to wezterm-bridge that executes `.wb` workflow files — linear sequences of bridge commands with variable substitution.

**Architecture:** A custom tokenizer (`tokenize_line`) parses DSL lines into bash arrays. A workflow runner (`cmd_run`) resolves workflow files, parses headers/variables, and executes each step in a subshell via command substitution. All code goes into `bin/wezterm-bridge` (single-file architecture).

**Tech Stack:** Bash 4+, jq (existing dependency)

**Spec:** `docs/superpowers/specs/2026-03-29-declarative-workflows-design.md`

---

### Task 1: Tokenizer — `tokenize_line()`

**Files:**
- Modify: `bin/wezterm-bridge` (add function before `# --- Commands ---` section, around line 209)
- Create: `tests/test_tokenizer.sh`

This function takes a line string and a variable-lookup function name, and populates a global `TOKENS` array. It handles double-quoted strings, backslash escapes, `$NAME` variable expansion, and rejects disallowed syntax.

- [ ] **Step 1: Write the tokenizer test file**

```bash
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
```

Write this to `tests/test_tokenizer.sh`.

- [ ] **Step 2: Run tokenizer tests to verify they fail**

Run: `bash tests/test_tokenizer.sh`
Expected: FAIL (tokenize_line not defined, --source-only not handled)

- [ ] **Step 3: Add --source-only support to main()**

Add at the very end of `bin/wezterm-bridge`, replacing the final `main "$@"` line (line 861):

```bash
if [[ "${1:-}" == "--source-only" ]]; then
    return 0 2>/dev/null || true
else
    main "$@"
fi
```

This allows `source bin/wezterm-bridge --source-only` to load all functions without executing `main`.

- [ ] **Step 4: Implement `tokenize_line()`**

Add this function in `bin/wezterm-bridge` before the `# --- Commands ---` comment (around line 209). The function takes a line and a variable-lookup callback name, and populates the global `TOKENS` array:

```bash
# --- Workflow Tokenizer ---

tokenize_line() {
    local line="$1"
    local var_lookup="$2"
    TOKENS=()
    local i=0 len=${#line} token="" in_quotes=false

    while (( i < len )); do
        local ch="${line:i:1}"

        # Reject single quotes
        if [[ "$ch" == "'" ]] && ! $in_quotes; then
            die "single quotes are not supported in workflow files"
        fi

        # Reject backticks
        if [[ "$ch" == '`' ]]; then
            die "backtick substitution is not allowed in workflow files"
        fi

        if $in_quotes; then
            if [[ "$ch" == '\' ]]; then
                local next="${line:i+1:1}"
                case "$next" in
                    '"')  token+='"' ;;
                    '\') token+='\' ;;
                    '$') token+='$' ;;
                    *)    die "invalid escape '\\$next' in workflow file (allowed: \\\", \\\\, \\\$)" ;;
                esac
                (( i += 2 ))
            elif [[ "$ch" == '"' ]]; then
                in_quotes=false
                (( i++ ))
            elif [[ "$ch" == '$' ]]; then
                # Check for disallowed syntax
                local next="${line:i+1:1}"
                if [[ "$next" == '(' ]]; then
                    die "\$(...) command substitution is not allowed in workflow files"
                fi
                if [[ "$next" == '{' ]]; then
                    die "\${...} brace expansion is not allowed in workflow files"
                fi
                # Extract variable name
                local varname=""
                local j=$(( i + 1 ))
                while (( j < len )) && [[ "${line:j:1}" =~ [A-Za-z0-9_] ]]; do
                    varname+="${line:j:1}"
                    (( j++ ))
                done
                if [[ -z "$varname" ]]; then
                    die "bare \$ in workflow file (use \\\$ for literal dollar)"
                fi
                local varval
                if ! varval="$("$var_lookup" "$varname")"; then
                    die "undefined variable '\$$varname' in workflow file"
                fi
                # Append value as literal data (no re-tokenization)
                token+="$varval"
                i=$j
            else
                token+="$ch"
                (( i++ ))
            fi
        else
            # Outside quotes
            if [[ "$ch" == '"' ]]; then
                in_quotes=true
                (( i++ ))
            elif [[ "$ch" == ' ' || "$ch" == $'\t' ]]; then
                if [[ -n "$token" ]]; then
                    TOKENS+=("$token")
                    token=""
                fi
                (( i++ ))
            elif [[ "$ch" == '\' ]]; then
                local next="${line:i+1:1}"
                if [[ "$next" == '$' ]]; then
                    token+='$'
                    (( i += 2 ))
                else
                    die "invalid escape '\\$next' outside quotes in workflow file"
                fi
            elif [[ "$ch" == '$' ]]; then
                local next="${line:i+1:1}"
                if [[ "$next" == '(' ]]; then
                    die "\$(...) command substitution is not allowed in workflow files"
                fi
                if [[ "$next" == '{' ]]; then
                    die "\${...} brace expansion is not allowed in workflow files"
                fi
                local varname=""
                local j=$(( i + 1 ))
                while (( j < len )) && [[ "${line:j:1}" =~ [A-Za-z0-9_] ]]; do
                    varname+="${line:j:1}"
                    (( j++ ))
                done
                if [[ -z "$varname" ]]; then
                    die "bare \$ in workflow file (use \\\$ for literal dollar)"
                fi
                local varval
                if ! varval="$("$var_lookup" "$varname")"; then
                    die "undefined variable '\$$varname' in workflow file"
                fi
                # Outside quotes: variable value becomes one token (not re-tokenized)
                token+="$varval"
                i=$j
            else
                token+="$ch"
                (( i++ ))
            fi
        fi
    done

    if $in_quotes; then
        die "unterminated quote in workflow file"
    fi

    if [[ -n "$token" ]]; then
        TOKENS+=("$token")
    fi
}
```

- [ ] **Step 5: Run tokenizer tests to verify they pass**

Run: `bash tests/test_tokenizer.sh`
Expected: All tests PASS

- [ ] **Step 6: Run existing tests to verify no regressions**

Run: `bash tests/test_guard.sh && bash tests/test_labels.sh`
Expected: All existing tests PASS

- [ ] **Step 7: Commit**

```bash
git add bin/wezterm-bridge tests/test_tokenizer.sh
git commit -m "feat: add workflow tokenizer with variable expansion and syntax validation"
```

---

### Task 2: Workflow file parser — `parse_workflow()`

**Files:**
- Modify: `bin/wezterm-bridge` (add function after `tokenize_line`)
- Create: `tests/test_workflow_parse.sh`

This function reads a `.wb` file and extracts metadata, variables, and body lines.

- [ ] **Step 1: Write the parser test file**

```bash
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
```

Write this to `tests/test_workflow_parse.sh`.

- [ ] **Step 2: Run parser tests to verify they fail**

Run: `bash tests/test_workflow_parse.sh`
Expected: FAIL (parse_workflow not defined)

- [ ] **Step 3: Implement `parse_workflow()`**

Add this function in `bin/wezterm-bridge` after `tokenize_line()`:

```bash
# --- Workflow Parser ---

parse_workflow() {
    local filepath="$1"
    [[ -f "$filepath" ]] || die "workflow file not found: $filepath"

    WF_NAME=""
    WF_DESCRIPTION=""
    WF_BODY=()
    declare -gA WF_VARS=()

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        (( line_num++ ))

        # Skip blank lines
        [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]] && continue

        # Header lines
        if [[ "$line" =~ ^'#!' ]]; then
            local content="${line#'#!'}"
            content="${content#"${content%%[![:space:]]*}"}"  # trim leading whitespace
            if [[ "$content" =~ ^name:[[:space:]]*(.*) ]]; then
                WF_NAME="${BASH_REMATCH[1]}"
            elif [[ "$content" =~ ^description:[[:space:]]*(.*) ]]; then
                WF_DESCRIPTION="${BASH_REMATCH[1]}"
            elif [[ "$content" =~ ^var:[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*) ]]; then
                WF_VARS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
            else
                die "unknown header directive at line $line_num: $content"
            fi
            continue
        fi

        # Skip comment lines
        [[ "$line" =~ ^[[:space:]]*'#' ]] && continue

        # Body lines — trim leading whitespace
        line="${line#"${line%%[![:space:]]*}"}"

        # Reject nested run
        if [[ "$line" =~ ^run([[:space:]]|$) ]]; then
            die "nested 'run' is not allowed in workflow files (line $line_num)"
        fi

        WF_BODY+=("$line")
    done < "$filepath"
}

wf_var_lookup() {
    local name="$1"
    if [[ -v "WF_VARS[$name]" ]]; then
        printf '%s' "${WF_VARS[$name]}"
    else
        return 1
    fi
}
```

- [ ] **Step 4: Run parser tests to verify they pass**

Run: `bash tests/test_workflow_parse.sh`
Expected: All tests PASS

- [ ] **Step 5: Run existing tests for regressions**

Run: `bash tests/test_guard.sh && bash tests/test_labels.sh && bash tests/test_tokenizer.sh`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add bin/wezterm-bridge tests/test_workflow_parse.sh
git commit -m "feat: add workflow file parser with header, variables, and body extraction"
```

---

### Task 3: Workflow resolution — `resolve_workflow()`

**Files:**
- Modify: `bin/wezterm-bridge` (add function after `parse_workflow`)
- Create: `tests/test_workflow_resolve.sh`

This function takes a name-or-path argument and returns the resolved file path.

- [ ] **Step 1: Write the resolution test file**

```bash
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
```

Write this to `tests/test_workflow_resolve.sh`.

- [ ] **Step 2: Run resolution tests to verify they fail**

Run: `bash tests/test_workflow_resolve.sh`
Expected: FAIL (resolve_workflow not defined)

- [ ] **Step 3: Implement `resolve_workflow()`**

Add this function in `bin/wezterm-bridge` after `wf_var_lookup()`:

```bash
resolve_workflow() {
    local name="$1"

    # Explicit path: contains / or ends in .wb
    if [[ "$name" == */* || "$name" == *.wb ]]; then
        [[ -f "$name" ]] || die "workflow file not found: $name"
        echo "$name"
        return
    fi

    # Project-local
    local project_path=".wezterm-bridge/workflows/${name}.wb"
    if [[ -f "$project_path" ]]; then
        echo "$project_path"
        return
    fi

    # Global
    local global_path="$HOME/.wezterm-bridge/workflows/${name}.wb"
    if [[ -f "$global_path" ]]; then
        echo "$global_path"
        return
    fi

    die "workflow '$name' not found. Searched: ./$project_path, $global_path"
}
```

- [ ] **Step 4: Run resolution tests to verify they pass**

Run: `bash tests/test_workflow_resolve.sh`
Expected: All tests PASS

- [ ] **Step 5: Run all tests for regressions**

Run: `bash tests/test_guard.sh && bash tests/test_labels.sh && bash tests/test_tokenizer.sh && bash tests/test_workflow_parse.sh && bash tests/test_workflow_resolve.sh`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add bin/wezterm-bridge tests/test_workflow_resolve.sh
git commit -m "feat: add workflow resolution (path, project-local, global)"
```

---

### Task 4: Workflow runner — `cmd_run()`

**Files:**
- Modify: `bin/wezterm-bridge` (add function after `resolve_workflow`, update `main()` dispatch and `show_help()`)
- Create: `tests/test_workflow_run.sh`

This is the main runner that ties everything together: resolve, parse, tokenize, and execute steps.

- [ ] **Step 1: Write the runner test file**

```bash
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
```

Write this to `tests/test_workflow_run.sh`.

- [ ] **Step 2: Run runner tests to verify they fail**

Run: `bash tests/test_workflow_run.sh`
Expected: FAIL (cmd_run / run command not recognized)

- [ ] **Step 3: Implement `cmd_run()`**

Add this function in `bin/wezterm-bridge` after `resolve_workflow()`:

```bash
# --- Workflow Runner ---

_wf_valid_commands=(list read type keys message name resolve id spawn lock unlock wait log doctor)

cmd_run() {
    local check_only=false
    if [[ "${1:-}" == "--check" ]]; then
        check_only=true
        shift
    fi

    [[ $# -ge 1 ]] || die "'run' requires a workflow name or path. Run: wezterm-bridge help"

    local wf_path
    wf_path="$(resolve_workflow "$1")"
    shift

    # Parse the workflow file
    parse_workflow "$wf_path"

    # Apply CLI variable overrides
    for arg in "$@"; do
        if [[ "$arg" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local oname="${BASH_REMATCH[1]}"
            local oval="${BASH_REMATCH[2]}"
            if [[ ! -v "WF_VARS[$oname]" ]]; then
                die "unknown variable override '$oname' (not declared in workflow)"
            fi
            WF_VARS["$oname"]="$oval"
        else
            die "invalid argument '$arg' (expected VAR=value)"
        fi
    done

    local total=${#WF_BODY[@]}
    local wf_label="${WF_NAME:-$(basename "$wf_path" .wb)}"

    if $check_only; then
        _wf_check "$wf_label" "$total"
        return
    fi

    # Execute steps
    local last_read_output=""
    local step=0

    for body_line in "${WF_BODY[@]}"; do
        (( step++ ))
        tokenize_line "$body_line" wf_var_lookup
        local command="${TOKENS[0]}"
        local args=("${TOKENS[@]:1}")

        # Validate command
        local valid=false
        for vc in "${_wf_valid_commands[@]}"; do
            [[ "$vc" == "$command" ]] && valid=true && break
        done
        $valid || die "unknown command '$command' in workflow '$wf_label' (step $step/$total)"

        # Log step progress to stderr
        echo "[workflow:$wf_label] step $step/$total: $body_line" >&2

        # Execute in subshell, capture output
        local step_output
        if ! step_output="$(cmd_"$command" "${args[@]}" 2>&1)"; then
            if [[ "$JSON_OUTPUT" == "true" ]]; then
                local emsg
                emsg="$(json_escape "step $step/$total failed: $body_line: $step_output")"
                printf '{"status":"error","command":"run","workflow":"%s","failed_step":%d,"total_steps":%d,"message":"%s"}\n' \
                    "$wf_label" "$step" "$total" "$emsg"
                exit 1
            else
                echo "[workflow:$wf_label] step $step/$total failed: $body_line" >&2
                echo "$step_output" >&2
                exit 1
            fi
        fi

        # Capture last read output
        if [[ "$command" == "read" ]]; then
            last_read_output="$step_output"
        fi

        # Non-read output goes to stderr as progress
        if [[ "$command" != "read" && -n "$step_output" ]]; then
            echo "$step_output" >&2
        fi
    done

    # Print workflow result
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local encoded_result
        encoded_result="$(json_escape "$last_read_output")"
        printf '{"status":"ok","command":"run","workflow":"%s","steps":%d,"result":"%s"}\n' \
            "$wf_label" "$total" "$encoded_result"
    elif [[ -n "$last_read_output" ]]; then
        printf '%s\n' "$last_read_output"
    fi
}

_wf_check() {
    local wf_label="$1"
    local total="$2"
    local step=0
    local -A check_labels=()

    # Pre-populate with existing labels
    if [[ -d "$LABEL_DIR" ]]; then
        for lfile in "$LABEL_DIR"/*; do
            [[ -f "$lfile" ]] || continue
            local lname
            lname="$(cat "$lfile")"
            check_labels["$lname"]=1
        done
    fi

    for body_line in "${WF_BODY[@]}"; do
        (( step++ ))
        tokenize_line "$body_line" wf_var_lookup
        local command="${TOKENS[0]}"

        # Validate command name
        local valid=false
        for vc in "${_wf_valid_commands[@]}"; do
            [[ "$vc" == "$command" ]] && valid=true && break
        done
        $valid || die "unknown command '$command' in workflow '$wf_label' (step $step/$total)"

        # Track labels from spawn and name
        if [[ "$command" == "spawn" ]]; then
            check_labels["${TOKENS[1]}"]=1
        elif [[ "$command" == "name" ]] && [[ ${#TOKENS[@]} -ge 3 ]]; then
            check_labels["${TOKENS[2]}"]=1
        fi
    done

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_ok "run" "workflow=$wf_label" "mode=check" "steps=$total"
    else
        echo "workflow '$wf_label' is valid ($total steps)" >&2
    fi
}
```

- [ ] **Step 4: Add `run` to main() dispatch**

In `bin/wezterm-bridge`, in the `main()` function's case statement (around line 836), add the `run` case before the catch-all:

```bash
        run)        shift; cmd_run "$@" ;;
```

Add it after the `log)` line and before `--version)`.

- [ ] **Step 5: Add `run` to show_help()**

In the `show_help()` function, add after the `doctor` line (around line 815):

```
  run <name|path> [VAR=val]   Run a workflow file (.wb)
                                  --check           Validate without executing
```

- [ ] **Step 6: Run runner tests to verify they pass**

Run: `bash tests/test_workflow_run.sh`
Expected: All tests PASS

- [ ] **Step 7: Run all tests for regressions**

Run: `bash tests/test_guard.sh && bash tests/test_labels.sh && bash tests/test_tokenizer.sh && bash tests/test_workflow_parse.sh && bash tests/test_workflow_resolve.sh && bash tests/test_workflow_run.sh`
Expected: All PASS

- [ ] **Step 8: Commit**

```bash
git add bin/wezterm-bridge tests/test_workflow_run.sh
git commit -m "feat: add workflow runner with subshell step execution and --check validation"
```

---

### Task 5: Update documentation

**Files:**
- Modify: `skills/wezterm-bridge/SKILL.md`
- Modify: `skills/wezterm-bridge/references/wezterm-bridge.md`
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add `run` to SKILL.md command table**

In `skills/wezterm-bridge/SKILL.md`, add to the Commands table after the `doctor` row:

```
| `run <name\|path> [VAR=val]` | Run a workflow file (.wb). `--check` validates without executing. |
```

- [ ] **Step 2: Add `run` section to API reference**

In `skills/wezterm-bridge/references/wezterm-bridge.md`, add a new section before `## doctor`:

```markdown
## run <name|path> [VAR=value ...]

Executes a workflow file (`.wb`) — a linear sequence of bridge commands with variable substitution.

```
wezterm-bridge run review                    # by name (searches .wezterm-bridge/workflows/ then ~/.wezterm-bridge/workflows/)
wezterm-bridge run ./my-workflow.wb          # by path
wezterm-bridge run review TARGET=claude      # override variable
wezterm-bridge run --check review            # validate without executing
```

The last `read` step's output is the workflow result (printed to stdout). All other step output goes to stderr as progress.

Workflow file format:

```
#! name: code-review
#! var: TARGET=codex
#! var: FILE=src/auth.ts

read $TARGET 20
message $TARGET --enter "Review $FILE"
wait $TARGET --quiet 10
read $TARGET --new
```

---
```

- [ ] **Step 3: Add `run` to README command table**

In `README.md`, add to the command table after the `doctor` row:

```
| `run <name\|path> [VAR=val]` | Run a workflow file. `--check` validates. |
```

- [ ] **Step 4: Update CLAUDE.md test command**

In `CLAUDE.md`, update the test command to include the new test files:

```
- Test with: `bash tests/test_guard.sh && bash tests/test_labels.sh && bash tests/test_commands.sh && bash tests/test_tokenizer.sh && bash tests/test_workflow_parse.sh && bash tests/test_workflow_resolve.sh && bash tests/test_workflow_run.sh`
```

- [ ] **Step 5: Commit**

```bash
git add skills/wezterm-bridge/SKILL.md skills/wezterm-bridge/references/wezterm-bridge.md README.md CLAUDE.md
git commit -m "docs: add run command to SKILL.md, API reference, README, and CLAUDE.md"
```

---

### Task 6: Final verification and push

**Files:** None (verification only)

- [ ] **Step 1: Run all tests**

Run: `bash tests/test_guard.sh && bash tests/test_labels.sh && bash tests/test_tokenizer.sh && bash tests/test_workflow_parse.sh && bash tests/test_workflow_resolve.sh && bash tests/test_workflow_run.sh`
Expected: All tests PASS

- [ ] **Step 2: Create a sample workflow file**

Create `.wezterm-bridge/workflows/hello.wb` for smoke testing:

```
#! name: hello
#! description: Simple test workflow
#! var: T=codex

list
```

- [ ] **Step 3: Smoke test --check**

Run: `wezterm-bridge run --check hello`
Expected: `workflow 'hello' is valid (1 steps)`

- [ ] **Step 4: Verify JSON mode**

Run: `wezterm-bridge --json run --check hello`
Expected: `{"status":"ok","command":"run","workflow":"hello","mode":"check","steps":"1"}`

- [ ] **Step 5: Push**

```bash
git push
```
