[![Claude Code Janitor](https://ghrb.waren.build/banner?header=Claude+Code+Janitor+%21%5Bclaude%5D&subheader=Sweep+up+orphaned+Claude+Code+processes&bg=1A1A1A-D97757&color=FFFFFF&headerfont=Inter&subheaderfont=Inter&support=false)](https://github.com/drewburchfield/claude-code-janitor)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) [![Platform: macOS](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos) [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/drewburchfield/claude-code-janitor)

A small macOS launchd-scheduled script that reaps orphaned Claude Code processes: the CLI itself, its subagents, and any MCP servers it spawned that didn't shut down cleanly. Safe to run alongside Claude Desktop, Cursor, Codex, and other tools that spawn MCP servers.

Built by a Claude Code user who got tired of finding 13 zombie MCP processes hogging memory after closing a terminal tab. If you run Claude Code regularly and notice your fans spinning hours after you stopped using it, this is for you.

## What It Does

Claude Code spawns subagents and MCP server processes. When you close a terminal tab or a session crashes, those children get reparented to `launchd` (PPID=1) and keep running. In our measurements each one held roughly 44 MB, varying with which MCP servers you use. Multiply by a few days of heavy use and you have a real memory leak.

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

The env var check is the key safety floor. Claude Code injects `CLAUDE_CODE_ENTRYPOINT` into every subprocess it spawns (subagents, MCP servers, tool executions). Claude Desktop, Cursor, Codex, and other MCP-using tools do not set this variable as of May 2026. If Claude Desktop's behavior ever changes upstream and it begins setting `CLAUDE_CODE_ENTRYPOINT`, this assumption breaks and the script could start matching Desktop's MCP children. Re-verify before relying on this with new releases of Claude Desktop.

The script also re-verifies the env marker immediately before sending `kill -9`, to close the small PID-reuse race window between candidate identification and the kill itself.

## Configuration

Set these environment variables in your shell profile to tune behavior. All are optional.

| Variable | Default | What it controls |
|----------|---------|------------------|
| `ORPHAN_MIN_HOURS` | `6` | Minimum runtime before a process is eligible. Lower this if you start many short sessions and want faster cleanup. |
| `ORPHAN_WHITELIST` | (none) | Regex matched against the process command line only (not env). Matches are never killed, even if otherwise eligible. Use to protect a specific Claude-spawned process you intentionally keep running. |
| `DRY_RUN` | `0` | Set to `1` to print what would be killed without killing. Same code path as a real run, so the preview never drifts from actual behavior. |

Example: faster cleanup for short-session workflows.

```bash
export ORPHAN_MIN_HOURS=1
```

## Compatibility

- macOS (Apple Silicon and Intel)
- Bash 3.2+ (the version that ships with macOS)
- Claude Code CLI installed via npm, brew, or the official installer

Not tested on Linux. Likely porting concerns: the `etime` field formatting from `ps` (locale-sensitive on some distros), the BSD-specific `(revoked)` string in `lsof` output (Linux `lsof` reports closed terminals differently), and the default destination of `logger` (syslog vs. journald).

## Troubleshooting

**Verify the launch agent is loaded:**

```bash
launchctl list | grep kill-orphan-claude
```

**Check what the last run did:**

```bash
log show --predicate 'eventMessage contains "kill-orphan-claude"' --last 1d
```

Every run emits a single heartbeat line at the end with `scanned`, `killed`, and `refused` counts. If you see the heartbeat but `killed=0` for days while you know orphans exist, jump to the next section.

**Suspect the script is running but not finding orphans:**

The detection relies on `ps eww -o command=` showing the environment block of each candidate process. On stricter macOS configurations (hardened runtime, certain code-signing states, or processes owned by another user), `ps` can return the command line without the env, and the script will silently treat those processes as not Claude orphans. To check whether this is happening:

```bash
# Pick any PPID=1 process you suspect is a Claude orphan
ps eww -o command= -p <pid> | tr ' ' '\n' | grep -E "^CLAUDE_|^ANTHROPIC"
```

If that returns nothing for a process you know was spawned by Claude Code, `ps` cannot read its environment from your shell context. The script will not be able to identify it as an orphan either.

**See what the script would kill right now without killing anything:**

```bash
DRY_RUN=1 ~/.local/bin/kill-orphan-claude.sh
```

This applies the same four safety checks as a real run and prints what would have been killed. Always matches actual behavior because it's the same script.

**Run manually:**

```bash
~/.local/bin/kill-orphan-claude.sh
```

**Heard `EPERM` in the logs?**

The script logs `REFUSED to kill PID X (EPERM, candidate logic let through a process we can't kill)` if `kill -9` ever returns "Operation not permitted." This should never happen for a process you own. If you see it, something let a non-Drew, non-Claude process through the candidate logic. Open an issue with the log line.

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
- [#33947](https://github.com/anthropics/claude-code/issues/33947) MCP server and subagent processes not cleaned up on session end, observed PPID=1 accumulation on macOS (a heavy user reports ~107 unsigned node processes orphaned in a single workday)
- [#40667](https://github.com/anthropics/claude-code/issues/40667) MCP server processes leak on host after subagent/session termination

Per-orphan memory varies with which MCP servers you use. In our measurements ~44 MB is typical.

## Development

The project is two files plus a launchd plist:

```
scripts/kill-orphan-claude.sh                   # The reaper
launchagents/com.user.kill-orphan-claude.plist  # Runs it every 2 hours
install.sh                                      # Copies them into place
```

To test changes:

```bash
# Edit scripts/kill-orphan-claude.sh
DRY_RUN=1 bash scripts/kill-orphan-claude.sh    # Preview without killing
./install.sh                                    # Reinstall and reload the agent
```

## License

MIT
