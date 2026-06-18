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

ffmpeg_bin="${MEDIAFORGE_FFMPEG:-$(command -v ffmpeg || true)}"
ffprobe_bin="${MEDIAFORGE_FFPROBE:-$(command -v ffprobe || true)}"
if [[ -n "$ffmpeg_bin" && -n "$ffprobe_bin" ]]; then
  args+=(--add-binary "$ffmpeg_bin:ffmpeg/bin")
  args+=(--add-binary "$ffprobe_bin:ffmpeg/bin")
  echo "Bundling FFmpeg: $ffmpeg_bin"
  echo "Bundling FFprobe: $ffprobe_bin"
else
  echo "FFmpeg/ffprobe not found on this build machine; app will use bundled files if present or PATH at runtime."
fi

if [[ "$mode" == "onefile" ]]; then
  args+=(--onefile)
fi

python3 -m PyInstaller "${args[@]}" MediaForge.py
