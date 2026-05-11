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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}Warning:${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1"; exit 1; }

install_orphan_killer() {
    info "Installing orphan process killer..."

    cp "$SCRIPT_DIR/scripts/kill-orphan-claude.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/kill-orphan-claude.sh"

    sed "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
        "$SCRIPT_DIR/launchagents/com.user.kill-orphan-claude.plist" \
        > "$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist"

    launchctl unload "$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist" 2>/dev/null || true
    launchctl load "$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist"

    info "Installed. Runs every 2 hours."
}

uninstall() {
    info "Uninstalling..."

    launchctl unload "$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist" 2>/dev/null || true
    rm -f "$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist"
    rm -f "$INSTALL_DIR/kill-orphan-claude.sh"

    info "Uninstalled."
}

mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENTS_DIR"

case "${1:-install}" in
    install|"")
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
echo "  cat /tmp/kill-orphan-claude.log             # View logs"
echo "  $INSTALL_DIR/kill-orphan-claude.sh          # Run manually"
