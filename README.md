# VScodeconfig

[![test](https://github.com/naif824/VScodeconfig/actions/workflows/test.yml/badge.svg)](https://github.com/naif824/VScodeconfig/actions/workflows/test.yml)

🚀 **Persistent AI coding terminals for VS Code, Cursor, and VS Code-compatible forks.**

VScodeconfig turns your Remote-SSH terminal into a stable workspace:

- one named terminal tab
- one `tmux` session
- one Claude Code or Codex conversation
- automatic restore after editor reloads, SSH disconnects, and server restarts

It works best with **VS Code** and **Cursor**. It should also work with forks that support VS Code-style `tasks.json`, workspace settings, integrated terminals, and OSC terminal titles.

Using this with Claude, Gemini, Codex, or another AI assistant? See
[`LLM.md`](LLM.md) for the agent-focused guide.

## Why This Exists

AI coding sessions are valuable context. Losing the terminal tab usually means losing the visible conversation, even when logs still exist somewhere on disk.

This repo fixes the annoying parts:

- 🧠 **Claude/Codex conversations stay attached to named work sessions**
- 🏷️ **Terminal tabs are named after the project/session**
- 🔁 **Reload VS Code/Cursor and your tabs come back**
- 🔌 **Disconnect SSH and reconnect without losing your workspace**
- 🧯 **Kill/remove a session and it stays removed**
- 🛠️ **Everything is plain shell, tmux, tasks.json, and workspace settings**

## What You Get

Four commands:

```bash
tn myproject      # new tmux session running Claude Code
tnx myproject     # new tmux session running Codex
ta myproject      # attach/switch to an existing session
tk myproject      # kill a session and sync editor restore state
```

When your editor opens over Remote SSH, VScodeconfig generates tasks that reattach every live tmux session as its own terminal tab.

## Quick Start

Run this on the **remote server**, not on your Mac/laptop:

```bash
git clone https://github.com/naif824/VScodeconfig.git
cd VScodeconfig
bash install.sh
```

Then reload your VS Code/Cursor window:

```text
Cmd/Ctrl + Shift + P → Developer: Reload Window
```

If prompted, click **Trust** for the remote workspace.

Create your first persistent session:

```bash
tn demo
```

Close the editor window, reconnect, and the `demo` terminal tab should come back.

## Requirements

- Linux remote server with `/proc`
- `tmux` 3.0+
- `python3`
- `cron`
- `git`
- Claude Code CLI on `PATH` for `tn`
- Codex CLI on `PATH` for `tnx`

The resume mapper uses Linux `/proc/<pid>/...`, so the full Claude/Codex resume behavior is designed for Linux Remote-SSH hosts.

## How It Works

```text
tn / tnx / ta / tk
        │
        ▼
named tmux sessions
        │
        ▼
scripts/sync-state.sh
        │
        ├─ scripts/gen-tasks.sh → ~/.vscode/tasks.json
        └─ tmux-resurrect save  → reboot-safe snapshot
        │
        ▼
VS Code / Cursor runs "Open Primary Sessions" on folder open
        │
        ▼
each tmux session reattaches as its own terminal tab
```

Main pieces:

- `bin/tn` creates a new tmux session and starts `claude --dangerously-skip-permissions`.
- `bin/tnx` creates a new tmux session and starts `codex --yolo`.
- `bin/ta` attaches to a session, or switches clients if already inside tmux.
- `bin/tk` kills a session and syncs editor tasks + tmux-resurrect state.
- `scripts/claude-session-map.sh` maps tmux sessions to Claude/Codex resume commands.
- `scripts/gen-tasks.sh` writes `~/.vscode/tasks.json` from the current tmux session list.
- `scripts/sync-state.sh` is the single sync entrypoint used by commands, hooks, and cron.
- `tmux.conf.snippet` wires tmux hooks, terminal titles, tmux-resurrect, and tmux-continuum.

## Reliability Model

VScodeconfig syncs in three ways:

- ⚡ **Realtime hooks** on `session-created` and `session-closed`
- 🧭 **Command sync** from `tn`, `tnx`, and `tk`
- ⏱️ **Cron fallback** every 5 minutes

`gen-tasks.sh` writes `tasks.json` atomically and clears stale tasks when there are no live tmux sessions, so old tabs do not come back after you intentionally remove them.

`sync-state.sh` also saves tmux-resurrect state when available, so killed sessions do not reappear after reboot from an old resurrect snapshot.

## Tab Naming

VScodeconfig names tabs in two layers:

```bash
printf '\033]0;session-name\007'
```

and:

```tmux
set -g set-titles on
set -g set-titles-string '#S'
set -g allow-rename off
```

That keeps each editor terminal tab named after its tmux session and prevents apps inside tmux from renaming the wrong tab.

## Removing Sessions

Preferred:

```bash
tk myproject
```

That kills the tmux session, regenerates editor tasks, and saves resurrect state.

Also valid:

```bash
exit
```

If `exit` closes the last process/pane in the tmux session, the tmux `session-closed` hook will sync the editor state. If the tab comes back, check whether the session still exists:

```bash
tmux ls
grep myproject ~/.vscode/tasks.json
```

If the name is gone from both, it will not be reopened.

## Installed Layout

```text
~/.local/bin/
  tn
  tnx
  ta
  tk

~/.vscodeconfig/scripts/
  claude-session-map.sh
  gen-tasks.sh
  sync-state.sh

~/.vscode/tasks.json
~/.vscode/settings.json
~/.claude/session-map.json
~/.tmux.conf
```

The installer appends a managed block to `~/.tmux.conf` and installs one cron entry.

## Upgrade

```bash
cd VScodeconfig
git pull
bash install.sh
```

Reload your VS Code/Cursor window afterward.

If old terminal tabs still do not rename, restart tmux once:

```bash
tmux kill-server
```

Then recreate sessions with `tn`, `tnx`, or attach with `ta`.

## Troubleshooting

List live sessions:

```bash
tmux ls
```

Regenerate editor tasks manually:

```bash
bash ~/.vscodeconfig/scripts/sync-state.sh
```

Inspect generated tasks:

```bash
python3 -m json.tool ~/.vscode/tasks.json
```

Check whether a removed session is still scheduled to reopen:

```bash
grep SESSION_NAME ~/.vscode/tasks.json
```

Install tmux plugins from inside tmux:

```text
prefix + I
```

Default tmux prefix is `Ctrl+b`.

## Uninstall

```bash
rm -f ~/.local/bin/{tn,tnx,ta,tk}
rm -rf ~/.vscodeconfig
rm -f ~/.vscode/tasks.json ~/.claude/session-map.json
crontab -l | grep -v -E 'sync-state\.sh|gen-tasks\.sh|claude-session-map\.sh' | crontab -
```

Then remove the managed VScodeconfig block from `~/.tmux.conf`.

## Safety Notes

- No sudo required.
- No secrets are stored by this repo.
- Generated files live in your home directory.
- Workspace VS Code settings are written on the remote server, not your Mac user settings.
- Claude/Codex launch commands are intentionally visible in generated `tasks.json`.

For AI assistants modifying this repo, read [`LLM.md`](LLM.md) before changing
the sync or session lifecycle.

## License

MIT
