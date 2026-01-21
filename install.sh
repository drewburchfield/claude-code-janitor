#!/bin/bash
# Install Claude Code maintenance scripts and launch agents
#
# Usage:
#   ./install.sh              # Install both scripts
#   ./install.sh orphan       # Install only orphan killer
#   ./install.sh backup       # Install only backup script
#   ./install.sh uninstall    # Remove everything

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
BACKUP_DIR="${CLAUDE_BACKUP_DIR:-$HOME/Backups/claude-code}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}Warning:${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1"; exit 1; }

install_orphan_killer() {
    info "Installing orphan process killer..."

    # Copy script
    cp "$SCRIPT_DIR/scripts/kill-orphan-claude.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/kill-orphan-claude.sh"

    # Create launch agent
    sed "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
        "$SCRIPT_DIR/launchagents/com.user.kill-orphan-claude.plist" \
        > "$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist"

    # Load launch agent
    launchctl unload "$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist" 2>/dev/null || true
    launchctl load "$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist"

    info "Orphan killer installed (runs every 2 hours)"
}

install_backup() {
    info "Installing conversation backup..."

    # Create backup directory
    mkdir -p "$BACKUP_DIR/projects"

    # Copy script
    cp "$SCRIPT_DIR/scripts/backup-claude-conversations.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/backup-claude-conversations.sh"

    # Create launch agent
    sed "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
        "$SCRIPT_DIR/launchagents/com.user.backup-claude-conversations.plist" \
        > "$LAUNCH_AGENTS_DIR/com.user.backup-claude-conversations.plist"

    # Load launch agent
    launchctl unload "$LAUNCH_AGENTS_DIR/com.user.backup-claude-conversations.plist" 2>/dev/null || true
    launchctl load "$LAUNCH_AGENTS_DIR/com.user.backup-claude-conversations.plist"

    info "Backup installed (runs on login + every 12h)"
    info "Backup location: $BACKUP_DIR"
}

uninstall() {
    info "Uninstalling Claude Code maintenance scripts..."

    # Unload and remove launch agents
    launchctl unload "$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist" 2>/dev/null || true
    launchctl unload "$LAUNCH_AGENTS_DIR/com.user.backup-claude-conversations.plist" 2>/dev/null || true
    rm -f "$LAUNCH_AGENTS_DIR/com.user.kill-orphan-claude.plist"
    rm -f "$LAUNCH_AGENTS_DIR/com.user.backup-claude-conversations.plist"

    # Remove scripts
    rm -f "$INSTALL_DIR/kill-orphan-claude.sh"
    rm -f "$INSTALL_DIR/backup-claude-conversations.sh"

    info "Uninstalled (backup data preserved at $BACKUP_DIR)"
}

# Ensure directories exist
mkdir -p "$INSTALL_DIR"
mkdir -p "$LAUNCH_AGENTS_DIR"

case "${1:-all}" in
    orphan)
        install_orphan_killer
        ;;
    backup)
        install_backup
        ;;
    uninstall)
        uninstall
        ;;
    all|"")
        install_orphan_killer
        install_backup
        ;;
    *)
        echo "Usage: $0 [orphan|backup|uninstall|all]"
        exit 1
        ;;
esac

info "Done!"
echo ""
echo "Useful commands:"
echo "  # Check orphan killer status"
echo "  launchctl list | grep kill-orphan-claude"
echo ""
echo "  # Check backup status"
echo "  launchctl list | grep backup-claude"
echo ""
echo "  # View logs"
echo "  cat /tmp/kill-orphan-claude.log"
echo "  cat /tmp/backup-claude-conversations.log"
echo ""
echo "  # Run manually"
echo "  $INSTALL_DIR/kill-orphan-claude.sh"
echo "  $INSTALL_DIR/backup-claude-conversations.sh"
