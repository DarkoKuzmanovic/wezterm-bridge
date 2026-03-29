#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
INSTALL_DIR="$HOME/.wezterm-bridge"
BIN_DIR="$INSTALL_DIR/bin"
SKILL_DIR="$INSTALL_DIR/skills"
SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null && pwd)"

info() { echo "  [*] $*"; }
ok()   { echo "  [ok] $*"; }
err()  { echo "  [!!] $*" >&2; }

detect_shell_rc() {
    case "$(basename "${SHELL:-bash}")" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        *)    echo "$HOME/.bashrc" ;;
    esac
}

cmd_install() {
    echo "wezterm-bridge $VERSION installer"
    echo "================================"

    # Check dependencies
    if ! command -v wezterm >/dev/null 2>&1; then
        err "wezterm not found. Install WezTerm first."
        exit 1
    fi
    ok "wezterm found"

    if ! command -v jq >/dev/null 2>&1; then
        err "jq not found. Install with your package manager (e.g., sudo pacman -S jq)"
        exit 1
    fi
    ok "jq found"

    # Create directories
    mkdir -p "$BIN_DIR" "$SKILL_DIR"
    ok "created $INSTALL_DIR"

    # Copy files
    cp "$SCRIPT_DIR/bin/wezterm-bridge" "$BIN_DIR/wezterm-bridge"
    chmod +x "$BIN_DIR/wezterm-bridge"
    ok "installed wezterm-bridge to $BIN_DIR"

    if [[ -d "$SCRIPT_DIR/skills" ]]; then
        cp -r "$SCRIPT_DIR/skills/"* "$SKILL_DIR/"
        ok "installed skills to $SKILL_DIR"
    fi

    # Update PATH
    local rc_file shell_name
    rc_file="$(detect_shell_rc)"
    shell_name="$(basename "${SHELL:-bash}")"

    # Ensure parent directory exists (e.g., ~/.config/fish/)
    mkdir -p "$(dirname "$rc_file")"

    if ! grep -qF "$BIN_DIR" "$rc_file" 2>/dev/null; then
        echo "" >> "$rc_file"
        echo "# wezterm-bridge" >> "$rc_file"
        if [[ "$shell_name" == "fish" ]]; then
            echo "set -gx PATH $BIN_DIR \$PATH" >> "$rc_file"
        else
            echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$rc_file"
        fi
        ok "added $BIN_DIR to PATH in $rc_file"
        info "run: source $rc_file"
    else
        ok "PATH already configured in $rc_file"
    fi

    echo ""
    echo "Done! Run 'wezterm-bridge doctor' to verify."
}

cmd_uninstall() {
    echo "Uninstalling wezterm-bridge..."

    rm -rf "$INSTALL_DIR"
    ok "removed $INSTALL_DIR"

    local rc_file
    rc_file="$(detect_shell_rc)"
    if grep -qF "wezterm-bridge" "$rc_file" 2>/dev/null; then
        sed -i '/# wezterm-bridge/d;/\.wezterm-bridge\/bin/d' "$rc_file"
        ok "removed PATH entry from $rc_file"
    fi

    # Clean temp files
    rm -f /tmp/wezterm-bridge-read-*
    rm -rf /tmp/wezterm-bridge-labels
    ok "cleaned temp files"

    echo "Done."
}

cmd_help() {
    cat <<'USAGE'
wezterm-bridge installer

COMMANDS:
  install       Install wezterm-bridge and add to PATH
  uninstall     Remove wezterm-bridge and clean up
  help          Show this help
USAGE
}

case "${1:-help}" in
    install)    cmd_install ;;
    uninstall)  cmd_uninstall ;;
    help|--help) cmd_help ;;
    *)          err "unknown command '$1'"; cmd_help; exit 1 ;;
esac
