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

echo "--> Installing commands (tn, ta, tk)"
for cmd in tn ta tk; do
  cp "$SRC/bin/$cmd" "$BIN/$cmd"
  chmod +x "$BIN/$cmd"
done

echo "--> Updating ~/.tmux.conf"
touch "$TMUX_CONF"
if grep -qF "$MARK" "$TMUX_CONF"; then
  echo "    (managed block already present — leaving .tmux.conf alone)"
else
  echo "" >> "$TMUX_CONF"
  cat "$SRC/tmux.conf.snippet" >> "$TMUX_CONF"
  echo "    (appended managed block)"
fi

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
