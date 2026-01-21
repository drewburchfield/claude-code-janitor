# Claude Code Maintenance Scripts

> Because Claude Code has trust issues with its own processes and your precious conversations.

macOS utilities to work around ~~features~~ known issues in [Claude Code](https://github.com/anthropics/claude-code):

1. **Orphan Process Killer** - Cleans up zombie processes that haunt your system
2. **Conversation Backup** - For the appropriately paranoid

## The Problems

### 🧟 Orphaned Processes

Claude Code spawns subagents. Subagents are supposed to clean up after themselves. They don't.

When you close a terminal tab, Claude Code processes can become orphans, get adopted by `launchd` (PPID=1), and proceed to consume your CPU and RAM like they're training GPT-5 on your MacBook.

**Real example:** Two zombie processes running for 4 days consumed 200% CPU and 10GB RAM. The user's computer was "randomly lagging." Mystery solved.

**Related issues:**
- [#1935 - MCP servers not properly terminated](https://github.com/anthropics/claude-code/issues/1935) (June 2025, still open)
- [#6594 - Subagent Termination Bug](https://github.com/anthropics/claude-code/issues/6594)
- [#11122 - Multiple CLI processes accumulate](https://github.com/anthropics/claude-code/issues/11122)

### 💨 Vanishing Conversations

Claude Code stores your conversations locally in `~/.claude/projects/`. Lovely.

Claude Code also **silently deletes them after 30 days by default**. Less lovely.

No prompt. No warning. No trash bin. Just... gone. Many users [discovered this the hard way](https://github.com/anthropics/claude-code/issues/4172).

## Before You Install: Fix Your Retention Settings

Open `~/.claude/settings.json` and add:

```json
{
  "cleanupPeriodDays": 99999
}
```

This sets retention to ~274 years. You'll be fine. Probably. Maybe.

**But wait**, you might say, **"99999 days should be enough, right?"**

Sure. Unless:
- A bug resets your settings
- A migration forgets to copy the flag
- The cleanup logic has an edge case
- You accidentally delete settings.json
- Anthropic changes the default behavior
- Mercury is in retrograde

That's why this repo exists. Belt AND suspenders. Trust no one. Not even Claude. *Especially* not Claude.

## Installation

```bash
git clone https://github.com/drewburchfield/claude-code-maintenance.git
cd claude-code-maintenance
./install.sh
```

Or install components separately:

```bash
./install.sh orphan   # Only orphan killer (you live dangerously)
./install.sh backup   # Only backup (you trust process management)
```

## What Gets Installed

| Component | Location | Schedule |
|-----------|----------|----------|
| Orphan killer script | `~/.local/bin/kill-orphan-claude.sh` | Every 2 hours |
| Backup script | `~/.local/bin/backup-claude-conversations.sh` | On login + every 12h |
| Launch agents | `~/Library/LaunchAgents/` | Survives restarts |
| Backups | `~/Backups/claude-code/` | Accumulation-only, forever |

## How It Works

### Orphan Killer

We don't just kill any process named `claude`. We're not monsters. We only kill processes that meet ALL criteria:

1. ✓ Process name is `claude` (CLI only, not Claude.app)
2. ✓ PPID = 1 (orphaned, parent terminal is gone)
3. ✓ Running 6+ hours (gives legitimate subagents time to finish)
4. ✓ File descriptors revoked (literally cannot communicate with anything)

If a process has no parent, no terminal, and has been spinning for 6+ hours, it's not doing useful work. It's just vibing. Expensively.

```bash
# Check for orphans manually
ps -Ao pid,ppid,etime,comm | grep -E "claude$" | awk '$2==1'

# Run killer manually
~/.local/bin/kill-orphan-claude.sh
```

### Conversation Backup

The backup script is aggressively paranoid:

- **Accumulation-only**: Files are only added, never deleted or overwritten
- **Even if Claude deletes the original**: Your backup still has it
- **Even if you accidentally delete the backup**: ...okay you're on your own there

```bash
# Check last backup time
date -r $(cat ~/Backups/claude-code/.last-backup)

# Run backup manually
~/.local/bin/backup-claude-conversations.sh

# Force backup (ignore 12h interval)
rm ~/Backups/claude-code/.last-backup && ~/.local/bin/backup-claude-conversations.sh
```

## Configuration

Environment variables (set in your shell profile):

```bash
# Orphan killer - minimum hours before killing (default: 6)
export ORPHAN_MIN_HOURS=3

# Backup - destination directory (default: ~/Backups/claude-code)
export CLAUDE_BACKUP_DIR="$HOME/Documents/claude-backup"

# Backup - minimum interval in seconds (default: 43200 = 12 hours)
export CLAUDE_BACKUP_INTERVAL=21600  # 6 hours, for the extra paranoid
```

## Logs

```bash
# View orphan killer log
cat /tmp/kill-orphan-claude.log

# View backup log
cat /tmp/backup-claude-conversations.log

# System log entries
log show --predicate 'eventMessage contains "claude"' --last 1h
```

## Uninstall

```bash
./install.sh uninstall
```

This removes scripts and launch agents but **preserves your backups**. Because we're paranoid, remember?

## The Paranoia Checklist

- [x] Set `cleanupPeriodDays: 99999` in settings
- [x] Install backup script (just in case)
- [x] Backup runs on login (catches overnight gaps)
- [x] Backup is accumulation-only (never loses data)
- [x] Install orphan killer (stop the CPU bleeding)
- [x] Scripts survive restarts (launchd)
- [ ] Trust that Claude Code will fix these bugs (optional, not recommended)

## Manual Cleanup

If you need to kill orphans immediately (without waiting for the scheduled run):

```bash
# List orphaned claude processes
ps -Ao pid,ppid,etime,pcpu,pmem,comm | grep -E "claude$" | awk '$2==1'

# Kill all orphans (verify the list first!)
ps -Ao pid,ppid,comm | grep -E "claude$" | awk '$2==1 {print $1}' | xargs kill -9
```

## FAQ

**Q: Isn't 99999 days overkill?**
A: It's 274 years. If you're still using Claude Code in 274 years, you have bigger concerns.

**Q: Why accumulation-only backups?**
A: Because the only thing worse than losing conversations is losing them *twice*.

**Q: Will Anthropic fix these bugs?**
A: The MCP orphan issue has been open since June 2025 with multiple "fixes" that didn't fully fix it. So... maybe? Eventually? Install the scripts.

**Q: Is this repo necessary?**
A: If you've never lost conversations or had zombie processes eat your CPU, congratulations on your good fortune. The rest of us are here.

## License

MIT - Do whatever you want. Back it up first though.
