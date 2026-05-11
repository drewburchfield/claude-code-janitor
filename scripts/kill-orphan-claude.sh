#!/bin/bash
#
# Reap orphaned Claude Code processes on macOS.
#
# A process is killed only if it meets ALL of these:
#   1. PPID == 1                       (reparented to launchd, session gone)
#   2. Env contains CLAUDE_CODE_ENTRYPOINT (Claude Code spawned this — NOT
#                                          Cursor, NOT Claude Desktop, NOT
#                                          any other tool's MCP server)
#   3. Terminal fds are "(revoked)"    (no live terminal connection)
#   4. Running ORPHAN_MIN_HOURS+ hours (don't touch fresh sessions)
#
# The env-var check is the safety floor. Claude Code injects
# CLAUDE_CODE_ENTRYPOINT into every subprocess (subagent, MCP server,
# tool execution). Processes spawned by other tools do NOT have this
# variable, so they are never candidates here. This prevents accidentally
# killing MCP servers that other apps (Cursor, Codex, Claude Desktop)
# are actively using.
#
# Background: Claude Code does not reliably terminate MCP server child
# processes or subagent processes on session end. They accumulate as
# PPID=1 orphans, each holding ~44MB.
#   https://github.com/anthropics/claude-code/issues/22612
#   https://github.com/anthropics/claude-code/issues/33947
#   https://github.com/anthropics/claude-code/issues/40667

set -u

# Minimum runtime in hours before a candidate is eligible. Set lower
# (e.g. 1) for faster cleanup if you start many short sessions.
MIN_HOURS="${ORPHAN_MIN_HOURS:-6}"

# Whitelist: never kill a PID whose command matches this regex, even if
# it's tagged as a Claude Code orphan. Use to protect any background
# Claude-spawned process you intentionally keep running.
WHITELIST="${ORPHAN_WHITELIST:-__never_match_anything__}"

# Find PPID=1 processes, then read each one's environment block to check
# for the CLAUDE_CODE_ENTRYPOINT marker. `ps eww` shows env on macOS.
ps -Ao pid,ppid,etime= | awk '$2 == 1 { print $1, $3 }' | \
while read -r pid etime; do
  # Skip self-readable env failures (kernel processes, other users, etc.)
  envline=$(ps eww -o command= -p "$pid" 2>/dev/null) || continue

  # Hard requirement: must be a Claude Code-spawned process.
  [[ "$envline" == *"CLAUDE_CODE_ENTRYPOINT="* ]] || continue

  # Whitelist check.
  if [[ "$envline" =~ $WHITELIST ]]; then
    continue
  fi

  # Parse etime (MM:SS | HH:MM:SS | D-HH:MM:SS) into hours.
  hours=0
  if [[ "$etime" == *-* ]]; then
    hours=999
  elif [[ "$etime" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
    hours=${BASH_REMATCH[1]}
  fi

  if (( hours < MIN_HOURS )); then
    continue
  fi

  # Final safety: only kill if terminal fds are revoked (truly detached).
  if lsof -p "$pid" 2>/dev/null | grep -q "(revoked)"; then
    if kill -9 "$pid" 2>/dev/null; then
      # Strip env block from logged command line; just keep the args.
      cmd=$(echo "$envline" | awk '{
        for (i = 1; i <= NF; i++) {
          if ($i !~ /=/) { for (j = i; j <= NF; j++) printf "%s ", $j; exit }
        }
      }')
      logger "kill-orphan-claude: killed PID $pid (etime: $etime): $cmd"
    fi
  fi
done
