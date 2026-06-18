param(
    [ValidateSet("onedir", "onefile")]
    [string]$Mode = "onedir"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

python -m pip install --upgrade pyinstaller

$pyinstallerArgs = @(
    "--name", "MediaForge",
    "--windowed",
    "--clean",
    "--add-data", "static$([IO.Path]::PathSeparator)static"
)

$ffmpegBin = if ($env:MEDIAFORGE_FFMPEG) { $env:MEDIAFORGE_FFMPEG } else { (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source }
$ffprobeBin = if ($env:MEDIAFORGE_FFPROBE) { $env:MEDIAFORGE_FFPROBE } else { (Get-Command ffprobe -ErrorAction SilentlyContinue).Source }
if ($ffmpegBin -and $ffprobeBin) {
    $pyinstallerArgs += "--add-binary"
    $pyinstallerArgs += "$ffmpegBin$([IO.Path]::PathSeparator)ffmpeg/bin"
    $pyinstallerArgs += "--add-binary"
    $pyinstallerArgs += "$ffprobeBin$([IO.Path]::PathSeparator)ffmpeg/bin"
    Write-Host "Bundling FFmpeg: $ffmpegBin"
    Write-Host "Bundling FFprobe: $ffprobeBin"
} else {
    Write-Host "FFmpeg/ffprobe not found on this build machine; app will use bundled files if present or PATH at runtime."
}

if ($Mode -eq "onefile") {
    $pyinstallerArgs += "--onefile"
}

$pyinstallerArgs += "MediaForge.py"
python -m PyInstaller @pyinstallerArgs
