#!/bin/bash
# Generates VS Code tasks.json from current tmux sessions.
# Tasks set the terminal tab title, attach to the tmux session, and
# — if the tmux server is dead — fall back to `claude --resume <id>`
# using the conversation ID from session-map.json so conversations survive a reboot.
#
# Writes: $TASKS_FILE (default $HOME/.vscode/tasks.json)

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_FILE="${TASKS_FILE:-$HOME/.vscode/tasks.json}"
MAP_FILE="$HOME/.claude/session-map.json"
LOCK_DIR="${VSCODECONFIG_LOCK_DIR:-$HOME/.vscodeconfig/.sync-lock}"

# Refresh the session map first
bash "$SCRIPT_DIR/claude-session-map.sh" >/dev/null 2>&1 || true

mkdir -p "$(dirname "$LOCK_DIR")"
if mkdir "$LOCK_DIR" 2>/dev/null; then
  trap 'rmdir "$LOCK_DIR"' EXIT
else
  echo "Another VScodeconfig sync is running"
  exit 0
fi

mkdir -p "$(dirname "$TASKS_FILE")"

SESSIONS="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
if [ -z "$SESSIONS" ]; then
  SESSION_COUNT=0
else
  SESSION_COUNT="$(printf '%s\n' "$SESSIONS" | wc -l | tr -d ' ')"
fi
export TASKS_FILE MAP_FILE SESSIONS

python3 - <<'PY'
import json, os, shlex, tempfile

tasks_file = os.environ["TASKS_FILE"]
map_file   = os.environ["MAP_FILE"]
sessions   = [s for s in os.environ["SESSIONS"].strip().split("\n") if s]

try:
    smap = json.load(open(map_file))
except Exception:
    smap = {}

tasks, labels = [], []
for name in sessions:
    labels.append(name)
    entry = smap.get(name, {}) or {}

    # The \033 and \007 stay as 4-char sequences in JSON; printf expands them at runtime.
    title = f"\\033]0;{name}\\007"
    q_name = shlex.quote(name)
    fallback = entry.get("resume_cmd") or "claude --dangerously-skip-permissions"
    q_fb = shlex.quote(fallback)

    # Attach if tmux session exists; otherwise cold-start a new tmux session running the fallback.
    cmd = (
        f"printf '{title}'; "
        f"tmux attach -t {q_name} 2>/dev/null || "
        f"tmux new-session -s {q_name} {q_fb}"
    )

    tasks.append({
        "label": name,
        "type": "shell",
        "command": cmd,
        "isBackground": True,
        "problemMatcher": [],
        "presentation": {"reveal": "silent", "panel": "dedicated"},
    })

if labels:
    tasks.append({
        "label": "Open Primary Sessions",
        "dependsOn": labels,
        "dependsOrder": "parallel",
        "runOptions": {"runOn": "folderOpen"},
        "problemMatcher": [],
    })

doc = {"version": "2.0.0", "tasks": tasks}
directory = os.path.dirname(tasks_file) or "."
fd, tmp = tempfile.mkstemp(prefix=".tasks.", suffix=".json", dir=directory)
with os.fdopen(fd, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
os.replace(tmp, tasks_file)
PY

echo "Generated $TASKS_FILE with $SESSION_COUNT sessions"
