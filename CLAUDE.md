# wezterm-bridge

CLI bridge for AI agent communication through WezTerm panes.

## Dev

- Bash strict mode (`set -euo pipefail`) everywhere
- Test with: `bash tests/test_guard.sh && bash tests/test_labels.sh && bash tests/test_commands.sh && bash tests/test_tokenizer.sh && bash tests/test_workflow_parse.sh && bash tests/test_workflow_resolve.sh && bash tests/test_workflow_run.sh`
- The script must work without WezTerm running for unit tests (mock guards/labels)
- jq is a required dependency

## Architecture

- `bin/wezterm-bridge` — single bash script, all commands
- Labels stored in `/tmp/wezterm-bridge-labels/`
- Read guards stored in `/tmp/wezterm-bridge-read-<pane_id>`
- Special keys sent as raw escape sequences via `send-text --no-paste`
