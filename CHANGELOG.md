# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
