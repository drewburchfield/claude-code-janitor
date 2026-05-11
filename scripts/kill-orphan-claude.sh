#!/bin/bash
#
# Reap orphaned Claude Code processes on macOS.
#
# A process is killed only if it meets ALL of these:
#   1. PPID == 1                       (reparented to launchd, session gone)
#   2. Env contains CLAUDE_CODE_ENTRYPOINT (Claude Code spawned this, NOT
#                                          Cursor, NOT Claude Desktop, NOT
#                                          any other tool's MCP server)
#   3. At least one fd shows "(revoked)" in lsof (controlling terminal/pipe
#                                          is gone)
#   4. Running ORPHAN_MIN_HOURS+ hours (don't touch fresh sessions)
#
# Plus: the env-var check is repeated immediately before kill -9 to close
# the PID-reuse race window between candidate identification and kill.
#
# The env-var check is the safety floor. Claude Code injects
# CLAUDE_CODE_ENTRYPOINT into every subprocess (subagent, MCP server,
# tool execution). Processes spawned by other tools do NOT have this
# variable, so they are never candidates here. This prevents accidentally
# killing MCP servers that other apps (Cursor, Codex, Claude Desktop)
# are actively using.
#
# Run with DRY_RUN=1 to print what would be killed without killing.
#
# Background: Claude Code does not reliably terminate MCP server child
# processes or subagent processes on session end. They accumulate as
# PPID=1 orphans, each holding ~44MB.

# Intentionally NOT using `set -e`. We want best-effort cleanup; one
# failed lsof or kill should not abort the run. We DO want pipefail so
# that an upstream `ps` failure surfaces in the heartbeat at the end.
set -u
set -o pipefail

# Pin locale so ps/awk output formatting (especially etime) doesn't drift
# under user locale settings.
export LC_ALL=C

MIN_HOURS="${ORPHAN_MIN_HOURS:-6}"
DRY_RUN="${DRY_RUN:-0}"

# Validate the optional whitelist regex up front. A malformed pattern
# would otherwise silently never match, leaving a user who set
# ORPHAN_WHITELIST believing their process is protected when it isn't.
# Bash [[ =~ ]] returns 0 (match), 1 (no match), or 2 (invalid regex).
if [[ -n "${ORPHAN_WHITELIST:-}" ]]; then
  { [[ "validation_probe" =~ $ORPHAN_WHITELIST ]]; } 2>/dev/null
  if (( $? == 2 )); then
    logger "kill-orphan-claude: ORPHAN_WHITELIST regex is invalid; ignoring whitelist for this run"
    unset ORPHAN_WHITELIST
  fi
fi

scanned=0
killed=0
refused=0
ps_failed=0
unparseable_etime=0

# Find PPID=1 processes, then read each one's env block.
candidates=$(ps -Ao pid,ppid,etime= | awk '$2 == 1 { print $1, $3 }')
ps_rc=$?
if (( ps_rc != 0 )); then
  ps_failed=1
fi

while read -r pid etime; do
  [[ -z "$pid" ]] && continue
  scanned=$((scanned + 1))

  # ps eww shows command followed by the process environment. Failure
  # here (kernel proc, exited mid-scan, other-user proc, hardened-runtime
  # env hidden) just skips. Safe failure direction: we never kill what
  # we can't fully verify.
  envline=$(ps eww -o command= -p "$pid" 2>/dev/null) || continue

  # Required marker: spawned by Claude Code CLI.
  [[ "$envline" == *"CLAUDE_CODE_ENTRYPOINT="* ]] || continue

  # Optional whitelist. Match against command only (not env block) to
  # avoid short patterns accidentally matching PATH, PWD, etc.
  cmd_only=$(ps -o command= -p "$pid" 2>/dev/null) || continue
  if [[ -n "${ORPHAN_WHITELIST:-}" && "$cmd_only" =~ $ORPHAN_WHITELIST ]]; then
    continue
  fi

  # Parse etime (MM:SS | HH:MM:SS | D-HH:MM:SS) into hours.
  if [[ "$etime" == *-* ]]; then
    : # has days, definitely eligible
  elif [[ "$etime" =~ ^[0-9]+:[0-9]+$ ]]; then
    continue # MM:SS, less than an hour, skip
  elif [[ "$etime" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
    if (( BASH_REMATCH[1] < MIN_HOURS )); then
      continue
    fi
  else
    # Unknown format. Don't kill (safe direction), but log so we notice
    # if ps output drifts in a future macOS release.
    unparseable_etime=$((unparseable_etime + 1))
    continue
  fi

  # Final safety: lsof must show at least one revoked fd.
  if ! lsof -p "$pid" 2>/dev/null | grep -q "(revoked)"; then
    continue
  fi

  if (( DRY_RUN == 1 )); then
    echo "would kill PID $pid (etime: $etime): $cmd_only"
    continue
  fi

  # Re-verify the env marker immediately before kill to close the
  # PID-reuse race window (could be hundreds of ms since first check).
  recheck=$(ps eww -o command= -p "$pid" 2>/dev/null) || continue
  [[ "$recheck" == *"CLAUDE_CODE_ENTRYPOINT="* ]] || continue

  # Capture stderr so EPERM (the one error that signals "we identified
  # the wrong process") is logged loudly.
  if kill_err=$(kill -9 "$pid" 2>&1); then
    killed=$((killed + 1))
    logger "kill-orphan-claude: killed PID $pid (etime: $etime): $cmd_only"
  elif [[ "$kill_err" == *"Operation not permitted"* ]]; then
    refused=$((refused + 1))
    logger "kill-orphan-claude: REFUSED to kill PID $pid (EPERM, candidate logic let through a process we can't kill): $cmd_only"
  fi
  # ESRCH (process already exited) silently ignored.
done <<< "$candidates"

# Heartbeat: a single line every run so the absence of activity is
# distinguishable from "the script never ran" or "ps broke silently."
hb="kill-orphan-claude: scan complete (scanned=$scanned, killed=$killed, refused=$refused, dry_run=$DRY_RUN"
if (( ps_failed == 1 )); then
  hb="$hb, ps_enumeration_FAILED rc=$ps_rc"
fi
if (( unparseable_etime > 0 )); then
  hb="$hb, unparseable_etime=$unparseable_etime"
fi
hb="$hb)"
logger "$hb"
