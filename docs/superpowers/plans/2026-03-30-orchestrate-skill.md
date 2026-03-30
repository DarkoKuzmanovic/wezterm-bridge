# Orchestrate Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an `orchestrate.md` skill that teaches the orchestrator agent when/how to delegate work to other agents via wezterm-bridge, and retire the standalone `/codex-*` skills.

**Architecture:** The orchestrate skill is a pure documentation file (no CLI changes). It defines a structured message convention for task delegation (`task:` and `status:` fields in the existing `[wezterm-bridge from:]` prefix), proactive suggestion triggers, a known agents table, and post-delegation triage logic. The existing `SKILL.md` gets a small addition to teach receiving agents the convention.

**Tech Stack:** Markdown skill files, bash (no code changes to wezterm-bridge CLI)

---

### Task 1: Create orchestrate.md skill

**Files:**
- Create: `skills/wezterm-bridge/orchestrate.md`

- [ ] **Step 1: Write the orchestrate.md skill file**

Create `skills/wezterm-bridge/orchestrate.md` with this content:

```markdown
---
name: orchestrate
description: Multi-agent task delegation via wezterm-bridge — teaches the orchestrator when and how to delegate work to other agents running in WezTerm panes
---

# Orchestrate

You are the orchestrator agent. You coordinate work across multiple AI agents running in WezTerm panes using `wezterm-bridge`. You decide when to delegate, to whom, and what — then triage the results.

## How Delegation Works

1. **Discover** — run `wezterm-bridge list` to see which agents are available
2. **Delegate** — send a structured message via `wezterm-bridge message`
3. **Receive** — the response arrives in YOUR pane (do not poll the other agent's pane)
4. **Triage** — independently evaluate the response before presenting to the user

## Message Convention

### Sending a task

```bash
wezterm-bridge read <agent>
wezterm-bridge message <agent> --enter '[task:<type>] <prompt>'
```

The bridge auto-prepends `[wezterm-bridge from:<your_label>]`, so the receiving agent sees:

```
[wezterm-bridge from:claude task:review] Review the staged changes in src/auth.ts
```

### Receiving a response

Responses arrive in your pane with a status field:

```
[wezterm-bridge from:codex task:review status:done] LGTM — no issues found
[wezterm-bridge from:codex task:audit status:done] Found 2 issues: ...
[wezterm-bridge from:codex task:test status:error] 3 of 12 tests failed
[wezterm-bridge from:codex task:review status:blocked] Can't find the file
```

### Task types

| Type     | Purpose                            |
|----------|------------------------------------|
| `review` | Code review of changes/files       |
| `audit`  | Security & quality deep dive       |
| `ask`    | Freeform question / second opinion |
| `test`   | Run tests and report results       |

### Status values

| Status    | Meaning                         |
|-----------|---------------------------------|
| `done`    | Task completed successfully     |
| `blocked` | Agent needs more info or access |
| `error`   | Something went wrong            |

## Known Agents

| Label   | Strengths                          | Tasks                  |
|---------|------------------------------------|------------------------|
| codex   | Code review, security analysis     | review, audit, ask, test |
| copilot | Quick questions, research (future) | ask                    |

If you see an unlabeled or unknown agent via `wezterm-bridge list`, ask the user what it can do.

## When to Suggest Delegation

### Proactive: always suggest

| Trigger                                                    | Task   | Example suggestion                                              |
|------------------------------------------------------------|--------|-----------------------------------------------------------------|
| Major feature implemented                                  | review | "Want me to ask codex to review these changes?"                 |
| About to create a PR                                       | review | "Good point to get a review from codex before the PR."          |
| Security-sensitive code touched (auth, crypto, SQL, etc)   | audit  | "These changes touch auth — want codex to audit?"               |
| Complex bug fix                                            | review | "This fix is non-trivial — worth a second pair of eyes?"        |
| Tests needed but you're busy with other work               | test   | "Want me to send the test suite to codex while we continue?"    |

### Proactive: consider suggesting

- Core architecture changes — `review`
- User seems uncertain about approach — `ask`
- Unfamiliar domain — `ask`

### Do NOT suggest

- Trivial changes (typos, comments, formatting)
- User already declined this session for similar scope
- Same changes were already delegated to an agent
- No agents available via `wezterm-bridge list`

### How to suggest

One line. Non-intrusive. If the user says no, move on. Don't re-ask for the same scope.

## User-Initiated Delegation

The user can always explicitly ask you to delegate:

> "Review this and also ask codex to review it"

When this happens, do your own work AND delegate via the bridge. Both paths use the same message convention.

## Execution Flow

When delegation is approved (proactive or explicit):

```bash
# 1. Discover
wezterm-bridge list

# 2. Read target (satisfy guard)
wezterm-bridge read codex

# 3. Send structured task
wezterm-bridge message codex --enter '[task:review] Review the staged changes in src/auth.ts for correctness'

# 4. STOP — do NOT poll. Response arrives in YOUR pane.
```

## Post-Delegation Triage

When a response arrives from a `review` or `audit` task, independently evaluate each finding:

| Verdict     | Meaning                            |
|-------------|------------------------------------|
| ACCEPT      | Real issue, recommend implementing |
| REJECT      | False positive, explain why        |
| PARTIAL     | Valid concern, different fix needed |
| INVESTIGATE | Needs more context before deciding |

Present a summary table to the user:

| # | Finding               | Agent says          | Your call   |
|---|-----------------------|---------------------|-------------|
| 1 | Weak key derivation   | HIGH — use bcrypt   | ACCEPT      |
| 2 | Missing null check    | MEDIUM — add guard  | REJECT — guaranteed non-null by caller |
| 3 | SQL injection risk    | CRITICAL — parameterize | ACCEPT  |

The user makes the final call on what to implement.

**For `test` tasks:** Report pass/fail directly. No triage needed.

**For `ask` tasks:** Present the agent's answer, then add your own perspective. Give the user two viewpoints.
```

- [ ] **Step 2: Verify the file was created correctly**

Run: `head -5 skills/wezterm-bridge/orchestrate.md`
Expected: the YAML frontmatter with `name: orchestrate`

- [ ] **Step 3: Commit**

```bash
git add skills/wezterm-bridge/orchestrate.md
git commit -m "feat: add orchestrate skill for multi-agent task delegation"
```

---

### Task 2: Update SKILL.md with receiving-side convention

**Files:**
- Modify: `skills/wezterm-bridge/SKILL.md`

The existing `SKILL.md` needs a small section so that non-orchestrator agents (Codex, Copilot) understand the structured message format when they receive a delegation request.

- [ ] **Step 1: Add the task delegation section to SKILL.md**

After the existing `## Message Format` section (around line 96), add:

```markdown
## Task Delegation Messages

You may receive messages with a `task:` field in the prefix:

```
[wezterm-bridge from:claude task:review] Review the staged changes in src/auth.ts
```

This is a structured task request. The task types are:

| Type     | What to do                                              |
|----------|---------------------------------------------------------|
| `review` | Review the specified code/changes and report findings   |
| `audit`  | Security & quality audit of specified files             |
| `ask`    | Answer the question or give your perspective            |
| `test`   | Run the specified tests and report results              |

When you respond, include a `status:` field so the sender knows the outcome:

```bash
wezterm-bridge read <sender>
wezterm-bridge message <sender> --enter '[task:review status:done] LGTM — no issues found'
```

Status values: `done` (completed), `blocked` (need more info), `error` (something went wrong).
```

- [ ] **Step 2: Verify the addition**

Run: `grep -n "Task Delegation" skills/wezterm-bridge/SKILL.md`
Expected: line number showing the new section header

- [ ] **Step 3: Commit**

```bash
git add skills/wezterm-bridge/SKILL.md
git commit -m "feat: add task delegation message convention to SKILL.md"
```

---

### Task 3: Update todo.md

**Files:**
- Modify: `todo.md`

- [ ] **Step 1: Update todo.md**

Remove the "Codex-integration bridge mode" item (last item in the Medium section — it's now implemented as the orchestrate skill).

Update the "Task handoff primitives" item in the High section to reference the new message conventions as foundation. Replace its description with:

```markdown
- **Task handoff primitives**
  Priority: high
  Add explicit handoff semantics such as claim, assign, ack, done, blocked, and return-with-context. The orchestrate skill's message convention (`task:` and `status:` fields) provides the foundation — this item extends it with richer lifecycle tracking and multi-step coordination.
```

- [ ] **Step 2: Verify the changes**

Run: `grep -c "Codex-integration" todo.md`
Expected: `0`

Run: `grep "orchestrate" todo.md`
Expected: line referencing the orchestrate skill in the task handoff item

- [ ] **Step 3: Commit**

```bash
git add todo.md
git commit -m "docs: update backlog — codex bridge mode done, reference orchestrate in handoff primitives"
```

---

### Task 4: Retire codex-integration skill

**Files:**
- Delete: `~/.agents/skills/codex-integration/` (directory)
- Delete: `~/.claude/skills/codex-integration` (symlink)

- [ ] **Step 1: Verify what exists before deleting**

Run: `ls -la ~/.claude/skills/codex-integration`
Expected: symlink pointing to `~/.agents/skills/codex-integration`

Run: `ls ~/.agents/skills/codex-integration/`
Expected: `SKILL.md`

- [ ] **Step 2: Delete the symlink and the skill directory**

```bash
rm ~/.claude/skills/codex-integration
rm -rf ~/.agents/skills/codex-integration
```

- [ ] **Step 3: Verify deletion**

Run: `ls ~/.claude/skills/codex-integration 2>&1`
Expected: "No such file or directory"

Run: `ls ~/.agents/skills/codex-integration 2>&1`
Expected: "No such file or directory"

- [ ] **Step 4: Commit** (nothing to commit in the repo — these are external files)

No git commit needed. These files are outside the wezterm-bridge repo.

---

### Task 5: Retire codex command files

**Files:**
- Delete: `~/.claude/commands/codex-review.md`
- Delete: `~/.claude/commands/codex-audit.md`
- Delete: `~/.claude/commands/codex-ask.md`

- [ ] **Step 1: Verify the files exist**

Run: `ls ~/.claude/commands/codex-*.md`
Expected: three files listed (`codex-review.md`, `codex-audit.md`, `codex-ask.md`)

- [ ] **Step 2: Delete the command files**

```bash
rm ~/.claude/commands/codex-review.md
rm ~/.claude/commands/codex-audit.md
rm ~/.claude/commands/codex-ask.md
```

- [ ] **Step 3: Verify deletion**

Run: `ls ~/.claude/commands/codex-*.md 2>&1`
Expected: "No such file or directory"

- [ ] **Step 4: No git commit needed**

These files are outside the wezterm-bridge repo.

---

### Task 6: Clean up settings.local.json reference

**Files:**
- Modify: `~/.claude/settings.local.json`

There's a permission entry for creating the codex-integration symlink that is now stale.

- [ ] **Step 1: Read the settings file to find the exact line**

Read `~/.claude/settings.local.json` and locate the line:
```
"Bash(ln -sf /home/quzma/.agents/skills/codex-integration /home/quzma/.claude/skills/codex-integration)",
```

- [ ] **Step 2: Remove the stale permission entry**

Remove that line from the `allow` array in `settings.local.json`.

- [ ] **Step 3: Verify the file is still valid JSON**

Run: `jq . ~/.claude/settings.local.json > /dev/null && echo "valid JSON"`
Expected: `valid JSON`

- [ ] **Step 4: No git commit needed**

This file is outside the wezterm-bridge repo.

---

### Task 7: Verify install.sh includes new skill

**Files:**
- Read only: `install.sh`

The installer uses `cp -r "$SCRIPT_DIR/skills/"* "$SKILL_DIR/"` (line 50), which recursively copies all files under `skills/`. No change needed — `orchestrate.md` is automatically included.

- [ ] **Step 1: Verify the copy is recursive**

Run: `grep "cp -r" install.sh`
Expected: `cp -r "$SCRIPT_DIR/skills/"* "$SKILL_DIR/"`

No commit needed — install.sh requires no changes.

---

### Task 8: Final verification

- [ ] **Step 1: Verify repo file structure**

Run: `find skills/wezterm-bridge/ -type f | sort`
Expected:
```
skills/wezterm-bridge/SKILL.md
skills/wezterm-bridge/orchestrate.md
skills/wezterm-bridge/references/wezterm-bridge.md
```

- [ ] **Step 2: Verify retired files are gone**

Run: `ls ~/.claude/commands/codex-*.md 2>&1; ls ~/.claude/skills/codex-* 2>&1; ls ~/.agents/skills/codex-* 2>&1`
Expected: all three should report "No such file or directory"

- [ ] **Step 3: Verify SKILL.md has the new section**

Run: `grep "Task Delegation" skills/wezterm-bridge/SKILL.md`
Expected: `## Task Delegation Messages`

- [ ] **Step 4: Verify todo.md is updated**

Run: `grep -c "Codex-integration" todo.md`
Expected: `0`

- [ ] **Step 5: Run existing tests to make sure nothing is broken**

Run: `bash tests/test_guard.sh && bash tests/test_labels.sh && bash tests/test_commands.sh && bash tests/test_tokenizer.sh && bash tests/test_workflow_parse.sh && bash tests/test_workflow_resolve.sh && bash tests/test_workflow_run.sh`
Expected: all tests pass

- [ ] **Step 6: Final commit if any stragglers**

```bash
git status
# If any uncommitted changes remain, commit them
```
