@echo off
REM Build-Installer.bat — MediaForge Full Installer Builder
REM Builds MediaForge.exe via PS2EXE, then packages it with bundled FFmpeg
REM into a single Inno Setup installer.
REM
REM Requirements:
REM   - PS2EXE:       Install-Module ps2exe -Scope CurrentUser -Force
REM   - Inno Setup 6: https://jrsoftware.org/isdl.php
REM   - FFmpeg bins:  .\ffmpeg\bin\ffmpeg.exe + ffprobe.exe + ffplay.exe

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "FFMPEG_BIN=%SCRIPT_DIR%ffmpeg\bin"
set "INNO_COMPILER=C:\PROGRA~2\Inno Setup 6\ISCC.exe"
set "ISS_FILE=%SCRIPT_DIR%MediaForge.iss"
set "PS1_INPUT=%SCRIPT_DIR%MediaForge-GUI.ps1"
set "EXE_OUTPUT=%SCRIPT_DIR%MediaForge.exe"
set "ICON_FILE=%SCRIPT_DIR%static\logo.ico"
set "LOG_FILE=%SCRIPT_DIR%build.log"

if exist "%LOG_FILE%" del "%LOG_FILE%"

echo ============================================================
echo   MediaForge Build Script
echo ============================================================
echo.

echo [1/4] Checking prerequisites...

if not exist "%PS1_INPUT%" (
    echo [ERROR] MediaForge-GUI.ps1 not found in project folder.
    goto :fail
)
if not exist "%FFMPEG_BIN%\ffmpeg.exe" (
    echo [ERROR] ffmpeg.exe not found at: %FFMPEG_BIN%\ffmpeg.exe
    goto :fail
)
if not exist "%FFMPEG_BIN%\ffprobe.exe" (
    echo [ERROR] ffprobe.exe not found at: %FFMPEG_BIN%\ffprobe.exe
    goto :fail
)
if not exist "%FFMPEG_BIN%\ffplay.exe" (
    echo [ERROR] ffplay.exe not found at: %FFMPEG_BIN%\ffplay.exe
    goto :fail
)
if not exist "%INNO_COMPILER%" (
    echo [ERROR] Inno Setup 6 not found at:
    echo         %INNO_COMPILER%
    echo         Install from https://jrsoftware.org/isdl.php
    goto :fail
)

echo [1b/4] Verifying PS2EXE module...
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (-not (Get-Module -ListAvailable -Name ps2exe)) { exit 1 }"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] PS2EXE not installed.
    echo         Run in PowerShell: Install-Module ps2exe -Scope CurrentUser -Force
    goto :fail
)

echo [OK] All prerequisites found.
echo.
echo [2/4] Compiling MediaForge-GUI.ps1 to MediaForge.exe...
echo       (May take 10-30 seconds)
echo.

REM Write a small wrapper ps1 that calls ps2exe with proper quoting,
REM then execute it. This avoids all bat->powershell quoting issues.
set "WRAPPER=%TEMP%\mf_build_wrapper.ps1"

(
echo $ErrorActionPreference = 'Stop'
echo try {
echo     ps2exe -inputFile "%PS1_INPUT%" -outputFile "%EXE_OUTPUT%" -iconFile "%ICON_FILE%" -noConsole -title 'MediaForge' -description 'TMDB-powered media renamer for Jellyfin' -product 'MediaForge'
echo     Write-Host 'PS2EXE OK'
echo } catch {
echo     Write-Host "PS2EXE FAILED: $($_.Exception.Message)"
echo     exit 1
echo }
) > "%WRAPPER%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%WRAPPER%" > "%LOG_FILE%" 2>&1
set PS2EXE_ERR=%ERRORLEVEL%

type "%LOG_FILE%"

if %PS2EXE_ERR% NEQ 0 (
    echo.
    echo [ERROR] PS2EXE compilation failed.
    goto :fail
)
if not exist "%EXE_OUTPUT%" (
    echo.
    echo [ERROR] MediaForge.exe was not produced.
    goto :fail
)

echo.
echo [OK] MediaForge.exe compiled.
echo.
echo [3/4] Building installer with Inno Setup...

"%INNO_COMPILER%" "%ISS_FILE%"
set INNO_ERR=%ERRORLEVEL%

if %INNO_ERR% NEQ 0 (
    echo [ERROR] Inno Setup failed with exit code %INNO_ERR%.
    goto :fail
)
if not exist "%SCRIPT_DIR%installer\MediaForge-install.exe" (
    echo [ERROR] installer\MediaForge-install.exe was not created.
    goto :fail
)

echo.
echo [4/4] Done!
echo.
echo ============================================================
echo   OUTPUT: %SCRIPT_DIR%installer\MediaForge-install.exe
echo ============================================================
echo.
pause
exit /b 0

:fail
echo.
echo ============================================================
echo   BUILD FAILED
echo ============================================================
echo.
pause
exit /b 1
