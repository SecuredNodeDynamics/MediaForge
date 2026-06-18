#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mode="${1:-onedir}"
python3 -m pip install --upgrade pyinstaller

args=(
  --name MediaForge
  --windowed
  --clean
  --add-data "static:static"
)

if [[ "$mode" == "onefile" ]]; then
  args+=(--onefile)
fi

python3 -m PyInstaller "${args[@]}" MediaForge.py
