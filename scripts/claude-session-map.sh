#!/bin/bash
# Maps tmux sessions -> Claude Code conversation IDs.
# Output: $HOME/.claude/session-map.json
#
# Fixes vs. original:
#  - Narrow process match: pgrep -P <pane_pid> -x claude  (exact, direct child only)
#  - Atomic temp file via mktemp (no cross-run race on a fixed .tmp path)
#  - JSON escaping via python (robust for any session name)

set -u
MAP_FILE="$HOME/.claude/session-map.json"
SESSIONS_DIR="$HOME/.claude/sessions"
HISTORY="$HOME/.claude/history.jsonl"
PROJECTS_DIR="$HOME/.claude/projects"

mkdir -p "$(dirname "$MAP_FILE")"
TMP="$(mktemp "${MAP_FILE}.XXXXXX")"

export SESSIONS_DIR HISTORY PROJECTS_DIR TMP

python3 - <<'PY'
import json, os, re, subprocess, sys

tmp_file    = os.environ["TMP"]
sess_dir    = os.environ["SESSIONS_DIR"]
history     = os.environ["HISTORY"]
projects    = os.environ["PROJECTS_DIR"]

UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=False).stdout
    except FileNotFoundError:
        return ""

def list_sessions():
    out = run(["tmux", "list-sessions", "-F", "#{session_name}"])
    return sorted([s for s in out.strip().split("\n") if s])

def pane_pid(name):
    out = run(["tmux", "list-panes", "-t", name, "-F", "#{pane_pid}"])
    line = out.strip().split("\n")[0] if out.strip() else ""
    return line or None

def child_claude(pid):
    # Exact-name, direct-child-only — no false matches on claude-mem, etc.
    out = run(["pgrep", "-P", str(pid), "-x", "claude"])
    line = out.strip().split("\n")[0] if out.strip() else ""
    return line or None

def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().decode(errors="replace").split("\x00")
    except Exception:
        return []

def conv_from_cmdline(pid):
    args = cmdline(pid)
    if "--resume" in args:
        i = args.index("--resume")
        if i + 1 < len(args) and UUID_RE.match(args[i+1] or ""):
            return args[i+1]
    return None

def session_file(claude_pid):
    f = os.path.join(sess_dir, f"{claude_pid}.json")
    if not os.path.isfile(f):
        return None, 0
    try:
        data = json.load(open(f))
        return data.get("sessionId"), data.get("startedAt", 0)
    except Exception:
        return None, 0

def jsonl_exists(sid):
    if not sid or not os.path.isdir(projects):
        return False
    for d in os.listdir(projects):
        if os.path.isfile(os.path.join(projects, d, f"{sid}.jsonl")):
            return True
    return False

def conv_from_history(started_at):
    if not started_at or not os.path.isfile(history):
        return None
    best_id, best_ts = None, 0
    try:
        with open(history) as f:
            for line in f:
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                ts  = e.get("timestamp", 0)
                sid = e.get("sessionId", "")
                if ts >= started_at and ts > best_ts and sid:
                    best_id, best_ts = sid, ts
    except Exception:
        return None
    return best_id

result = {}
for name in list_sessions():
    entry = {"pid": None, "conversation_id": None, "resume_cmd": None}
    ppid = pane_pid(name)
    if ppid:
        cp = child_claude(ppid)
        if cp:
            entry["pid"] = int(cp)
            conv = conv_from_cmdline(cp)
            if not conv:
                sid, started = session_file(cp)
                if sid and jsonl_exists(sid):
                    conv = sid
                elif started:
                    conv = conv_from_history(started)
            if conv:
                entry["conversation_id"] = conv
                entry["resume_cmd"] = f"claude --dangerously-skip-permissions --resume {conv}"
    result[name] = entry

with open(tmp_file, "w") as f:
    json.dump(result, f, indent=2)
PY

mv "$TMP" "$MAP_FILE"
