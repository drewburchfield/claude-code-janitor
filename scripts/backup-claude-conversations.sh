#!/bin/bash
# Backup Claude Code conversations
#
# Features:
#   - One-way accumulation (only adds, never deletes or overwrites)
#   - Skips if last backup was recent (configurable interval)
#   - Safe to run frequently (quick exit if not needed)
#
# Claude Code stores conversations in ~/.claude/projects/ as JSONL files.
# This script preserves them even if Claude Code clears history.

# Configuration - override with environment variables
BACKUP_DIR="${CLAUDE_BACKUP_DIR:-$HOME/Backups/claude-code}"
SOURCE_DIR="${CLAUDE_SOURCE_DIR:-$HOME/.claude}"
MIN_INTERVAL="${CLAUDE_BACKUP_INTERVAL:-43200}"  # 12 hours in seconds

TIMESTAMP_FILE="$BACKUP_DIR/.last-backup"

# Check if backup is needed
if [[ -f "$TIMESTAMP_FILE" ]]; then
    last_run=$(cat "$TIMESTAMP_FILE")
    now=$(date +%s)
    elapsed=$((now - last_run))

    if (( elapsed < MIN_INTERVAL )); then
        hours_ago=$((elapsed / 3600))
        logger "backup-claude-conversations: Skipped - last backup was ${hours_ago}h ago"
        exit 0
    fi
fi

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR/projects"

# Sync projects (accumulation only - never overwrite existing, never delete)
rsync -av --ignore-existing "$SOURCE_DIR/projects/" "$BACKUP_DIR/projects/"

# Sync history index (can overwrite - it's just metadata)
cp "$SOURCE_DIR/history.jsonl" "$BACKUP_DIR/history.jsonl" 2>/dev/null

# Record timestamp
date +%s > "$TIMESTAMP_FILE"

logger "backup-claude-conversations: Backup completed to $BACKUP_DIR"
