#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
from pathlib import Path
import json
import tomllib

catalog_path = Path("catalog.toml")
plugin_path = Path("openrgb-noctalia/plugin.toml")

with catalog_path.open("rb") as handle:
    catalog = tomllib.load(handle)
with plugin_path.open("rb") as handle:
    plugin = tomllib.load(handle)

catalog_version = catalog["plugin"][0]["version"]
plugin_version = plugin["version"]
if catalog_version != plugin_version:
    raise SystemExit(
        f"Version mismatch: catalog={catalog_version}, plugin={plugin_version}"
    )

for path in Path("openrgb-noctalia/translations").glob("*.json"):
    json.loads(path.read_text(encoding="utf-8"))

print("TOML e JSON válidos.")
PY

python3 -m py_compile openrgb-noctalia/apply_color.py
python3 -m unittest discover -s tests -v
bash -n install.sh
bash -n uninstall.sh

grep -Fq 'id           = "maylton/openrgb-noctalia"' openrgb-noctalia/plugin.toml
grep -Fq '[[service]]' openrgb-noctalia/plugin.toml
grep -Fq '[[shortcut]]' openrgb-noctalia/plugin.toml
grep -Fq 'function onIpc' openrgb-noctalia/service.luau
grep -Fq 'return (tostring(value):gsub("^%s+", ""):gsub("%s+$", ""))' \
  openrgb-noctalia/service.luau

if grep -Fq 'string.trim' openrgb-noctalia/service.luau; then
  echo "Erro: string.trim não é compatível com o runtime Luau do Noctalia." >&2
  exit 1
fi

echo "Validação concluída."
