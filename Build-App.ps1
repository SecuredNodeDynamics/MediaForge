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

if ($Mode -eq "onefile") {
    $pyinstallerArgs += "--onefile"
}

$pyinstallerArgs += "MediaForge.py"
python -m PyInstaller @pyinstallerArgs
