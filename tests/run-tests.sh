#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "$ROOT/.tmp-tests.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_fake_tmux() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/tmux" <<'SH'
#!/bin/bash
case "$1" in
  list-sessions)
    if [ "${TMUX_FAKE_SESSIONS:-}" = "__EMPTY__" ]; then
      exit 1
    fi
    if [ -n "${TMUX_FAKE_SESSIONS:-}" ]; then
      printf '%s\n' "$TMUX_FAKE_SESSIONS"
    fi
    ;;
  list-panes)
    printf '12345\n'
    ;;
  has-session)
    exit 0
    ;;
  kill-session)
    printf '%s\n' "$*" >> "${TMUX_FAKE_KILLS:?}"
    ;;
  *)
    exit 0
    ;;
esac
SH
  chmod +x "$dir/bin/tmux"
}

test_gen_tasks_clears_stale_file_when_no_sessions() {
  local work="$TMP_ROOT/no-sessions"
  mkdir -p "$work/.vscode" "$work/.claude"
  make_fake_tmux "$work"
  cat > "$work/.vscode/tasks.json" <<'JSON'
{"version":"2.0.0","tasks":[{"label":"stale"}]}
JSON

  HOME="$work" PATH="$work/bin:$PATH" TMUX_FAKE_SESSIONS="__EMPTY__" \
    bash "$ROOT/scripts/gen-tasks.sh" >/tmp/vscodeconfig-test.log

  python3 - "$work/.vscode/tasks.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
assert doc == {"version": "2.0.0", "tasks": []}, doc
PY
}

test_tk_syncs_resurrect_after_kill() {
  local work="$TMP_ROOT/tk"
  mkdir -p "$work/.vscodeconfig/scripts" "$work/.tmux/plugins/tmux-resurrect/scripts"
  make_fake_tmux "$work"
  cp "$ROOT/scripts/sync-state.sh" "$work/.vscodeconfig/scripts/sync-state.sh"
  cat > "$work/.vscodeconfig/scripts/gen-tasks.sh" <<'SH'
#!/bin/bash
printf 'gen\n' >> "$HOME/sync.log"
SH
  chmod +x "$work/.vscodeconfig/scripts/"*.sh
  cat > "$work/.tmux/plugins/tmux-resurrect/scripts/save.sh" <<'SH'
#!/bin/bash
printf 'save\n' >> "$HOME/sync.log"
SH
  chmod +x "$work/.tmux/plugins/tmux-resurrect/scripts/save.sh"

  HOME="$work" PATH="$work/bin:$PATH" TMUX_FAKE_KILLS="$work/kills.log" \
    bash "$ROOT/bin/tk" demo >/tmp/vscodeconfig-test.log

  grep -qx -- 'kill-session -t demo' "$work/kills.log" || fail "tmux kill-session was not called for demo"
  grep -qx 'gen' "$work/sync.log" || fail "gen-tasks was not called"
  grep -qx 'save' "$work/sync.log" || fail "resurrect save was not called"
}

test_gen_tasks_writes_valid_tasks_for_sessions() {
  local work="$TMP_ROOT/with-sessions"
  mkdir -p "$work/.vscode" "$work/.claude"
  make_fake_tmux "$work"

  HOME="$work" PATH="$work/bin:$PATH" TMUX_FAKE_SESSIONS=$'alpha\nbeta' \
    bash "$ROOT/scripts/gen-tasks.sh" >/tmp/vscodeconfig-test.log

  python3 - "$work/.vscode/tasks.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
labels = [task["label"] for task in doc["tasks"]]
assert labels == ["alpha", "beta", "Open Primary Sessions"], labels
for task in doc["tasks"]:
    if task["label"] == "Open Primary Sessions":
        continue
    cmd = task["command"]
    assert "tmux has-session" in cmd, cmd
    assert "tmux attach" in cmd, cmd
    assert "tmux new-session" not in cmd, cmd
PY
}

test_gen_tasks_clears_stale_file_when_no_sessions
test_tk_syncs_resurrect_after_kill
test_gen_tasks_writes_valid_tasks_for_sessions

echo "All tests passed"
