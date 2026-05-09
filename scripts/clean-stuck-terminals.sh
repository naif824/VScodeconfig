#!/bin/bash
# Detect and optionally kill stale VS Code/Cursor pty task shells that still run
# the old pre-v1.2.1 command shape: tmux attach ... || tmux new-session ...
# Default is dry-run. Use --kill to terminate matching wrapper shells.

set -euo pipefail

MODE="dry-run"
if [ "${1:-}" = "--kill" ]; then
  MODE="kill"
  shift
elif [ "${1:-}" = "--dry-run" ]; then
  shift
elif [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'EOF'
Usage: tclean [--dry-run|--kill]

Find old Cursor/VS Code persistent terminal task shells that still contain the
obsolete fallback command:

  tmux attach ... || tmux new-session ...

Default: dry-run, only prints matches.
--kill: terminate only the matching obsolete wrapper shell processes, then sync.
EOF
  exit 0
elif [ $# -gt 0 ]; then
  echo "Usage: tclean [--dry-run|--kill]" >&2
  exit 2
fi

PS_INPUT="${VSCODECONFIG_PS_FILE:-}"

list_matches() {
  if [ -n "$PS_INPUT" ]; then
    cat "$PS_INPUT"
  else
    ps -eo pid=,ppid=,args=
  fi | python3 -c '
import re
import sys

lines = sys.stdin.read().splitlines()
procs = {}
for line in lines:
    parts = line.strip().split(None, 2)
    if len(parts) < 3:
        continue
    try:
        pid = int(parts[0])
        ppid = int(parts[1])
    except ValueError:
        continue
    procs[pid] = (ppid, parts[2])

pty_markers = (".cursor-server", ".vscode-server", "cursor-server", "ptyHost")
pattern = re.compile(r"tmux attach\b.*\|\|.*tmux new-session\b")
name_re = re.compile(r"tmux new-session -s ([^\s;]+)")

def has_editor_pty_ancestor(pid):
    seen = set()
    cur = pid
    while cur in procs and cur not in seen:
        seen.add(cur)
        ppid, args = procs[cur]
        if any(marker in args for marker in pty_markers):
            return True
        cur = ppid
    return False

for pid, (ppid, args) in sorted(procs.items()):
    if "clean-stuck-terminals" in args or "VSCODECONFIG_PS_FILE" in args:
        continue
    if "/bin/bash -c" not in args and "bash -c" not in args:
        continue
    if not pattern.search(args):
        continue
    if not has_editor_pty_ancestor(pid):
        continue
    name = "?"
    match = name_re.search(args)
    if match:
        name = match.group(1).strip("\047\042")
    print(f"{pid}\t{ppid}\t{name}\t{args}")
'
}

matches="$(list_matches)"
if [ -z "$matches" ]; then
  echo "No stale pre-v1.2.1 editor task shells found."
  exit 0
fi

printf '%s\n' "PID PPID SESSION COMMAND"
printf '%s\n' "$matches" | awk -F '\t' '{printf "%s %s %s %s\n", $1, $2, $3, $4}'

if [ "$MODE" = "dry-run" ]; then
  echo "Dry run only. Use: tclean --kill"
  exit 0
fi

printf '%s\n' "$matches" | awk -F '\t' '{print $1}' | while read -r pid; do
  case "$pid" in
    ''|*[!0-9]*) continue ;;
  esac
  kill "$pid" 2>/dev/null || true
done

SCRIPTS="${VSCODECONFIG_SCRIPTS_DIR:-$HOME/.vscodeconfig/scripts}"
if [ -x "$SCRIPTS/sync-state.sh" ]; then
  bash "$SCRIPTS/sync-state.sh" >/dev/null 2>&1 || true
fi

echo "Killed stale pre-v1.2.1 editor task shells and synced state."
