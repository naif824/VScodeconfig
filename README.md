# VScodeconfig

**One tmux session per VS Code terminal tab — with Claude Code conversations that survive every restart.**

## The problem

If you use Claude Code inside VS Code's integrated terminal, you've probably hit these:

- **VS Code restart wipes your terminals.** Every Claude conversation is gone from view, even though the transcripts are still on disk.
- **Terminal tabs show `bash` or `zsh`**, not the thing you're actually working on.
- **Renaming a tab in tmux leaks to the wrong VS Code tab** because of how OSC title escapes propagate across clients.
- **Server reboots** take down tmux and lose your Claude processes entirely.

## The objective

Make VS Code's terminal behave like a persistent workspace:

1. Every terminal tab = one named tmux session = one Claude Code conversation.
2. Tab titles always match session names, per-tab, no bleed.
3. Close VS Code, reopen it → every tab reattaches automatically.
4. Kill tmux or reboot the machine → tabs cold-start with `claude --resume <conversation-id>` so the conversation continues where it left off.

All driven by three short commands: `tn` (new), `ta` (attach), `tk` (kill).

## Install

> **Upgrading?** Re-run `install.sh`. It refreshes the managed block in
> `~/.tmux.conf`, reloads tmux, and (v1.0.2+) writes workspace VS Code
> settings to `$HOME/.vscode/settings.json` so tab rename + single-click
> focus work over Remote-SSH with no Mac-side intervention (you'll see a
> one-time "Trust this folder" prompt in VS Code).
>
> If existing tmux tabs still don't rename after upgrade, run
> `tmux kill-server` once and start fresh with `tn <name>`.

```bash
git clone https://github.com/naif824/VScodeconfig.git
cd VScodeconfig
bash install.sh
```

Idempotent. No sudo. No user-specific paths — everything resolves from `$HOME` at runtime.

## Usage

```bash
tn myproject     # new tmux session "myproject" with Claude Code running inside
ta myproject     # attach to an existing session (or switch-client if already in tmux)
tk myproject     # kill the session and sync VS Code tasks
```

Open VS Code in any folder and every tmux session opens as a terminal tab automatically — labeled correctly, attached to its Claude conversation. Close VS Code and come back a day later: same tabs, same conversations.

## How it works

```
┌────────────────────┐    ┌──────────────────┐    ┌────────────────────┐
│  tn / ta / tk      │───▶│  tmux server     │───▶│  claude (per pane) │
└────────────────────┘    └──────────────────┘    └────────────────────┘
                                   │                         │
                                   ▼                         ▼
                          ┌──────────────────┐     ┌────────────────────┐
                          │ gen-tasks.sh     │◀────│ session-map.json   │
                          │  (cron + hooks)  │     │ name → {pid,       │
                          └──────────────────┘     │        conv_id}    │
                                   │               └────────────────────┘
                                   ▼
                          ┌──────────────────┐
                          │ ~/.vscode/       │
                          │  tasks.json      │──runOn: folderOpen──▶ reattach all tabs
                          └──────────────────┘
```

- **`claude-session-map.sh`** — walks tmux sessions, finds the direct `claude` child per pane, extracts the conversation ID from `/proc/<pid>/cmdline`, the sessions directory, or `history.jsonl`, and writes `~/.claude/session-map.json`.
- **`gen-tasks.sh`** — reads the map, emits one VS Code task per tmux session. Each task sets the tab title and does `tmux attach OR tmux new-session -s NAME 'claude --resume <id>'`. The fallback is what makes conversations survive a dead tmux server.
- **`.tmux.conf` managed block** — enables `set-titles` (per-client), disables `allow-rename` (prevents the OSC title leak bug), auto-regenerates tasks on session-created/closed, and wires up tmux-resurrect + continuum for cold-boot.
- **Cron** — runs `gen-tasks.sh` every 5 minutes so the tasks file never drifts.

## Requirements

- tmux ≥ 3.0
- python3
- cron
- [Claude Code CLI](https://docs.claude.com/en/docs/claude-code) (`claude` on PATH)
- git (optional — used to install tpm)

## Layout after install

```
~/.vscodeconfig/scripts/
    claude-session-map.sh
    gen-tasks.sh
~/.local/bin/
    tn  ta  tk
~/.vscode/tasks.json         (auto-generated)
~/.claude/session-map.json   (auto-generated)
~/.tmux.conf                 (managed block between VScodeconfig markers)
crontab                      (one entry, 5-min refresh)
```

## Uninstall

```bash
# 1. Remove commands
rm -f ~/.local/bin/{tn,ta,tk}

# 2. Remove worker scripts
rm -rf ~/.vscodeconfig

# 3. Remove managed block from ~/.tmux.conf (between `# --- VScodeconfig:` markers)

# 4. Remove cron line
crontab -l | grep -v 'gen-tasks.sh' | crontab -

# 5. Optional — remove generated files
rm -f ~/.vscode/tasks.json ~/.claude/session-map.json
```

## License

MIT
