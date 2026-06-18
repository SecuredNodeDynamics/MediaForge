@echo off
REM Build-GUI.bat — Compile MediaForge-GUI.ps1 -> MediaForge.exe via PS2EXE
REM Run from the same folder as MediaForge-GUI.ps1
REM
REM -requireAdmin has been intentionally removed. Running as admin blocks
REM drag-and-drop because Explorer (non-elevated) cannot drop onto an
REM elevated process. The script uses Move-Item which works without admin
REM as long as you own the files being renamed.

echo [Build] Compiling MediaForge-GUI.ps1 ...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"ps2exe -inputFile '%~dp0MediaForge-GUI.ps1' -outputFile '%~dp0MediaForge.exe' -iconFile '%~dp0static\logo.ico' -noConsole -title 'MediaForge' -description 'TMDB-powered media renamer for Jellyfin' -product 'MediaForge'"

if %ERRORLEVEL% EQU 0 (
echo [OK] Build succeeded: MediaForge.exe
) else (
echo [ERROR] Build failed. Make sure PS2EXE is installed:
echo Install-Module ps2exe -Scope CurrentUser
)
pause
