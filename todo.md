# wezterm-bridge Post-v2 Backlog

## High

- **Declarative workflows**  
  Priority: high  
  Add a file-driven way to declare multi-step bridge runs such as spawn, wait, read, message, and submit. This would turn the current atomic CLI into a reusable orchestration layer for repeatable agent handoffs.

- **Safety policies**  
  Priority: high  
  Add configurable guardrails for which panes, commands, keys, and message patterns are allowed. This reduces accidental or unsafe automation when multiple agents are sharing a live terminal session.

- **Task handoff primitives**  
  Priority: high  
  Add explicit handoff semantics such as claim, assign, ack, done, blocked, and return-with-context. This would let agents coordinate ownership and status without overloading free-form chat messages.

## Medium

- **Session manifests**  
  Priority: medium  
  Add a manifest format that describes the expected panes, labels, working directories, startup commands, and roles for a session. This would make complex bridge setups reproducible and easier to recover after restarts.

- **Pane groups / broadcast**  
  Priority: medium  
  Add logical pane groups plus broadcast operations for reads, messages, and key sends across a set of targets. This is useful for swarm-style coordination, but it should land after stronger workflow and safety primitives.

- **Bridge-aware `SKILL.md` auto-injection**  
  Priority: medium  
  Add automatic injection of the bridge skill into spawned or attached agent contexts when the environment supports it. This removes manual setup drift and makes the bridge protocol more consistent across tools.

- **Codex-integration bridge mode**  
  Priority: medium  
  Add a first-class integration mode for Codex that understands pane labels, read guards, waits, and structured handoffs out of the box. This would lower friction for mixed-agent sessions and make bridge usage more scriptable from Codex workflows.
