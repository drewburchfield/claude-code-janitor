# Claude Code Janitor

A tiny macOS launchd-scheduled script that reaps orphaned Claude Code processes and their MCP server children. Safe to run alongside Claude Desktop, Cursor, Codex, and other tools that spawn MCP servers.

Built by a Claude Code user who got tired of finding 13 zombie MCP processes hogging memory after closing a terminal tab. If you run Claude Code regularly and notice your fans spinning hours after you stopped using it, this is for you.

## What It Does

Claude Code spawns subagents and MCP server processes. When you close a terminal tab or a session crashes, those children get reparented to `launchd` (PPID=1) and keep running. Each one holds roughly 44 MB. Multiply by a few days of heavy use and you have a real memory leak.

This script runs every 2 hours, finds those orphans, and kills them. It will not touch:

- Active Claude Code sessions you are currently running
- Processes spawned by Claude Desktop, Cursor, Codex, or any other tool
- Anything that still has a live terminal or pipe attached

It uses four overlapping safety checks (detailed below) so it only kills processes that are 100% orphans of Claude Code specifically.

## Quick Start

```bash
git clone https://github.com/drewburchfield/claude-code-janitor.git
cd claude-code-janitor
./install.sh
```

That copies the script to `~/.local/bin/`, installs a launchd agent that runs every 2 hours, and starts it immediately.

To remove later:

```bash
./install.sh uninstall
```

## How It Works

A process is killed only if it meets all four of these:

| Check | What it confirms |
|-------|------------------|
| `PPID == 1` | The original session is gone. On macOS, `launchd` is PID 1 and adopts orphaned processes. |
| `CLAUDE_CODE_ENTRYPOINT` in env | The process was spawned by Claude Code CLI, not Claude Desktop or any other tool. |
| At least one fd shows `(revoked)` in `lsof` | The controlling terminal or pipe is gone. |
| Running `ORPHAN_MIN_HOURS`+ hours (default 6) | Don't touch processes from sessions that just started. |

The env var check is the key safety floor. Claude Code injects `CLAUDE_CODE_ENTRYPOINT` into every subprocess it spawns (subagents, MCP servers, tool executions). Claude Desktop and other MCP-using tools don't set this variable today, so their processes are never candidates here. The script also re-verifies this env marker immediately before sending `kill -9`, to close the small PID-reuse race window between candidate identification and the kill itself.

## Configuration

Set these environment variables in your shell profile to tune behavior. All are optional.

| Variable | Default | What it controls |
|----------|---------|------------------|
| `ORPHAN_MIN_HOURS` | `6` | Minimum runtime before a process is eligible. Lower this if you start many short sessions and want faster cleanup. |
| `ORPHAN_WHITELIST` | (none) | Regex against the process command line. Matches are never killed, even if otherwise eligible. Use to protect a specific Claude-spawned process you intentionally keep running. |

Example: faster cleanup for short-session workflows.

```bash
export ORPHAN_MIN_HOURS=1
```

## Compatibility

- macOS (Apple Silicon and Intel)
- Bash 3.2+ (the version that ships with macOS)
- Claude Code CLI installed via npm, brew, or the official installer

Not tested on Linux. The detection relies on `ps eww -o command=` showing process environment, which behaves differently on Linux.

## Troubleshooting

**Verify the launch agent is loaded:**

```bash
launchctl list | grep kill-orphan-claude
```

**Check what the last run did:**

```bash
log show --predicate 'eventMessage contains "kill-orphan-claude"' --last 1d
```

**See what the script would kill right now without killing anything:**

```bash
DRY_RUN=1 ~/.local/bin/kill-orphan-claude.sh
```

This applies the same four safety checks as a real run and prints what would have been killed. Always matches actual behavior because it's the same script.

**Run manually:**

```bash
~/.local/bin/kill-orphan-claude.sh
```

## Manual Cleanup

If you want to reap right now without waiting for the scheduled run:

```bash
# Preview first
DRY_RUN=1 ~/.local/bin/kill-orphan-claude.sh

# Then actually kill
~/.local/bin/kill-orphan-claude.sh
```

## Background

The orphaned process problem in Claude Code has been tracked across several upstream issues:

- [#22612](https://github.com/anthropics/claude-code/issues/22612) MCP servers not cleaned up when sessions end
- [#33947](https://github.com/anthropics/claude-code/issues/33947) MCP server and subagent processes not cleaned up on session end, observed PPID=1 accumulation on macOS
- [#40667](https://github.com/anthropics/claude-code/issues/40667) MCP server processes leak on host after subagent/session termination

Each orphan holds roughly 44 MB. Heavy users report accumulating 100+ orphans within a workday.

## Development

The project is two files plus a launchd plist:

```
scripts/kill-orphan-claude.sh          # The reaper
launchagents/com.user.kill-orphan-claude.plist  # Runs it every 2 hours
install.sh                              # Copies them into place
```

To test changes:

```bash
# Edit scripts/kill-orphan-claude.sh
./install.sh                            # Reinstalls and reloads the agent
~/.local/bin/kill-orphan-claude.sh      # Run it once manually
```

## License

MIT
