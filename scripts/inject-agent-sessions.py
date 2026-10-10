#!/usr/bin/env python3
"""
Inject live agent session IDs into the tmux-resurrect snapshot.

tmux-resurrect saves each pane's command line verbatim, e.g.
    kilo -m deepseek/deepseek-v4-pro
so after a reboot the agent relaunches with NO conversation. This script
rewrites those command lines to carry the pane's current session id, e.g.
    kilo -m deepseek/deepseek-v4-pro -s ses_<session-id>
so tmux-continuum's normal restore brings the conversation back too.

Runs after every resurrect save (via sync-state.sh) and on a cron timer,
because tmux-continuum also saves on its own schedule.

Detection per tool:
  kiro-cli  -> ~/.kiro/sessions/cli/<id>.lock holds {"pid":...}; match against
               the pane's process tree.
  kilo/opencode -> pane title is "Kilo CLI | <title>" / "OC | <title>";
               look the title up in `<tool> session list`.
  claude    -> newest *.jsonl in ~/.claude/projects/<slug(cwd)>/, confirmed
               against the pane title when possible.
Idempotent: existing resume flags are stripped before new ones are added.
"""
import json, os, re, subprocess, sys, glob, shlex

HOME = os.path.expanduser("~")
STATE = os.environ.get("VSCODECONFIG_STATE", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "state"))
SNAP = os.path.join(HOME, ".local/share/tmux/resurrect/last")
PATH_EXTRA = ":".join([
    f"{HOME}/.local/bin", f"{HOME}/.bun/bin",
    *sorted(glob.glob(f"{HOME}/.nvm/versions/node/*/bin"), reverse=True),
])
ENV = dict(os.environ, PATH=PATH_EXTRA + ":" + os.environ.get("PATH", ""))


def sh(cmd, timeout=25):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True,
                              timeout=timeout, env=ENV).stdout
    except Exception:
        return ""


def descendants(pid):
    """All descendant pids of pid, inclusive."""
    out, frontier = {pid}, [pid]
    while frontier:
        p = frontier.pop()
        for c in sh(f"pgrep -P {p} 2>/dev/null").split():
            c = int(c)
            if c not in out:
                out.add(c); frontier.append(c)
    return out


def kiro_locks():
    """pid -> kiro session id"""
    m = {}
    for f in glob.glob(os.path.join(HOME, ".kiro/sessions/cli/*.lock")):
        try:
            with open(f) as fh:
                m[int(json.load(fh)["pid"])] = os.path.basename(f)[:-5]
        except Exception:
            pass
    return m


_LIST_CACHE = {}


def session_list(tool):
    """title -> id, newest first, for kilo / opencode."""
    if tool in _LIST_CACHE:
        return _LIST_CACHE[tool]
    rows = []
    for line in sh(f"{tool} session list 2>/dev/null").splitlines():
        line = line.rstrip()
        if not line.startswith("ses_"):
            continue
        parts = re.split(r"\s{2,}", line.strip())
        if len(parts) >= 2:
            rows.append((parts[1].strip(), parts[0].strip()))
    _LIST_CACHE[tool] = rows
    return rows


def match_title(tool, title):
    """Match a possibly-truncated pane title against the session list."""
    t = title.strip().rstrip(".").strip()
    if not t:
        return None
    rows = session_list(tool)
    for full, sid in rows:                       # exact
        if full == t:
            return sid
    for full, sid in rows:                       # truncated prefix
        if len(t) >= 8 and full.startswith(t):
            return sid
    return None


def claude_pid_id(tree):
    """Claude Code writes ~/.claude/sessions/<pid>.json with the live sessionId."""
    for pid in tree:
        f = os.path.join(HOME, ".claude/sessions", f"{pid}.json")
        try:
            with open(f) as fh:
                sid = json.load(fh).get("sessionId")
            if sid:
                return sid
        except Exception:
            pass
    return None


def claude_id(cwd, title):
    # FALLBACK ONLY: every pane in the same cwd shares one project dir, so the
    # "newest file" guess gave all claude panes the same id (seen 2026-10-09).
    slug = re.sub(r"[^A-Za-z0-9]", "-", cwd)
    d = os.path.join(HOME, ".claude/projects", slug)
    files = sorted(glob.glob(os.path.join(d, "*.jsonl")),
                   key=os.path.getmtime, reverse=True)
    if not files:
        return None
    key = re.sub(r"^[^A-Za-z0-9]+", "", title).strip()
    if key and len(key) > 6:
        for f in files[:12]:                     # confirm by title when we can
            try:
                with open(f, errors="replace") as fh:
                    if key[:40] in fh.read():
                        return os.path.basename(f)[:-6]
            except Exception:
                pass
    return os.path.basename(files[0])[:-6]


def detect():
    """tmux session name -> (tool, session id)"""
    fmt = "#{session_name}\t#{pane_pid}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_title}"
    locks = kiro_locks()
    found = {}
    for line in sh(f"tmux list-panes -a -F '{fmt}'").splitlines():
        p = line.split("\t")
        if len(p) < 5:
            continue
        name, pid, cmd, cwd, title = p[0], int(p[1]), p[2], p[3], p[4]
        tree = None
        sid = tool = None
        if cmd.startswith("kiro"):
            tool = "kiro-cli"
            tree = descendants(pid)
            for lp, ls in locks.items():
                if lp in tree:
                    sid = ls; break
        elif cmd == "claude":
            tool = "claude"
            sid = claude_pid_id(descendants(pid)) or claude_id(cwd, title)
        elif cmd == "opencode":
            tool = "opencode"
            sid = match_title("opencode", title.split("|", 1)[-1])
        elif cmd == "node" or cmd.endswith("kilo"):
            tool = "kilo"
            sid = match_title("kilo", title.split("|", 1)[-1])
        if tool and sid:
            found[name] = (tool, sid)
    return found


RESUME_RE = re.compile(
    r"\s+(?:-s|--session|--resume-id)(?:=|\s+)\S+"
    r"|\s+--resume(?:=|\s+)[0-9a-f]{8}-\S+"
    r"|\s+--resume(?!\S)"
)


def inject(cmd, tool, sid):
    cmd = RESUME_RE.sub("", cmd).rstrip()
    if tool == "claude":
        return f"{cmd} --resume {sid}"
    if tool == "kiro-cli":
        return f"{cmd} --resume-id {sid}"
    return f"{cmd} -s {sid}"          # kilo, opencode


def main():
    if not os.path.exists(SNAP):
        print("no resurrect snapshot", file=sys.stderr); return 1
    target = os.path.realpath(SNAP)
    ids = detect()
    if not ids:
        print("no agent sessions detected; snapshot untouched"); return 0

    out, changed = [], 0
    for line in open(target, errors="replace").read().splitlines():
        f = line.split("\t")
        if f and f[0] == "pane" and len(f) >= 11 and f[1] in ids:
            tool, sid = ids[f[1]]
            cmd = f[-1]
            lead = ":" if cmd.startswith(":") else ""
            body = cmd[1:] if lead else cmd
            if body.strip():
                new = lead + inject(body, tool, sid)
                if new != cmd:
                    f[-1] = new; changed += 1
                    line = "\t".join(f)
        out.append(line)

    tmp = target + ".tmp"
    with open(tmp, "w") as fh:
        fh.write("\n".join(out) + "\n")
    os.replace(tmp, target)
    # keep the most recent snapshot that carries commands for the boot-time
    # guard. FIX 2026-10-10: this was a high-water mark (only replaced by a
    # richer snapshot), so closed sessions came back on every reboot.
    good = os.path.join(STATE, "last-good.txt")
    def score(lines):
        return sum(1 for l in lines
                   if l.startswith("pane\t") and l.rstrip("\n").split("\t")[-1] not in (":", ""))
    n_new = score(out)
    if n_new >= 1:
        os.makedirs(os.path.dirname(good), exist_ok=True)
        with open(good + ".tmp", "w") as fh:
            fh.write("\n".join(out) + "\n")
        os.replace(good + ".tmp", good)

    print(f"injected resume ids into {changed} pane(s) of {os.path.basename(target)}")
    for n, (t, s) in sorted(ids.items()):
        print(f"  {n:<18} {t:<9} {s}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
