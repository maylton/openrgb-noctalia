#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_NAME="openrgb-noctalia"
PLUGIN_ID="maylton/openrgb-noctalia"
REPOSITORY="https://github.com/maylton/openrgb-noctalia"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'Erro: %s\n' "$*" >&2
  exit 1
}

command -v noctalia >/dev/null 2>&1 || fail "o comando noctalia não foi encontrado"
command -v openrgb >/dev/null 2>&1 || fail "o comando openrgb não foi encontrado"
command -v python3 >/dev/null 2>&1 || fail "o comando python3 não foi encontrado"

if [[ "${1:-}" == "--local" ]]; then
  noctalia msg plugins source remove "$SOURCE_NAME" >/dev/null 2>&1 || true
  noctalia msg plugins source add "$SOURCE_NAME" path "$SCRIPT_DIR"
else
  noctalia msg plugins source add "$SOURCE_NAME" git "$REPOSITORY" 2>/dev/null \
    || noctalia msg plugins update "$SOURCE_NAME"
  noctalia msg plugins update "$SOURCE_NAME" >/dev/null 2>&1 || true
fi

noctalia msg plugins enable "$PLUGIN_ID"
noctalia msg config-reload
noctalia msg plugin "$PLUGIN_ID:sync" all apply >/dev/null 2>&1 || true

cat <<EOF

OpenRGB Noctalia instalado.

Configuração:
  Noctalia Settings → Plugins → OpenRGB Noctalia

Atalho opcional:
  adicione "OpenRGB Noctalia" aos atalhos do Control Center.

Teste:
  noctalia msg plugin $PLUGIN_ID:sync all status
EOF
