#!/bin/bash
# Sync VScodeconfig state after tmux session changes.
#
# This regenerates VS Code/Cursor tasks from live tmux sessions and, when
# tmux-resurrect is installed, saves the current resurrect snapshot so removed
# sessions do not come back after a reboot.
#
# GUARD (added 2026-09-10): never save a resurrect snapshot when zero sessions
# remain. On shutdown tmux kills sessions one by one; the final session-closed
# hook used to fire with no sessions left and wrote an EMPTY snapshot over
# "last", so continuum restored nothing on the next boot.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESURRECT_SAVE="$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"

bash "$SCRIPT_DIR/gen-tasks.sh"

session_count="$(tmux list-sessions 2>/dev/null | grep -cvE "^(bootstrap|_boot):")"
if [ "${session_count:-0}" -lt 1 ]; then
  exit 0
fi

if [ -x "$RESURRECT_SAVE" ]; then
  bash "$RESURRECT_SAVE" >/dev/null 2>&1 || true
fi

# Rewrite the snapshot so each agent pane carries its live conversation id,
# otherwise a restored pane relaunches the tool with an empty session.
python3 "$SCRIPT_DIR/inject-agent-sessions.py" >/dev/null 2>&1 || true
