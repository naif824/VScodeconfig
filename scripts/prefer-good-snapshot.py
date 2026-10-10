#!/usr/bin/env python3
"""
Boot-time guard: make sure tmux-continuum restores the state from just before
the reboot, not a blank one.

The resurrect "last" pointer can be left pointing at a blank snapshot (every
command field empty) if a save fires while the agents are being torn down at
shutdown. inject-agent-sessions.py keeps "last-good", the most recent snapshot
that carried commands. At boot, before the tmux server starts:
  - "last" carries commands -> it IS the pre-reboot state; keep it.
  - "last" is blank         -> repoint it at last-good.
The chosen snapshot is copied to state/boot.txt for relaunch-agents.py.

FIX 2026-10-10: this used to repoint whenever last-good had MORE panes. But
last-good was a high-water mark (only replaced by a richer snapshot), so after
sessions were closed it kept resurrecting them on every reboot (Oct 9 reboot
brought back 7 sessions closed since Oct 2).

Runs as ExecStartPre of the tmux.service user unit.
"""
import os, shutil, sys, time

HOME = os.path.expanduser("~")
STATE = os.environ.get("VSCODECONFIG_STATE", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "state"))
RES = os.path.join(HOME, ".local/share/tmux/resurrect")
LAST = os.path.join(RES, "last")
GOOD = os.path.join(STATE, "last-good.txt")
BOOT = os.path.join(STATE, "boot.txt")


def panes(path):
    """Score a snapshot by panes that carry a restorable command.

    Counting panes alone is not enough: a save fired while the agents are
    being torn down keeps all the panes but blanks every command field, so
    a restore from it yields the right sessions full of bare shells.
    """
    try:
        seen = set()                 # unique panes; a duplicated line must not count twice
        with open(path, errors="replace") as fh:
            for l in fh:
                f = l.rstrip("\n").split("\t")
                if f[0] == "pane" and len(f) >= 11 and f[-1] not in (":", ""):
                    seen.add((f[1], f[2], f[5]))
        return len(seen)
    except Exception:
        return -1


def main():
    n_last, n_good = panes(LAST), panes(GOOD)
    print(f"last={n_last} panes, last-good={n_good} panes")
    if n_last > 0 or n_good <= 0:
        print("last carries commands (or no fallback); restoring it as-is")
        if os.path.exists(LAST):
            shutil.copyfile(os.path.realpath(LAST), BOOT)
        return 0
    target = os.path.join(RES, f"tmux_resurrect_{time.strftime('%Y%m%dT%H%M%S')}_recovered.txt")
    os.makedirs(RES, exist_ok=True)
    shutil.copyfile(GOOD, target)
    tmp = LAST + ".tmp"
    if os.path.islink(tmp) or os.path.exists(tmp):
        os.remove(tmp)
    os.symlink(os.path.basename(target), tmp)
    os.replace(tmp, LAST)
    shutil.copyfile(GOOD, BOOT)
    print(f"last was blank; repointed last -> {os.path.basename(target)} ({n_good} panes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
