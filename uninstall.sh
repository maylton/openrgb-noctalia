#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_NAME="openrgb-noctalia"
PLUGIN_ID="maylton/openrgb-noctalia"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
NOCTALIA_ROOT="${NOCTALIA_CONFIG_HOME:-$CONFIG_HOME}/noctalia"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

if command -v noctalia >/dev/null 2>&1; then
  noctalia msg plugin "$PLUGIN_ID:sync" all cleanup >/dev/null 2>&1 || true
  sleep 0.2
  noctalia msg plugins disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  noctalia msg plugins source remove "$SOURCE_NAME" >/dev/null 2>&1 || true
fi

rm -f \
  "$NOCTALIA_ROOT/openrgb-noctalia.toml" \
  "$NOCTALIA_ROOT/templates/openrgb-noctalia-primary.txt.in" \
  "$NOCTALIA_ROOT/generated/openrgb-noctalia-primary.txt"

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$STATE_HOME/openrgb-noctalia"
fi

if command -v noctalia >/dev/null 2>&1; then
  noctalia msg config-reload >/dev/null 2>&1 || true
fi

echo "OpenRGB Noctalia removido."
