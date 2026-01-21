#!/bin/bash
# Kill orphaned Claude Code processes
#
# Targets processes that are:
#   1. Named "claude" (CLI only, not Claude.app)
#   2. Orphaned (PPID=1, parent terminal is gone)
#   3. Running 6+ hours (configurable below)
#   4. Have revoked stdin/stdout (no terminal connection)
#
# Related issues:
#   - https://github.com/anthropics/claude-code/issues/1935
#   - https://github.com/anthropics/claude-code/issues/6594
#   - https://github.com/anthropics/claude-code/issues/11122

MIN_HOURS=${ORPHAN_MIN_HOURS:-6}

ps -Ao pid,ppid,etime,comm | grep -E "claude$" | awk '$2==1 {print $1, $3}' | while read pid etime; do
    # Parse elapsed time
    # Formats: MM:SS, HH:MM:SS, or D-HH:MM:SS
    hours=0

    if [[ "$etime" == *-* ]]; then
        # Has days component - definitely over threshold
        hours=999
    elif [[ "$etime" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
        # HH:MM:SS format
        hours=${BASH_REMATCH[1]}
    fi
    # MM:SS format means < 1 hour, skip

    if (( hours >= MIN_HOURS )); then
        # Verify stdin/stdout are revoked (no terminal connection)
        if lsof -p "$pid" 2>/dev/null | grep -q "(revoked)"; then
            kill -9 "$pid" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                logger "kill-orphan-claude: Killed orphaned process $pid (runtime: $etime)"
            fi
        fi
    fi
done
