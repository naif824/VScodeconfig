#!/bin/bash
# VScodeconfig installer — sets up tmux <-> VS Code tab integration with
# Claude Code session-resume continuity.
#
# Idempotent: safe to re-run.
#
# Layout after install:
#   $HOME/.local/bin/{tn,ta,tk}            — shell commands
#   $HOME/.vscodeconfig/scripts/*.sh       — worker scripts
#   $HOME/.vscode/tasks.json               — auto-generated on first tmux session
#   $HOME/.tmux.conf                       — appends a managed block (if missing)
#   crontab                                — 5-min refresh of tasks.json

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${VSCODECONFIG_DEST:-$HOME/.vscodeconfig}"
BIN="${VSCODECONFIG_BIN:-$HOME/.local/bin}"
TMUX_CONF="$HOME/.tmux.conf"
MARK="# --- VScodeconfig:"

echo "==> Installing VScodeconfig"
echo "    package:   $SRC"
echo "    dest:      $DEST"
echo "    bin:       $BIN"

mkdir -p "$DEST/scripts" "$BIN" "$HOME/.vscode" "$HOME/.claude"

echo "--> Installing worker scripts"
cp "$SRC/scripts/"*.sh "$DEST/scripts/"
chmod +x "$DEST/scripts/"*.sh

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

echo "--> Installing commands (tn, tnx, ta, tk)"
for cmd in tn tnx ta tk; do
  cp "$SRC/bin/$cmd" "$BIN/$cmd"
  chmod +x "$BIN/$cmd"
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
cat "$SRC/tmux.conf.snippet" >> "$TMUX_CONF"
echo "    (appended fresh managed block)"

# Reload so changes take effect without requiring kill-server
tmux source-file "$TMUX_CONF" >/dev/null 2>&1 || true

echo "--> Installing cron entry (every 5 min)"
CRON_LINE="*/5 * * * * /bin/bash $DEST/scripts/gen-tasks.sh >/dev/null 2>&1"
# Strip any prior lines referencing either worker script, then append the one we want.
( crontab -l 2>/dev/null \
    | grep -v -E 'gen-tasks\.sh|claude-session-map\.sh' || true
  echo "$CRON_LINE"
) | crontab -

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
