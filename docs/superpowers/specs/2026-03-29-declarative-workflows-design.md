# Declarative Workflows Design Spec

## Summary

Add a `run` command to wezterm-bridge that executes workflow files (`.wb`) — linear sequences of bridge commands with variable substitution. This eliminates the repeated read/message/keys/wait choreography that agents and humans perform manually today.

## File Format

Workflow files use a simple DSL where each body line is a wezterm-bridge command (without the `wezterm-bridge` prefix). The format has two sections: a header and a body.

### Header

Lines starting with `#!` declare metadata and variables:

```
#! name: code-review
#! description: Send code for review and collect results
#! var: TARGET=codex
#! var: FILE=src/auth.ts
```

- `#! name:` — workflow name (used in logging and JSON output)
- `#! description:` — human-readable description
- `#! var: NAME=value` — declare a variable with a default value

### Body

Each non-header, non-comment, non-blank line is a bridge command:

```
spawn $TARGET --cmd codex --horizontal
read $TARGET 20
message $TARGET --enter "Review $FILE for security issues"
wait $TARGET --quiet 10 --timeout 300
read $TARGET --new
```

- `#` comment lines and blank lines are skipped
- `run` is not allowed in workflow bodies (rejected at parse time)

### Complete example

```
#! name: code-review
#! description: Send code for review and collect results
#! var: TARGET=codex
#! var: FILE=src/auth.ts

# Setup the review pane
spawn $TARGET --cmd codex --horizontal

# Send the review request
read $TARGET 20
message $TARGET --enter "Review $FILE for security issues"

# Wait for the agent to finish and collect results
wait $TARGET --quiet 10 --timeout 300
read $TARGET --new
```

## Parsing Rules

A custom `tokenize_line()` function handles parsing. It is a constrained tokenizer, not a shell evaluator.

### Tokenization

1. Split on whitespace
2. Double-quoted strings preserve spaces inside: `"hello world"` is one token
3. Backslash escapes inside quotes: `\"` (literal quote), `\\` (literal backslash), `\$` (literal dollar)
4. Unquoted tokens split on whitespace boundaries

### Variable Expansion

1. `$NAME` in a line is replaced with the variable's value
2. Expansion happens during tokenization
3. Expanded values are literal data appended to the current token buffer — they are never re-tokenized as syntax
4. Undefined variables are hard errors (workflow aborts at parse time)
5. Literal `$` is written as `\$`

### Rejected syntax

The following are hard parse errors, rejected before execution:

- Single quotes (not supported as string delimiters)
- `$(...)` command substitution
- Backtick substitution
- `${...}` brace expansion
- Unterminated quotes
- Stray backslashes (backslash not followed by `"`, `\`, or `$`)
- `run` as a command (no nested workflows)

## Command: `run`

```
wezterm-bridge run <name-or-path> [VAR=value ...]
wezterm-bridge run --check <name-or-path> [VAR=value ...]
```

### Workflow resolution

1. If argument contains `/` or ends in `.wb` — treat as file path
2. Else look in `.wezterm-bridge/workflows/<name>.wb` (project-local, cwd)
3. Else look in `~/.wezterm-bridge/workflows/<name>.wb` (global)
4. Else die with "workflow not found"

### Variable override

CLI arguments in `VAR=value` form override `#! var:` defaults. Unknown variable names in overrides are errors.

### Execution model

Each body line is parsed, tokenized, and dispatched to the corresponding `cmd_*` function. Steps execute linearly, top to bottom.

#### Step isolation

Each step runs in a subshell via command substitution. This preserves existing `set -e` and `die()` → `exit 1` semantics without any modifications to `cmd_*` functions.

The parent runner captures exit code and output using an errexit-safe pattern:

```bash
if ! step_output="$(cmd_"$command" "${args[@]}" 2>&1)"; then
    # report "step N/M failed" with step_output as error detail
    # abort workflow
fi
```

This works because:

- `$(...)` runs in a subshell — `set -e` and `die()` work exactly as today inside it
- The `if !` form prevents errexit from killing the parent before failure is captured
- All persistent state (guards, labels, locks, cursors) is file-based in `/tmp/` and shared across subshells automatically
- Workflow variables are expanded by the runner before dispatch, so they do not cross subshell boundaries

#### Step failure

If any step exits non-zero, the workflow aborts immediately. The runner reports which step failed and includes the error output:

```
[workflow:code-review] step 3/5 failed: message codex --enter "Review ..."
error: must read pane 1 before interacting. Run: wezterm-bridge read 1
```

### Output handling

- Each step's stdout is redirected to stderr (shown as progress)
- Step progress is logged to stderr: `[workflow:code-review] step 3/5: message codex --enter ...`
- The last `read` step's output is captured as the workflow result and printed to stdout
- Trailing newlines in the result are normalized (standard command substitution behavior)
- Outputs from non-read commands (e.g., `wait --match` status) go to stderr during workflow execution and are not part of the result

### JSON output

```
wezterm-bridge --json run review
```

```json
{"status":"ok","command":"run","workflow":"code-review","steps":5,"result":"<last read output>"}
```

On failure:

```json
{"status":"error","command":"run","workflow":"code-review","failed_step":3,"total_steps":5,"message":"<error detail>"}
```

### Validation mode

```
wezterm-bridge run --check review
```

Validates without executing:

- Parses header and body syntax
- Expands variables (checks for undefined)
- Validates command names (rejects unknown commands, rejects `run`)
- Rejects disallowed syntax (`$(...)`, backticks, etc.)
- Tracks labels declared by `spawn` and `name` steps so that later `read`/`message`/`type`/`keys` steps targeting those labels validate correctly even though the panes do not exist yet

Exits 0 if valid, 1 with error details if not.

## Workflow directory convention

- Project-local: `.wezterm-bridge/workflows/`
- Global: `~/.wezterm-bridge/workflows/`
- File extension: `.wb`

The installer does not create these directories. They are created on demand by users or agents.

## Scope boundaries

This spec covers linear step execution only. The following are explicitly out of scope:

- Conditionals and branching
- Loops and retries
- Step output capture into variables (e.g., `capture ID = spawn ...`)
- Parallel step execution
- Workflow composition (nested `run`)

These may be added in future iterations if needed.

## Testing

- Unit tests for `tokenize_line()`: quoting, escaping, variable expansion, rejected syntax (no WezTerm needed)
- Unit test for workflow resolution: path vs name lookup (no WezTerm needed)
- Unit test for `--check` validation: valid workflow, undefined var, bad syntax, nested run (no WezTerm needed)
- Integration test with a simple workflow file (requires WezTerm)
