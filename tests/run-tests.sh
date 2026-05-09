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


test_tclean_detects_old_editor_task_shells() {
  local work="$TMP_ROOT/tclean-detect"
  mkdir -p "$work"
  cat > "$work/ps.txt" <<'EOF'
100 1 /home/ft/.cursor-server/bin/node out/bootstrap-fork --type=ptyHost
200 100 /bin/bash -c printf '\033]0;admin\007'; tmux attach -t admin 2>/dev/null || tmux new-session -s admin 'claude --dangerously-skip-permissions'
300 100 /bin/bash -c printf '\033]0;aziz\007'; tmux has-session -t =aziz 2>/dev/null && tmux attach -t =aziz
400 1 /bin/bash -c printf '\033]0;manual\007'; tmux attach -t manual 2>/dev/null || tmux new-session -s manual 'claude --dangerously-skip-permissions'
EOF

  VSCODECONFIG_PS_FILE="$work/ps.txt" \
    bash "$ROOT/scripts/clean-stuck-terminals.sh" --dry-run > "$work/out.txt"

  grep -q '^200 100 admin ' "$work/out.txt" || fail "tclean did not report old editor task shell"
  grep -q 'Dry run only' "$work/out.txt" || fail "tclean did not stay in dry-run mode"
  ! grep -q '^300 ' "$work/out.txt" || fail "tclean reported current attach-only task"
  ! grep -q '^400 ' "$work/out.txt" || fail "tclean reported non-editor shell"
}

test_tclean_no_matches() {
  local work="$TMP_ROOT/tclean-none"
  mkdir -p "$work"
  cat > "$work/ps.txt" <<'EOF'
100 1 /home/ft/.cursor-server/bin/node out/bootstrap-fork --type=ptyHost
300 100 /bin/bash -c printf '\033]0;aziz\007'; tmux has-session -t =aziz 2>/dev/null && tmux attach -t =aziz
EOF

  VSCODECONFIG_PS_FILE="$work/ps.txt" \
    bash "$ROOT/scripts/clean-stuck-terminals.sh" --dry-run > "$work/out.txt"

  grep -q 'No stale pre-v1.2.1 editor task shells found.' "$work/out.txt" || fail "tclean no-match message missing"
}

test_gen_tasks_clears_stale_file_when_no_sessions
test_tk_syncs_resurrect_after_kill
test_gen_tasks_writes_valid_tasks_for_sessions
test_tclean_detects_old_editor_task_shells
test_tclean_no_matches

echo "All tests passed"
