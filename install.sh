#!/bin/bash
# Install or uninstall the claude-code-janitor orphan killer.
#
# Usage:
#   ./install.sh              # Install
#   ./install.sh uninstall    # Remove

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}==>${NC} $1"; }
fail() { echo -e "${RED}Error:${NC} $1" >&2; exit 1; }

install_orphan_killer() {
    info "Installing orphan process killer..."

    cp "$SCRIPT_DIR/scripts/kill-orphan-claude.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/kill-orphan-claude.sh"

    sed "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
        "$SCRIPT_DIR/launchagents/com.user.kill-orphan-claude.plist" \
        > "$PLIST_PATH"

    # Unload may legitimately fail on first install (no agent loaded yet).
    launchctl unload "$PLIST_PATH" 2>/dev/null || true

    if ! launchctl load "$PLIST_PATH"; then
        fail "launchctl load failed. Plist is at $PLIST_PATH; try 'plutil -lint $PLIST_PATH' and 'launchctl print-disabled gui/$(id -u)'."
    fi

    if ! launchctl list | grep -q "com.user.kill-orphan-claude"; then
        fail "launchctl load returned 0 but the agent did not register. Check $PLIST_PATH and 'log stream --predicate \"subsystem == \\\"com.apple.xpc.launchd\\\"\"'."
    fi

    info "Installed. Runs every 2 hours."
}

uninstall() {
    info "Uninstalling..."

    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    rm -f "$INSTALL_DIR/kill-orphan-claude.sh"

    if launchctl list | grep -q "com.user.kill-orphan-claude"; then
        fail "Uninstall removed files but the agent is still registered. Reboot or run 'launchctl bootout gui/$(id -u)/com.user.kill-orphan-claude'."
    fi

    info "Uninstalled."
}

mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENTS_DIR"

case "${1:-install}" in
    install)
        install_orphan_killer
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac

info "Done"
echo ""
echo "Useful commands:"
echo "  launchctl list | grep kill-orphan-claude    # Check status"
echo "  log show --predicate 'eventMessage contains \"kill-orphan-claude\"' --last 1d"
echo "  DRY_RUN=1 $INSTALL_DIR/kill-orphan-claude.sh   # Preview without killing"
echo "  $INSTALL_DIR/kill-orphan-claude.sh             # Run manually"
