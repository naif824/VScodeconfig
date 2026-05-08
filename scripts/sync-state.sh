#!/bin/bash
# Sync VScodeconfig state after tmux session changes.
#
# This regenerates VS Code/Cursor tasks from live tmux sessions and, when
# tmux-resurrect is installed, saves the current resurrect snapshot so removed
# sessions do not come back after a reboot.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESURRECT_SAVE="$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"

bash "$SCRIPT_DIR/gen-tasks.sh"

if [ -x "$RESURRECT_SAVE" ]; then
  bash "$RESURRECT_SAVE" >/dev/null 2>&1 || true
fi
