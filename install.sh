#!/bin/bash
# VScodeconfig installer - sets up tmux <-> VS Code/Cursor tab integration
# backed by named tmux sessions.
#
# Idempotent: safe to re-run.
#
# Layout after install:
#   $HOME/.local/bin/{tn,tnx,ta,tk,tclean} - symlinks into this repo's bin/
#   <this repo>/scripts/                   - worker scripts, run in place
#   <this repo>/state/                     - snapshots, logs, locks (gitignored)
#   $HOME/.vscode/tasks.json               - auto-generated from live tmux sessions
#   $HOME/.tmux.conf                       - appends a managed block (if missing)
#   crontab                                - 5-min refresh of tasks/resurrect state

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Runs in place: everything executes from this checkout, nothing is copied to a
# hidden folder (they used to be copied to ~/.vscodeconfig and drifted apart).
DEST="$SRC"
BIN="${VSCODECONFIG_BIN:-$HOME/.local/bin}"
TMUX_CONF="$HOME/.tmux.conf"
MARK="# --- VScodeconfig:"

echo "==> Installing VScodeconfig"
echo "    package:   $SRC"
echo "    dest:      $DEST"
echo "    bin:       $BIN"

mkdir -p "$DEST/state" "$BIN" "$HOME/.vscode"
chmod +x "$DEST/scripts/"*.sh "$DEST/scripts/"*.py

echo "--> Merging workspace VS Code settings ($HOME/.vscode/settings.json)"
# Window-scoped keys that make OSC-set tab titles + single-click focus work
# over Remote-SSH without touching the Mac's User settings. Existing keys are
# preserved; only the five we own get written.
SETTINGS_FILE="$HOME/.vscode/settings.json"
export SETTINGS_FILE
python3 - <<'PY'
import json, os
path = os.environ["SETTINGS_FILE"]
try:
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
managed = {
    "terminal.integrated.tabs.title": "${sequence}",
    "terminal.integrated.tabs.description": "${task}${separator}${cwdFolder}",
    "terminal.integrated.tabs.enabled": True,
    "terminal.integrated.tabs.focusMode": "singleClick",
}
data.update(managed)
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"    wrote {len(managed)} managed keys (preserved others)")
PY

echo "--> Linking commands (tn, tnx, ta, tk, tclean)"
for cmd in tn tnx tngr tngm tnm tnds ta tk tclean; do
  chmod +x "$SRC/bin/$cmd"
  ln -sfn "$SRC/bin/$cmd" "$BIN/$cmd"
done

echo "--> Updating ~/.tmux.conf"
touch "$TMUX_CONF"
if grep -qF "$MARK" "$TMUX_CONF"; then
  awk '
    /^# --- VScodeconfig:/ {skip=1}
    !skip {print}
    /^# --- \/VScodeconfig ---/ {skip=0; next}
  ' "$TMUX_CONF" > "$TMUX_CONF.tmp" && mv "$TMUX_CONF.tmp" "$TMUX_CONF"
  echo "    (removed old managed block)"
fi
echo "" >> "$TMUX_CONF"
sed "s#__VSCODECONFIG_DIR__#$SRC#g" "$SRC/tmux.conf.snippet" >> "$TMUX_CONF"
echo "    (appended fresh managed block)"

# Reload so changes take effect without requiring kill-server
tmux source-file "$TMUX_CONF" >/dev/null 2>&1 || true

echo "--> Installing cron entry (every 5 min)"
CRON_LINE="*/5 * * * * /bin/bash $DEST/scripts/sync-state.sh >/dev/null 2>&1"
INJECT_LINE="*/5 * * * * /usr/bin/python3 $DEST/scripts/inject-agent-sessions.py >> $DEST/state/inject.log 2>&1"
# Strip any prior lines referencing the worker scripts, then append ours.
( crontab -l 2>/dev/null \
    | grep -v -E 'sync-state\.sh|gen-tasks\.sh|claude-session-map\.sh|inject-agent-sessions\.py' || true
  echo "$CRON_LINE"
  echo "$INJECT_LINE"
) | crontab -

echo "--> Installing reboot-restore unit (systemd --user)"
if command -v systemctl >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/systemd/user"
  sed "s#__VSCODECONFIG_DIR__#$SRC#g" "$SRC/systemd/tmux.service" > "$DEST/state/tmux.service"
  ln -sfn "$DEST/state/tmux.service" "$HOME/.config/systemd/user/tmux.service"
  systemctl --user daemon-reload && systemctl --user enable tmux.service >/dev/null 2>&1 || true
fi

echo "--> Installing tpm (tmux plugin manager) if missing"
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
    echo "    Installed tpm — inside tmux, press: prefix + I   to install resurrect/continuum"
  else
    echo "    git not found; skip. Install tpm manually: https://github.com/tmux-plugins/tpm"
  fi
else
  echo "    (tpm already present)"
fi

echo ""
echo "==> Done."
echo "    Ensure \$HOME/.local/bin is on your PATH (most distros add it automatically)."
echo "    Reload tmux:   tmux kill-server   (or just keep working — hooks load on next tmux start)"
echo "    Try:           tn demo"
