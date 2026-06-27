#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
from pathlib import Path
import json
import tomllib

for path in (Path("catalog.toml"), Path("openrgb-noctalia/plugin.toml")):
    with path.open("rb") as handle:
        tomllib.load(handle)

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

echo "Validação concluída."
