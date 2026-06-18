# -*- mode: python ; coding: utf-8 -*-

import shutil

ffmpeg_binaries = []
ffmpeg_path = shutil.which('ffmpeg')
ffprobe_path = shutil.which('ffprobe')
if ffmpeg_path and ffprobe_path:
    ffmpeg_binaries = [
        (ffmpeg_path, 'ffmpeg/bin'),
        (ffprobe_path, 'ffmpeg/bin'),
    ]


a = Analysis(
    ['MediaForge.py'],
    pathex=[],
    binaries=ffmpeg_binaries,
    datas=[('static', 'static')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='MediaForge',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='MediaForge',
)
