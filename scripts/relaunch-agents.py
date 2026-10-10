#!/usr/bin/env python3
"""
Relaunch agent processes after a tmux-resurrect restore.

WHY THIS EXISTS
tmux-resurrect can only restore a pane's *process* while a client is
attached. Its restore_pane_process() starts with:

    tmux switch-client -t "session:window"
    tmux select-pane  -t "pane"

and `switch-client` fails with "no current client" when the tmux server was
started headless -- which is exactly what tmux.service does at boot. The
result is a restore that looks like it worked: every session, pane, title and
even the scrollback comes back, but every pane sits at a bare shell.

This script closes that gap without needing a client. It reads the same
snapshot resurrect just restored from and types the saved command into any
pane that is still at a shell prompt. `send-keys` needs no client, and
skipping non-shell panes makes it safe to run twice.

Wired as ExecStartPost of tmux.service; also runnable by hand.
"""
import glob, os, re, subprocess, sys, time

HOME = os.path.expanduser("~")
STATE = os.environ.get("VSCODECONFIG_STATE", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "state"))
# Read the protected copy first. Restoring a snapshot immediately fires the
# session-created hooks, which save a fresh snapshot of the just-restored
# (still empty) panes over "last" -- so by the time this runs, "last" usually
# describes bare shells. last-good.txt is only ever updated with a snapshot
# that carries commands, so it is the reliable source here.
GOOD = os.path.join(STATE, "last-good.txt")
LAST = os.path.join(HOME, ".local/share/tmux/resurrect/last")
# Written by prefer-good-snapshot.py at boot: exactly the snapshot continuum
# restored from. Preferred over both of the above (added 2026-10-10).
BOOT = os.path.join(STATE, "boot.txt")


def _pick_snapshot():
    def score(path):
        try:
            return sum(1 for l in open(path, errors="replace")
                       if l.startswith("pane\t") and l.rstrip("\n").split("\t")[-1] not in (":", ""))
        except Exception:
            return -1
    if score(BOOT) > 0:
        return BOOT
    return GOOD if score(GOOD) >= score(LAST) else LAST


SNAP = _pick_snapshot()
SHELLS = {"bash", "zsh", "sh", "fish", "dash"}
PLACEHOLDER = {"_boot", "bootstrap"}
# bare names -> absolute paths, PATH-independent (boot runs with a minimal PATH)
_SEARCH = [f"{HOME}/.local/bin", *sorted(glob.glob(f"{HOME}/.nvm/versions/node/*/bin"), reverse=True)]
ABS = {}
for _name in ("claude", "kiro-cli", "opencode", "kilo", "codex"):
    for _d in _SEARCH:
        if os.path.exists(os.path.join(_d, _name)):
            ABS[_name] = os.path.join(_d, _name); break


def tmux(*args, timeout=15):
    try:
        r = subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except Exception:
        return ""


def wanted():
    """(session, window, pane, dir, command) for every pane with a command."""
    out = []
    if not os.path.exists(SNAP):
        return out
    for line in open(os.path.realpath(SNAP), errors="replace"):
        f = line.rstrip("\n").split("\t")
        if len(f) < 11 or f[0] != "pane":
            continue
        cmd = f[10][1:] if f[10].startswith(":") else f[10]
        if not cmd.strip():
            continue
        d = f[7][1:] if f[7].startswith(":") else f[7]
        out.append((f[1], f[2], f[5], d or HOME, cmd))
    return out


def absolutise(cmd):
    parts = cmd.split(" ", 1)
    head = parts[0]
    if "/" not in head and head in ABS and os.path.exists(ABS[head]):
        return ABS[head] + (" " + parts[1] if len(parts) > 1 else "")
    return cmd


def live():
    """(session, window, pane) -> current command"""
    fmt = "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_current_command}"
    m = {}
    for line in tmux("list-panes", "-a", "-F", fmt).splitlines():
        p = line.split("\t")
        if len(p) == 4:
            m[(p[0], p[1], p[2])] = p[3]
    return m


def main():
    targets = wanted()
    if not targets:
        print("snapshot has no pane commands; nothing to relaunch")
        return 0
    names = {t[0] for t in targets}

    # Wait for continuum's restore to finish creating the sessions.
    deadline = time.time() + 45
    while time.time() < deadline:
        have = {s for s in tmux("list-sessions", "-F", "#{session_name}").splitlines()}
        if names <= have:
            break
        time.sleep(2)
    else:
        print("timed out waiting for restore; relaunching what exists")

    time.sleep(2)                       # let the restored shells settle
    cur = live()
    launched = skipped = 0
    for sess, win, pane, d, cmd in targets:
        if sess in PLACEHOLDER:
            continue
        key = (sess, win, pane)
        if key not in cur:
            print(f"  {sess}: pane missing, skipped"); skipped += 1; continue
        if cur[key] not in SHELLS:
            print(f"  {sess}: already running {cur[key]}, skipped"); skipped += 1; continue
        target = f"{sess}:{win}.{pane}"
        tmux("send-keys", "-t", target, f"cd {d} && {absolutise(cmd)}", "Enter")
        print(f"  {sess}: launched {absolutise(cmd).split()[0].split('/')[-1]}")
        launched += 1
        time.sleep(0.4)
    print(f"relaunched {launched} pane(s), skipped {skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
