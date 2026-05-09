# LLM Guide

This file is written for AI assistants and power users working inside a VS Code,
Cursor, or VS Code-compatible Remote-SSH terminal.

Use it when you need to understand, install, debug, or safely modify
VScodeconfig without reading the whole repo first.

## What This Repo Does

VScodeconfig makes remote AI coding terminals persistent.

It maps:

```text
editor terminal tab → tmux session → Claude/Gemini/Codex-style coding task
```

The current implementation has first-class commands for:

- Claude Code via `tn <name>`
- Codex via `tnx <name>`

Gemini users can still use the tmux/session/task workflow today by creating or
attaching named tmux sessions manually, or by adapting the command launched by a
session. If you add a dedicated Gemini command later, follow the `tn`/`tnx`
pattern and keep the same sync behavior.

## User-Facing Commands

```bash
tn name    # create a tmux session and start Claude Code
tnx name   # create a tmux session and start Codex
ta name    # attach/switch to an existing tmux session
tk name    # kill a tmux session and sync generated state
tclean     # inspect old pre-v1.2.1 editor task shells, dry-run by default
```

Session names must not be empty and must not start with `-`.

## Important Files

```text
bin/tn                         # new Claude session
bin/tnx                        # new Codex session
bin/ta                         # attach/switch session
bin/tk                         # kill session and sync state
bin/tclean                     # inspect/kill stale old editor task shells
scripts/gen-tasks.sh           # writes ~/.vscode/tasks.json
scripts/clean-stuck-terminals.sh # detects old attach-or-create task shells
scripts/sync-state.sh          # shared sync entrypoint
tmux.conf.snippet              # tmux hooks, titles, resurrect/continuum
install.sh                     # idempotent installer
README.md                      # public human-facing docs
```

Generated user files:

```text
~/.vscode/tasks.json
~/.vscode/settings.json
~/.tmux.conf
~/.tmux/resurrect/
```

## Sync Model

All state should flow through:

```bash
bash ~/.vscodeconfig/scripts/sync-state.sh
```

That script:

1. Regenerates `~/.vscode/tasks.json` from live tmux sessions.
2. Saves tmux-resurrect state when tmux-resurrect is installed.

The sync path is triggered by:

- `tn`
- `tnx`
- `tk`
- tmux `session-created` hook
- tmux `session-closed` hook
- cron every 5 minutes

Do not add new code paths that update only `tasks.json` and skip
`sync-state.sh`, unless there is a specific reason.

Generated `tasks.json` tasks must be **attach-only**. They may check
`tmux has-session` and attach, but they must not run `tmux new-session`.
Cursor/VS Code can revive old persistent task terminals after a user has
properly exited a tmux session; a create fallback would bring deleted sessions
back.

## Troubleshooting Checklist

List live tmux sessions:

```bash
tmux ls
```

Regenerate all editor restore state:

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

Check for old Cursor/VS Code pty task shells that still contain `tmux attach ... || tmux new-session ...`:

```bash
tclean
```

If a session comes back after reboot, inspect tmux-resurrect:

```bash
grep -R SESSION_NAME ~/.tmux/resurrect 2>/dev/null
```

## Safe Behavior Rules For AI Assistants

- Prefer `tk <name>` over raw `tmux kill-session -t <name>`.
- After any manual tmux session change, run `sync-state.sh`.
- If fresh sessions appear after a repo upgrade, run `tclean` and inspect old pre-v1.2.1 editor task shells before changing tmux logic.
- Never edit `~/.vscode/tasks.json` directly as the primary fix; regenerate it.
- Never hardcode a user's home path, hostname, token, API key, or personal
  machine details into repo files.
- Keep startup commands configurable or clearly documented when adding new
  agents.
- Preserve the invariant: generated tasks reflect live tmux sessions.
- Preserve the invariant: only `tn`/`tnx` create sessions; generated editor
  tasks only attach.

## Adding Another Agent Command

To add a command for another agent, copy the shape of `bin/tnx`:

1. Validate the session name.
2. Refuse if the tmux session already exists.
3. Create the tmux session detached.
4. Send the agent startup command into the session.
5. Run `sync-state.sh` in the background.
6. Emit the OSC title escape.
7. Attach to the tmux session.

For example, a future Gemini command should use the same lifecycle and only
change the agent startup command.

## Testing

Run:

```bash
tests/run-tests.sh
```

Run shell syntax checks:

```bash
for file in install.sh bin/* scripts/*.sh tests/*.sh; do
  bash -n "$file"
done
```

Before claiming a fix works, verify both commands.
