#!/bin/bash
# Generates VS Code tasks.json from current tmux sessions.
# Tasks set the terminal tab title and attach to existing tmux sessions.
# They intentionally never create sessions: stale VS Code/Cursor persistent
# terminals can be revived later, and a create fallback would resurrect sessions
# the user already exited or killed.
#
# Writes: $TASKS_FILE (default $HOME/.vscode/tasks.json)

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_FILE="${TASKS_FILE:-$HOME/.vscode/tasks.json}"
LOCK_DIR="${VSCODECONFIG_LOCK_DIR:-$HOME/.vscodeconfig/.sync-lock}"

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
export TASKS_FILE SESSIONS

python3 - <<'PY'
import json, os, shlex, tempfile

tasks_file = os.environ["TASKS_FILE"]
sessions   = [s for s in os.environ["SESSIONS"].strip().split("\n") if s]

tasks, labels = [], []
for name in sessions:
    labels.append(name)
    # The \033 and \007 stay as 4-char sequences in JSON; printf expands them at runtime.
    title = f"\\033]0;{name}\\007"
    q_name = shlex.quote(name)

    # Attach only. Cursor/VS Code may revive old terminal tasks after the tmux
    # session was intentionally exited; this must not recreate deleted sessions.
    cmd = (
        f"printf '{title}'; "
        f"tmux has-session -t ={q_name} 2>/dev/null && "
        f"tmux attach -t ={q_name}"
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
