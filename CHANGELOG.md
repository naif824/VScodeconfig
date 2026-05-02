# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.1] - 2026-05-02

### Fixed
- `tn` and `tnx` now reject session names starting with `-` so a stray
  `tnx --help` doesn't create a tmux session literally named `--help`.

## [1.1.0] - 2026-05-02

### Added
- `tnx <name>` — new command. Same flow as `tn` but launches `codex --yolo`
  inside the tmux session instead of `claude`.
- Per-session agent detection in `claude-session-map.sh`. Each map entry now
  includes an `agent` field (`claude` or `codex`) and a ready-to-run
  `resume_cmd`. Codex sessions are matched by their direct `codex` child
  process; the rollout UUID is recovered from `/proc/<pid>/fd/` so cold-start
  resumes via `codex resume <id> --yolo`.
- `gen-tasks.sh` now uses each entry's `resume_cmd`, so codex tabs cold-start
  with `codex resume <id> --yolo` and claude tabs are unchanged.

### Notes
- `ta` and `tk` are agent-agnostic and work for codex sessions too.

## [1.0.2] - 2026-04-24

### Added
- `install.sh` now writes workspace VS Code settings to
  `$HOME/.vscode/settings.json` so Remote-SSH clients get correct tab
  behavior without touching the Mac's User settings. Managed keys:
  - `terminal.integrated.tabs.title = "${sequence}"` (honor OSC titles)
  - `terminal.integrated.tabs.description`
  - `terminal.integrated.tabs.enabled = true`
  - `terminal.integrated.tabs.focusMode = "singleClick"` (auto-focus on
    single click between terminal tabs)
  Existing keys in `settings.json` are preserved.

### Notes
- First time the Mac user opens the workspace after this update, VS Code
  will prompt once to **Trust** the folder. Click Trust.
- One setting cannot be delivered server-side because it's
  application-scoped: `terminal.integrated.enablePersistentSessions`.
  It's optional polish (prevents VS Code from resurrecting ghost cached
  terminals over real tmux tabs on window reload). Set to `false` in
  Mac User settings if you want it.

## [1.0.1] - 2026-04-24

### Fixed
- `tn <name>` now renames the terminal tab immediately. `bin/tn` emits the
  OSC title escape (`\033]0;<name>\007`) before `tmux attach`, so the rename
  works even on clients where tmux's `set-titles` hasn't been (re)loaded.
- `ta <name>` emits the same escape before attach/switch, keeping the tab
  label correct when moving between sessions.
- `install.sh` now **upgrades** the managed block in `~/.tmux.conf` on
  re-run instead of silently leaving a stale block in place. Also reloads
  tmux via `source-file` so changes take effect without `kill-server`.

### Notes
- If you installed v1.0.0 before this release and your tab titles aren't
  updating, re-run `install.sh` and either `tmux kill-server` once or
  detach/re-attach your existing sessions.

## [1.0.0] - 2026-04-23

### Added
- Initial release: tmux <-> VS Code tab integration with Claude Code
  session resume (`tn`, `ta`, `tk`, auto-generated `tasks.json`,
  session-map with conversation IDs, cron refresh, tpm plugins).
