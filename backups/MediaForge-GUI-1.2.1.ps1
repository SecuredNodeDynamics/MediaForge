#Requires -Version 5.1
# Rename-GUI.ps1 — MediaForge (WinForms GUI)
# Compile: ps2exe -inputFile Rename-GUI.ps1 -outputFile Rename-GUI.exe -noConsole

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ─────────────────────────────────────────────────────────────────────────────
#  DARK MENU RENDERER
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public class RoundedButton : System.Windows.Forms.Button {
    private int _radius = 5;
    public int Radius { get { return _radius; } set { _radius = value; Invalidate(); } }

    public RoundedButton() {
        SetStyle(System.Windows.Forms.ControlStyles.UserPaint |
                 System.Windows.Forms.ControlStyles.AllPaintingInWmPaint |
                 System.Windows.Forms.ControlStyles.OptimizedDoubleBuffer |
                 System.Windows.Forms.ControlStyles.Selectable, true);
        FlatStyle = System.Windows.Forms.FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        TabStop = false;   // removes dotted focus rectangle
    }

    private System.Drawing.Drawing2D.GraphicsPath GetRoundedPath(System.Drawing.Rectangle rect) {
        int r = _radius * 2;
        var path = new System.Drawing.Drawing2D.GraphicsPath();
        path.AddArc(rect.X,          rect.Y,           r, r, 180, 90);
        path.AddArc(rect.Right - r,  rect.Y,           r, r, 270, 90);
        path.AddArc(rect.Right - r,  rect.Bottom - r,  r, r,   0, 90);
        path.AddArc(rect.X,          rect.Bottom - r,  r, r,  90, 90);
        path.CloseFigure();
        return path;
    }

    protected override void OnPaint(System.Windows.Forms.PaintEventArgs e) {
        var g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;

        // Clear background to parent color to eliminate rectangular ghost border
        g.Clear(Parent != null ? Parent.BackColor : System.Drawing.Color.Transparent);

        var rect = new System.Drawing.Rectangle(1, 1, Width - 2, Height - 2);
        using (var path = GetRoundedPath(rect)) {
            // Set clip to rounded shape so nothing bleeds outside
            g.SetClip(path);

            // Fill base color
            using (var brush = new System.Drawing.SolidBrush(BackColor))
                g.FillPath(brush, path);

            // Hover tint
            bool isHovered = ClientRectangle.Contains(PointToClient(System.Windows.Forms.Control.MousePosition));
            bool isPressed = isHovered && (System.Windows.Forms.Control.MouseButtons == System.Windows.Forms.MouseButtons.Left);
            if (isPressed) {
                using (var overlay = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(40, 0, 0, 0)))
                    g.FillPath(overlay, path);
            } else if (isHovered) {
                using (var overlay = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(25, 255, 255, 255)))
                    g.FillPath(overlay, path);
            }

            g.ResetClip();

            // Draw text — centered
            var sf = new System.Drawing.StringFormat {
                Alignment     = System.Drawing.StringAlignment.Center,
                LineAlignment = System.Drawing.StringAlignment.Center,
                FormatFlags   = System.Drawing.StringFormatFlags.NoWrap
            };
            using (var brush = new System.Drawing.SolidBrush(ForeColor))
                g.DrawString(Text, Font, brush, new System.Drawing.RectangleF(0, 0, Width, Height), sf);
        }
    }

    // Suppress default WinForms focus rectangle entirely
    protected override bool ShowFocusCues { get { return false; } }

    protected override void OnMouseEnter(System.EventArgs e) { base.OnMouseEnter(e); Invalidate(); }
    protected override void OnMouseLeave(System.EventArgs e) { base.OnMouseLeave(e); Invalidate(); }
    protected override void OnMouseDown(System.Windows.Forms.MouseEventArgs e) { base.OnMouseDown(e); Invalidate(); }
    protected override void OnMouseUp(System.Windows.Forms.MouseEventArgs e) { base.OnMouseUp(e); Invalidate(); }
}

public class DarkMenuRenderer : ToolStripProfessionalRenderer {
    public DarkMenuRenderer() : base(new DarkColorTable()) {}
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
        if (e.Item.ForeColor != Color.White && e.Item.ForeColor != SystemColors.ControlText && e.Item.ForeColor != SystemColors.Control)
            e.TextColor = e.Item.ForeColor;
        else
            e.TextColor = e.Item.Enabled ? Color.White : Color.FromArgb(120, 120, 140);
        base.OnRenderItemText(e);
    }
}

public class DarkColorTable : ProfessionalColorTable {
    public override Color MenuItemSelected                { get { return Color.FromArgb(60, 60, 80); } }
    public override Color MenuItemSelectedGradientBegin   { get { return Color.FromArgb(60, 60, 80); } }
    public override Color MenuItemSelectedGradientEnd     { get { return Color.FromArgb(60, 60, 80); } }
    public override Color MenuItemPressedGradientBegin    { get { return Color.FromArgb(40, 40, 58); } }
    public override Color MenuItemPressedGradientEnd      { get { return Color.FromArgb(40, 40, 58); } }
    public override Color MenuItemBorder                  { get { return Color.FromArgb(80, 80, 110); } }
    public override Color MenuBorder                      { get { return Color.FromArgb(60, 60, 80); } }
    public override Color ToolStripDropDownBackground     { get { return Color.FromArgb(28, 28, 40); } }
    public override Color ImageMarginGradientBegin        { get { return Color.FromArgb(28, 28, 40); } }
    public override Color ImageMarginGradientMiddle       { get { return Color.FromArgb(28, 28, 40); } }
    public override Color ImageMarginGradientEnd          { get { return Color.FromArgb(28, 28, 40); } }
    public override Color SeparatorDark                   { get { return Color.FromArgb(60, 60, 80); } }
    public override Color SeparatorLight                  { get { return Color.FromArgb(60, 60, 80); } }
}
"@ -ReferencedAssemblies "System.Windows.Forms","System.Drawing"

# ─────────────────────────────────────────────────────────────────────────────
#  UNDO STACK
# ─────────────────────────────────────────────────────────────────────────────
$script:UndoStack = [System.Collections.Generic.Stack[hashtable]]::new()
$script:AudioReport  = [System.Collections.Generic.List[hashtable]]::new()
$script:CachedTVEntries = $null

# ─────────────────────────────────────────────────────────────────────────────
#  COLOR HELPER
# ─────────────────────────────────────────────────────────────────────────────
function Get-LogColor {
    param([string]$Name)
    switch ($Name) {
        "Cyan"       { return [System.Drawing.Color]::FromArgb(100, 220, 255) }
        "LightGreen" { return [System.Drawing.Color]::FromArgb(100, 220, 150) }
        "Yellow"     { return [System.Drawing.Color]::FromArgb(255, 220,  80) }
        "Gray"       { return [System.Drawing.Color]::FromArgb(140, 140, 160) }
        "Red"        { return [System.Drawing.Color]::FromArgb(240,  80,  80) }
        "Orange"     { return [System.Drawing.Color]::FromArgb(255, 160,  60) }
        default      { return [System.Drawing.Color]::FromArgb(210, 210, 220) }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  CONFIG PERSISTENCE
# ─────────────────────────────────────────────────────────────────────────────
$script:ConfigDir    = [System.IO.Path]::Combine($env:APPDATA, "JellyfinRenamer")
$script:ConfigFile   = [System.IO.Path]::Combine($script:ConfigDir, "key.dat")
$script:FFmpegFile   = [System.IO.Path]::Combine($script:ConfigDir, "ffmpeg.dat")
$script:TMDB_API_KEY = ""
$script:FFmpegPath   = ""
$script:FFprobePath  = ""

function Save-APIKey {
    param([string]$Key)
    if (-not (Test-Path $script:ConfigDir)) { New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null }
    Set-Content -Path $script:ConfigFile -Value ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Key))) -Encoding UTF8
}
function Load-APIKey {
    if (Test-Path $script:ConfigFile) {
        try { return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Get-Content $script:ConfigFile -Raw).Trim())) }
        catch { return "" }
    }
    return ""
}
function Save-FFmpegPath {
    param([string]$Path)
    if (-not (Test-Path $script:ConfigDir)) { New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null }
    Set-Content -Path $script:FFmpegFile -Value ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Path))) -Encoding UTF8
}
function Load-FFmpegPath {
    if (Test-Path $script:FFmpegFile) {
        try { return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Get-Content $script:FFmpegFile -Raw).Trim())) }
        catch { return "" }
    }
    return ""
}
function Set-FFmpegPaths {
    param([string]$FfmpegExe)
    $script:FFmpegPath  = $FfmpegExe
    $script:FFprobePath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($FfmpegExe), "ffprobe.exe")
}

# ─────────────────────────────────────────────────────────────────────────────
#  AUDIO DETECTION
# ─────────────────────────────────────────────────────────────────────────────
function Get-AudioInfo {
    param([string]$FilePath)
    if (-not $script:FFprobePath -or -not (Test-Path $script:FFprobePath)) {
        return @{ Label = "—"; IsHeAac = $false; Bitrate = 0; Channels = 0 }
    }
    try {
        # ffprobe: file path must be LAST, no -i flag needed
        $rawLines = & $script:FFprobePath `
            "-v" , "quiet" `
            , "-select_streams" , "a:0" `
            , "-show_entries"   , "stream=codec_name,profile,bit_rate,channels" `
            , "-of"             , "default=noprint_wrappers=1" `
            , $FilePath  2>&1

        $out = ($rawLines | Where-Object { $_ -is [string] }) -join "`n"

        $codec    = if ($out -match '(?m)codec_name=(\S+)')  { $Matches[1].Trim().ToLower() } else { "unknown" }
        $profile  = if ($out -match '(?m)profile=(.+)')      { $Matches[1].Trim() }           else { "" }
        $bitrate  = if ($out -match '(?m)bit_rate=(\d+)')    { [int64]$Matches[1] }            else { 0 }
        $channels = if ($out -match '(?m)channels=(\d+)')    { [int]$Matches[1] }              else { 0 }

        $isHeAac = $false
        if ($codec -eq "aac") {
            if ($profile -match "HE-AAC" -or $profile -match "HE-AACv2" -or $profile -match "aac_he") {
                $isHeAac = $true
            } elseif (($profile -eq "" -or $profile -eq "unknown" -or $profile -eq "N/A") -and
                      $bitrate -gt 0 -and $bitrate -lt 80000) {
                $isHeAac = $true
            }
        }

        $label = switch ($codec) {
            "aac"     { if ($isHeAac) { "HE-AAC" } else { "AAC LC" } }
            "ac3"     { "AC3" }
            "eac3"    { "EAC3" }
            "dts"     { "DTS" }
            "truehd"  { "TrueHD" }
            "mp3"     { "MP3" }
            "flac"    { "FLAC" }
            "opus"    { "Opus" }
            "vorbis"  { "Vorbis" }
            "unknown" { "?" }
            default    { $codec.ToUpper() }
        }
        return @{ Label = $label; IsHeAac = $isHeAac; Bitrate = $bitrate; Channels = $channels }
    } catch {
        return @{ Label = "Err"; IsHeAac = $false; Bitrate = 0; Channels = 0 }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  HE-AAC FIX
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-HeAacFix {
    param([string]$FilePath)
    if (-not $script:FFmpegPath -or -not (Test-Path $script:FFmpegPath)) {
        Write-Log "  [Audio Fix] FFmpeg not configured — set path in Connect menu." "Orange"
        return @{ Success=$false; FailReason="FFmpeg not configured" }
    }
    if (-not (Test-Path -LiteralPath $FilePath)) {
        Write-Log "  [Error] File not found: $FilePath" "Red"
        return @{ Success=$false; FailReason="File not found" }
    }

    $dir      = [System.IO.Path]::GetDirectoryName($FilePath)
    $fname    = [System.IO.Path]::GetFileName($FilePath)
    $tempPath = [System.IO.Path]::Combine($dir, "__heaac_fix_$fname")
    $logFile  = [System.IO.Path]::Combine($env:TEMP, "__heaac_log_$([System.IO.Path]::GetFileNameWithoutExtension($fname)).txt")

    # ── Pre-conversion probe ──────────────────────────────────────────────────
    try {
        $probeOut = & $script:FFprobePath "-v","quiet","-show_streams","-show_format","-print_format","flat",$FilePath 2>&1 | Out-String
        $aCodec   = if ($probeOut -match 'streams\.stream\.0\.codec_name="([^"]+)"')  { $Matches[1] } else { "unknown" }
        $aProfile = if ($probeOut -match 'streams\.stream\.0\.profile="([^"]+)"')     { $Matches[1] } else { "unknown" }
        $aBitrate = if ($probeOut -match 'streams\.stream\.0\.bit_rate="([^"]+)"')    { $Matches[1] } else { "unknown" }
        $duration = if ($probeOut -match 'format\.duration="([^"]+)"')                { [math]::Round([double]$Matches[1],1) } else { "?" }
        $fmtName  = if ($probeOut -match 'format\.format_name="([^"]+)"')             { $Matches[1] } else { "unknown" }
        Write-Log "  Input  : $fname" "Gray"
        Write-Log "  Format : $fmtName   Duration: ${duration}s" "Gray"
        Write-Log "  Audio  : codec=$aCodec   profile=$aProfile   bitrate=$aBitrate" "Gray"
    } catch {
        Write-Log "  [Probe] Could not read metadata: $($_.Exception.Message)" "Yellow"
    }
    Write-Log "  Command: ffmpeg -i `"$fname`" -c:v copy -c:a aac -ac 2 -b:a 192k" "Gray"

    # ── Run FFmpeg — stderr redirected to temp file (ps2exe compatible) ───────
    try {
        $psi                    = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName           = $script:FFmpegPath
        $psi.Arguments          = "-i `"$FilePath`" -c:v copy -c:a aac -ac 2 -b:a 192k -y `"$tempPath`""
        $psi.UseShellExecute    = $false
        $psi.CreateNoWindow     = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardOutput = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $script:CurrentFFmpegProc = $proc

        # Read stderr on a background thread to avoid pipe-buffer deadlock
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        # Keep UI alive while waiting
        while (-not $proc.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
        }
        $proc.WaitForExit()
        $exitCode  = $proc.ExitCode
        $stderrOut = $stderrTask.Result

        # Log last 8 meaningful ffmpeg lines
        $ffLines = ($stderrOut -split "`n") | Where-Object { $_.Trim() -ne "" }
        $tail    = if ($ffLines.Count -gt 8) { $ffLines[-8..-1] } else { $ffLines }
        foreach ($line in $tail) {
            $t = $line.TrimEnd()
            if     ($t -match "^(Error|Invalid|No such|Unable|Cannot|Failed|Could not)") { Write-Log "  ffmpeg: $t" "Red" }
            elseif ($t -match "^(Warning|Conversion)")                                   { Write-Log "  ffmpeg: $t" "Yellow" }
            else                                                                          { Write-Log "  ffmpeg: $t" "Gray" }
        }
        $exitLabel = if ($exitCode -eq 0) { "LightGreen" } else { "Red" }
        Write-Log "  Exit code: $exitCode" $exitLabel

        if ($exitCode -eq 0 -and (Test-Path -LiteralPath $tempPath)) {
            $inSize  = [math]::Round((Get-Item -LiteralPath $FilePath).Length / 1MB, 2)
            $outSize = [math]::Round((Get-Item -LiteralPath $tempPath).Length / 1MB, 2)
            Write-Log "  Size: ${inSize} MB  ->  ${outSize} MB" "Gray"
            Remove-Item -LiteralPath $FilePath -Force
            Move-Item   -LiteralPath $tempPath -Destination $FilePath -Force
            Write-Log "  Conversion successful — file replaced." "LightGreen"
            return @{ Success=$true; FailReason="" }
        } else {
            $hint = switch ($exitCode) {
                1    { "General FFmpeg error — see log above" }
                -1414549496 { "Invalid data — file may be corrupted or codec mismatch" }
                -1094995529 { "Invalid argument — check file path for special characters" }
                default     { "FFmpeg exit code $exitCode" }
            }
            # Pull the most relevant error line from stderr for the report
            $errLine = ($ffLines | Where-Object { $_ -match "^(Error|Invalid|No such|Unable|Cannot|Failed)" } | Select-Object -Last 1)
            $detail  = if ($errLine) { $errLine.Trim() } else { $hint }
            Write-Log "  FFmpeg failed (exit $exitCode) — $detail" "Red"
            if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
            return @{ Success=$false; FailReason="Exit $exitCode — $detail" }
        }
    } catch {
        $msg = $_.Exception.Message
        Write-Log "  [Exception] $msg" "Red"
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        return @{ Success=$false; FailReason="Exception: $msg" }
    } finally {
        if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch {} }
        $script:CurrentFFmpegProc = $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  TMDB HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-TMDB {
    param([string]$Path, [hashtable]$Query = @{})
    $qs  = ($Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([Uri]::EscapeDataString($_.Value))" }) -join "&"
    $url = "https://api.themoviedb.org/3$Path`?api_key=$script:TMDB_API_KEY"
    if ($qs) { $url += "&$qs" }
    try { return Invoke-RestMethod -Uri $url -UseBasicParsing -ErrorAction Stop } catch { return $null }
}
function Search-TMDB {
    param([string]$Query,[string]$Type)
    $r = Invoke-TMDB "/search/$Type" @{query=$Query}
    if ($r -and $r.results) { return $r.results }
    return @()
}
function Invoke-AniList {
    param([string]$Search,[string]$Type="ANIME")
    $query = @'
query ($search: String, $type: MediaType) {
  Page(perPage: 10) {
    media(search: $search, type: $type, sort: SEARCH_MATCH) {
      id
      format
      title {
        romaji
        english
        native
        userPreferred
      }
      startDate {
        year
      }
    }
  }
}
'@
    $body = @{ query = $query; variables = @{ search = $Search; type = $Type } }
    try {
        return Invoke-RestMethod -Uri 'https://graphql.anilist.co' -Method Post -ContentType 'application/json' -Body (ConvertTo-Json $body -Depth 5) -UseBasicParsing -ErrorAction Stop
    } catch {
        return $null
    }
}
function Search-AniList {
    param([string]$Query)
    if (-not $Query -or $Query.Trim().Length -eq 0) { return @() }
    $r = Invoke-AniList $Query 'ANIME'
    if ($r -and $r.data -and $r.data.Page -and $r.data.Page.media) { return $r.data.Page.media }
    return @()
}
function Get-AniListMediaTitle {
    param($Media)
    if ($Media -and $Media.title) {
        if ($Media.title.userPreferred) { return $Media.title.userPreferred }
        if ($Media.title.english)       { return $Media.title.english }
        if ($Media.title.romaji)        { return $Media.title.romaji }
        if ($Media.title.native)        { return $Media.title.native }
    }
    return ""
}
function Get-AniListYear {
    param($Media)
    if ($Media -and $Media.startDate -and $Media.startDate.year) {
        return [string]$Media.startDate.year
    }
    return ""
}
function Get-TMDBById {
    param([string]$Id,[string]$Type)
    if ($Id -match '^tt\d+') {
        $find = Invoke-TMDB "/find/$Id" @{external_source="imdb_id"}
        if ($find) {
            if ($Type -eq 'tv'    -and $find.tv_results)    { return $find.tv_results[0] }
            if ($Type -eq 'movie' -and $find.movie_results) { return $find.movie_results[0] }
        }
        return $null
    }
    return (Invoke-TMDB "/$Type/$Id")
}
function Get-EpisodeName {
    param([int]$ShowId,[int]$Season,[int]$Episode)
    $ep = Invoke-TMDB "/tv/$ShowId/season/$Season/episode/$Episode"
    if ($ep -and $ep.name) { return $ep.name }
    return $null
}

# Season episode cache — avoids one TMDB call per file
$script:SeasonCache = @{}

function Get-SeasonEpisodes {
    param([int]$ShowId,[int]$Season)
    # Use string key to avoid int/string hashtable mismatch
    $key = [string]$ShowId + '-' + [string]$Season
    if ($script:SeasonCache.ContainsKey($key)) { return $script:SeasonCache[$key] }
    $map = @{}
    if ($ShowId -gt 0) {
        $data = Invoke-TMDB "/tv/$ShowId/season/$Season"
        if ($data -and $data.episodes) {
            foreach ($ep in $data.episodes) {
                $n = 0
                if ($ep.episode_number -ne $null) { $n = [int]$ep.episode_number }
                if ($n -gt 0) { $map[$n] = $ep }
            }
        }
    }
    # Always cache (even empty) so we don't hammer TMDB on repeat calls
    $script:SeasonCache[$key] = $map
    return $map
}

function Get-SeasonEpisodeFromPath {
    # Returns hashtable {Season, Episode} parsed from filename or parent folder.
    # Season and Episode are [int]; Episode may be $null if only season is found.
    # Returns $null if nothing is detectable.
    param([string]$FilePath)
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $dirName  = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($FilePath))

    # Primary: S01E01 / S1E1 — non-letter before S guards against mid-word false match
    if ($fileName -match '(?i)(?:^|[^a-zA-Z])S(\d{1,2})E(\d{1,3})') {
        return @{ Season=[int]$Matches[1]; Episode=[int]$Matches[2] }
    }
    # Fallback A: 1x01 / 2x03 — require 2+ digit episode to avoid false matches
    if ($fileName -match '(?i)(?:^|[^0-9])(\d{1,2})x(\d{2,3})(?:[^0-9]|$)') {
        return @{ Season=[int]$Matches[1]; Episode=[int]$Matches[2] }
    }
    # Fallback B: parent folder exactly "Season 2", "Season 02", "S02", "S2"
    if ($dirName -match '(?i)^season[\s._-]*(\d{1,2})$') {
        return @{ Season=[int]$Matches[1]; Episode=$null }
    }
    if ($dirName -match '(?i)^[Ss](\d{1,2})$') {
        return @{ Season=[int]$Matches[1]; Episode=$null }
    }
    # Fallback C: "Season N" anywhere in parent folder name
    if ($dirName -match '(?i)season[\s._-]*(\d{1,2})') {
        return @{ Season=[int]$Matches[1]; Episode=$null }
    }
    return $null
}
function Get-ShowNameFromFilename {
    # Strips season/episode markers, years, codec tags and common junk from a
    # filename to produce a clean candidate show name for TMDB search.
    param([string]$FilePath)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)

    # Remove S##E## and everything after it
    $name = $name -replace '(?i)[\s._-]*S\d{1,2}E\d{1,3}.*', ''
    # Remove 1x01 style and everything after
    $name = $name -replace '(?i)[\s._-]*\d{1,2}x\d{2,3}.*', ''
    # Remove standalone 4-digit years like (2019) or .2019.
    $name = $name -replace '[\s._(-]*\b(19|20)\d{2}\b[\s._)]*', ' '
    # Remove common release/codec tags
    $name = $name -replace '(?i)\b(1080p|720p|480p|2160p|4k|uhd|bluray|blu-ray|webrip|web-dl|hdtv|dvdrip|x264|x265|hevc|avc|aac|ac3|eac3|dts|hdr|sdr|remux|proper|repack|extended|theatrical|directors\.cut)\b.*', ''
    # Replace separators (dots, underscores, dashes used as spaces) with spaces
    $name = $name -replace '[._]', ' '
    # Collapse multiple spaces and trim
    $name = ($name -replace '\s+', ' ').Trim(' -')
    return $name
}

function Get-MovieCandidatesFromPath {
    param([string]$FilePath)

    $fileCandidate = Get-ShowNameFromFilename $FilePath
    $parentDir = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($FilePath))
    $folderCandidate = $null
    if ($parentDir -and $parentDir -notmatch '(?i)^(season[\s._-]*\d|S\d{1,2}$)' -and $parentDir.Length -gt 3) {
        $folderCandidate = ($parentDir -replace '[\s._(-]*\b(19|20)\d{2}\b[\s._)]*', ' ').Trim(' -._')
    }

    $candidates = @()
    if ($fileCandidate -and $fileCandidate.Length -gt 1) { $candidates += $fileCandidate }
    if ($folderCandidate -and $folderCandidate.Length -gt 1 -and $folderCandidate -ne $fileCandidate) { $candidates += $folderCandidate }
    return $candidates
}

function Get-TopMatchCandidate {
    param([string]$Candidate,[string]$Title)
    $norm1 = ($Candidate -replace '[^a-z0-9]','').ToLower()
    $norm2 = ($Title -replace '[^a-z0-9]','').ToLower()
    return ($norm1 -eq $norm2) -or ($norm2.StartsWith($norm1)) -or ($norm1.StartsWith($norm2))
}

function Get-ShowCandidatesFromPath {
    param([string]$FilePath)
    $fileCandidate = Get-ShowNameFromFilename $FilePath
    $parentDir = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($FilePath))
    $folderCandidate = $null
    if ($parentDir -and $parentDir -notmatch '(?i)^(season[\s._-]*\d|S\d{1,2}$)' -and $parentDir.Length -gt 3) {
        $folderCandidate = ($parentDir -replace '[\s._(-]*\b(19|20)\d{2}\b[\s._)]*', ' ').Trim(' -._')
    }

    $candidates = @()
    if ($fileCandidate -and $fileCandidate.Length -gt 1) { $candidates += $fileCandidate }
    if ($folderCandidate -and $folderCandidate.Length -gt 1 -and $folderCandidate -ne $fileCandidate) { $candidates += $folderCandidate }
    return $candidates
}

function Matches-ShowByName {
    param([string]$FilePath,[string]$ShowName)
    foreach ($candidate in Get-ShowCandidatesFromPath $FilePath) {
        if (Get-TopMatchCandidate $candidate $ShowName) { return $true }
    }
    return $false
}

function Matches-MovieByTitle {
    param([string]$FilePath,[string]$Title)
    foreach ($candidate in Get-MovieCandidatesFromPath $FilePath) {
        if (Get-TopMatchCandidate $candidate $Title) { return $true }
    }
    return $false
}

function Find-TMDBMovieMatch {
    param([string]$FilePath)
    $useTMDB = [bool]$script:TMDB_API_KEY

    foreach ($candidate in Get-MovieCandidatesFromPath $FilePath) {
        if ($useTMDB) {
            $results = Search-TMDB $candidate 'movie'
            if ($results -and $results.Count -gt 0) {
                $top = $results[0]
                $title = if ($top.title) { $top.title } else { $top.original_title }
                if (Get-TopMatchCandidate $candidate $title) {
                    return $top
                }
            }
        }

        Write-Log "  Searching AniList for candidate: `"$candidate`"..." "Gray"
        $aResults = Search-AniList $candidate
        foreach ($item in $aResults) {
            if (-not $item.format) { continue }
            if ($item.format -notin @('MOVIE','OVA','ONA','SPECIAL')) { continue }
            $title = Get-AniListMediaTitle $item
            if (-not $title) { continue }
            if (Get-TopMatchCandidate $candidate $title) {
                return @{ title = $title; original_title = $title; release_date = Get-AniListYear $item; source = 'AniList' }
            }
        }
    }
    return $null
}

function Find-TMDBShowMatch {
    param([string]$FilePath)
    $useTMDB = [bool]$script:TMDB_API_KEY

    $fileCandidate = Get-ShowNameFromFilename $FilePath
    $parentDir = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($FilePath))
    $folderCandidate = $null
    if ($parentDir -and $parentDir -notmatch '(?i)^(season[\s._-]*\d|S\d{1,2}$)' -and $parentDir.Length -gt 3) {
        $folderCandidate = ($parentDir -replace '[\s._(-]*\b(19|20)\d{2}\b[\s._)]*', ' ').Trim(' -._')
    }

    $candidates = @()
    if ($fileCandidate -and $fileCandidate.Length -gt 1) { $candidates += $fileCandidate }
    if ($folderCandidate -and $folderCandidate.Length -gt 1 -and $folderCandidate -ne $fileCandidate) { $candidates += $folderCandidate }

    foreach ($candidate in $candidates) {
        if ($useTMDB) {
            # Try TV first
            $results = Search-TMDB $candidate 'tv'
            if ($results -and $results.Count -gt 0) {
                $top = $results[0]
                $topName = if ($top.name) { $top.name } else { $top.original_name }
                if (Get-TopMatchCandidate $candidate $topName) {
                    return $top
                }
            }

            # Fallback to movie search (for Anime movies or specials)
            $results = Search-TMDB $candidate 'movie'
            if ($results -and $results.Count -gt 0) {
                $top = $results[0]
                $title = if ($top.title) { $top.title } else { $top.original_title }
                if (Get-TopMatchCandidate $candidate $title) {
                    # Convert movie to show-like object for compatibility
                    return @{
                        id = $top.id
                        name = $title
                        original_name = $top.original_title
                        first_air_date = $top.release_date  # Use release_date as first_air_date
                    }
                }
            }
        }

        Write-Log "  Searching AniList for candidate: `"$candidate`"..." "Gray"
        $aResults = Search-AniList $candidate
        foreach ($item in $aResults) {
            $title = Get-AniListMediaTitle $item
            if (-not $title) { continue }
            if ($item.format -eq 'MOVIE') { continue }
            if (Get-TopMatchCandidate $candidate $title) {
                return @{ 
                    id = 0
                    name = $title
                    original_name = $title
                    first_air_date = if ($item.startDate -and $item.startDate.year) { "$($item.startDate.year)-01-01" } else { "" }
                    source = 'AniList'
                }
            }
        }
    }
    return $null
}

function Invoke-AutoDetectShow {
    # Called after files are loaded in TV mode. Auto-detects show name for each file
    # using TMDB and AniList, and populates accordingly.
    if (-not $rbTV.Checked) { return }
    if ($script:TVShowData -or $script:CachedTVEntries) { return }   # already detected
    if ($script:SelectedFiles.Count -eq 0) { return }
    Write-Log "-- TV Show Auto-Detect: scanning $($script:SelectedFiles.Count) file(s) --" "Cyan"

    $entries = New-Object System.Collections.Generic.List[hashtable]
    $showGroups = @{}
    $matched = 0
    $total = $script:SelectedFiles.Count

    foreach ($f in $script:SelectedFiles) {
        $fn = [System.IO.Path]::GetFileName($f)
        $showData = Find-TMDBShowMatch $f
        if ($showData) {
            $showName = if ($showData.name) { $showData.name } else { $showData.original_name }
            $showYear = Get-Year $showData.first_air_date
            $tmdbId = $showData.id
            Write-Log "  ✓ $fn -> $showName ($showYear)" "LightGreen"
            $entries.Add(@{File=$f; ShowData=$showData; ShowName=$showName; ShowYear=$showYear; TMDBId=$tmdbId})
            $key = "$showName|$showYear|$tmdbId"
            if (-not $showGroups.ContainsKey($key)) { $showGroups[$key] = @() }
            $showGroups[$key] += $f
            $matched++
        } else {
            Write-Log "  ✗ $fn — no TMDB match found" "Yellow"
        }
    }

    Write-Log "" "Gray"
    if ($matched -eq 0) {
        $script:CachedTVEntries = $null
        $lblShowPicked.Text = "No show auto-detect matches found"
        $lblShowPicked.ForeColor = [System.Drawing.Color]::FromArgb(220,180,80)
        Write-Log "Summary: No auto-detect matches found — manual matching required." "Yellow"
    } elseif ($showGroups.Count -eq 1) {
        # All files matched the same show
        $script:TVShowData = $entries[0].ShowData
        $script:SeasonCache = @{}
        $lblShowPicked.Text = "$($entries[0].ShowName) ($($entries[0].ShowYear))"
        $lblShowPicked.ForeColor = [System.Drawing.Color]::FromArgb(100,220,150)
        Write-Log "Summary: All $matched file(s) matched `"$($entries[0].ShowName)`" — single show mode." "LightGreen"
    } else {
        # Multiple different shows detected
        $script:CachedTVEntries = $entries
        $lblShowPicked.Text = "Multiple shows detected ($($showGroups.Count) shows)"
        $lblShowPicked.ForeColor = [System.Drawing.Color]::FromArgb(100,220,150)
        Write-Log "Summary: $matched file(s) auto-detected across $($showGroups.Count) different show(s) — multi-show mode." "LightGreen"
    }

    Update-Preview
}

function Invoke-AutoDetectMovie {
    if (-not $rbMovie.Checked) { return }
    if ($script:SelectedFiles.Count -eq 0) { return }
    if (-not $script:TMDB_API_KEY) { return }

    Write-Log "-- Movie Auto-Detect: scanning $($script:SelectedFiles.Count) file(s) --" "Cyan"

    $entries = New-Object System.Collections.Generic.List[hashtable]
    $matched = 0
    $total = $script:SelectedFiles.Count

    foreach ($f in $script:SelectedFiles) {
        $fn = [System.IO.Path]::GetFileName($f)
        $item = Find-TMDBMovieMatch $f
        if ($item) {
            if ($item.title) { $title = $item.title } else { $title = $item.original_title }
            $year = Get-Year $item.release_date
            Write-Log "  ✓ $fn -> $title ($year)" "LightGreen"
            $entries.Add(@{File=$f;Title=$title;Year=$year})
            $matched++
        } else {
            Write-Log "  ✗ $fn — no TMDB match found" "Yellow"
        }
    }

    Write-Log "" "Gray"
    if ($matched -gt 0) {
        $script:CachedMovieEntries = $entries
        $lblMovieMatched.Text = "Auto-detected $matched of $total file(s)"
        $lblMovieMatched.ForeColor = [System.Drawing.Color]::FromArgb(100,220,150)
        Write-Log "Summary: $matched of $total file(s) auto-detected — preview updated." "LightGreen"
    } else {
        $script:CachedMovieEntries = $null
        $lblMovieMatched.Text = "No movie auto-detect matches found"
        $lblMovieMatched.ForeColor = [System.Drawing.Color]::FromArgb(220,180,80)
        Write-Log "Summary: No auto-detect matches found — manual matching required." "Yellow"
    }

    Update-Preview
}

function Test-IsSeasonFolder {
    # Returns $true if the given folder name looks like a season folder,
    # e.g. "Season 1", "Season 01", "Season1", "S01", "S1"
    param([string]$FolderName)
    return ($FolderName -match '(?i)^season[\s._-]*\d{1,2}$') -or
           ($FolderName -match '(?i)^[Ss]\d{1,2}$')
}

function Sanitize-Filename {
    param([string]$Name)
    $Name = $Name -replace "[$([regex]::Escape([System.IO.Path]::GetInvalidFileNameChars()-join''))]",''
    return $Name.Trim()
}
function Get-Year {
    param([string]$DateStr)
    if ($DateStr -and $DateStr.Length -ge 4) { return $DateStr.Substring(0,4) }
    return "????"
}

# ─────────────────────────────────────────────────────────────────────────────
#  RENAME ENGINE
# ─────────────────────────────────────────────────────────────────────────────
function Start-RenameJob {
    param([string]$Mode,[string[]]$Files,[hashtable]$TVOptions,[hashtable]$MovieOptions,
          [System.Windows.Forms.RichTextBox]$LogBox,[System.Windows.Forms.ProgressBar]$Bar,[bool]$DryRun,[bool]$RenameInPlace=$false)

    function Append-Log { param([string]$Msg,[string]$Color="White")
        $LogBox.SelectionStart=$LogBox.TextLength; $LogBox.SelectionLength=0
        $LogBox.SelectionColor=Get-LogColor $Color; $LogBox.AppendText("$Msg`n")
        $atBottom = ($LogBox.SelectionStart -ge ($LogBox.TextLength - 2))
        if ($atBottom) { $LogBox.ScrollToCaret() }
    }

    if (-not $DryRun) { $script:UndoStack.Clear() }
    $total=$Files.Count; $done=0

    if ($Mode -eq 'TV') {
        if ($TVOptions.Entries) {
            # Multi-show mode
            Append-Log "-- TV Mode (Multi-Show)$(if($RenameInPlace){' (Rename in Place)'}) --" "Cyan"
            foreach ($entry in $TVOptions.Entries) {
                $f = $entry.File
                $ext = [System.IO.Path]::GetExtension($f)
                $showName = Sanitize-Filename $entry.ShowName
                $showYear = $entry.ShowYear
                $tmdbId = [int]([string]$entry.TMDBId)
                $manualOverride = $TVOptions.ManualOverride -as [bool]
                $manualSeason = $TVOptions.Season -as [int]
                $startEp = $TVOptions.StartEp -as [int]

                $fileName = [System.IO.Path]::GetFileName($f)
                $det = Get-SeasonEpisodeFromPath $f

                if ($manualOverride) {
                    $season = $manualSeason
                    $epNum = $startEp
                    $startEp++
                } else {
                    # Season: explicit season can be overridden if manual override is enabled
                    $season = if ($det -and $det.Season) {
                        if ($manualOverride) { $manualSeason } else { $det.Season }
                    } else {
                        $manualSeason
                    }

                    # Episode: from filename > startEp (no sequential for multi-show)
                    $epNum = if ($det -and $det.Episode) { $det.Episode } else { $startEp }
                }

                $epMap = $script:SeasonCache[([string]$tmdbId + '-' + [string]$season)]
                $epObj = if ($epMap -and $epMap.ContainsKey($epNum)) { $epMap[$epNum] } else { $null }
                $epName = if ($epObj -and $epObj.name) { Sanitize-Filename $epObj.name } else { "Episode $epNum" }
                $epStr = "S{0:D2}E{1:D2}" -f $season, $epNum
                $newName = if ($TVOptions.IncludeName) { "$showName - $epStr - $epName$ext" } else { "$epStr - $epName$ext" }

                $fileDir = [System.IO.Path]::GetDirectoryName($f)
                $parentName = [System.IO.Path]::GetFileName($fileDir)
                $alreadyInSeasonFolder = Test-IsSeasonFolder $parentName

                if ($RenameInPlace -or $alreadyInSeasonFolder) {
                    $destDir = $fileDir
                    $destPath = [System.IO.Path]::Combine($destDir, $newName)
                    if ($alreadyInSeasonFolder -and -not $RenameInPlace) {
                        Append-Log "  [already in season folder: $parentName — renaming in place]" "Gray"
                    }
                } else {
                    $destDir = [System.IO.Path]::Combine($fileDir, "$showName ($showYear)", ("Season {0:D2}" -f $season))
                    $destPath = [System.IO.Path]::Combine($destDir, $newName)
                }

                if ($fileName -eq $newName -and $fileDir -eq $destDir) {
                    Append-Log "[$epStr] $fileName" "Gray"
                    Append-Log "      ✔ already correct — skipped" "Gray"
                } else {
                    Append-Log "[$epStr] $fileName" "Gray"
                    Append-Log "      -> $newName" "LightGreen"
                    if (-not $DryRun) {
                        try {
                            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                            Move-Item -LiteralPath $f -Destination $destPath -Force
                            $script:UndoStack.Push(@{From=$destPath;To=$f;Dir=$destDir})
                        } catch { Append-Log "  ERROR: $($_.Exception.Message)" "Red" }
                    }
                }
                $done++; $Bar.Value = [int](($done / $total) * 100); $Bar.Refresh(); [System.Windows.Forms.Application]::DoEvents()
            }
        } else {
            # Single show mode
            $showName       = Sanitize-Filename $TVOptions.ShowName
            $showYear       = $TVOptions.ShowYear
            $tmdbId         = [int]([string]($TVOptions.ShowTMDBId))
            $fallbackSeason = $TVOptions.Season -as [int]
            $startEp        = $TVOptions.StartEp -as [int]
            $showName       = Sanitize-Filename $TVOptions.ShowName
            $showYear       = $TVOptions.ShowYear
            $tmdbId         = [int]([string]($TVOptions.ShowTMDBId))
            $fallbackSeason = $TVOptions.Season -as [int]
            $startEp        = $TVOptions.StartEp -as [int]
            $manualOverride = $TVOptions.ManualOverride -as [bool]

            Append-Log "-- TV Mode: $showName ($showYear)$(if($RenameInPlace){' (Rename in Place)'}) --" "Cyan"

            # Pre-cache every season referenced by the file list
            $seasonsNeeded = @{}
            foreach ($f in $Files) {
                $det = Get-SeasonEpisodeFromPath $f
                $s   = if ($det -and $det.Season) {
                         if ($manualOverride) { $fallbackSeason } else { $det.Season }
                       } else {
                         $fallbackSeason
                       }
                $seasonsNeeded[$s] = $true
            }
            foreach ($s in @($seasonsNeeded.Keys)) {
                Append-Log "  Fetching Season $s from TMDB..." "Gray"
                Get-SeasonEpisodes $tmdbId $s | Out-Null
            }

            # Sequential fallback counter per season
            $seqCounters = @{}

            foreach ($f in $Files) {
                $fileName = [System.IO.Path]::GetFileName($f)
                $ext      = [System.IO.Path]::GetExtension($f)
                $det      = Get-SeasonEpisodeFromPath $f

                if ($manualOverride) {
                $season = $fallbackSeason
                if (-not $seqCounters.ContainsKey($season)) { $seqCounters[$season] = $startEp }
                $epNum = $seqCounters[$season]
                $seqCounters[$season]++
            } else {
                # Season: explicit season can be overridden if manual override is enabled
                $season = if ($det -and $det.Season) { $det.Season } else { $fallbackSeason }

                # Episode: filename > sequential counter per season
                if (-not $seqCounters.ContainsKey($season)) { $seqCounters[$season] = $startEp }
                $epNum = if ($det -and $det.Episode) {
                    $det.Episode
                } else {
                    $c = $seqCounters[$season]; $seqCounters[$season]++; $c
                }
            }

                $epMap   = $script:SeasonCache[([string]$tmdbId + '-' + [string]$season)]
                $epObj   = if ($epMap -and $epMap.ContainsKey($epNum)) { $epMap[$epNum] } else { $null }
                $epName  = if ($epObj -and $epObj.name) { Sanitize-Filename $epObj.name } else { "Episode $epNum" }
                $epStr   = "S{0:D2}E{1:D2}" -f $season,$epNum
                $newName = if($TVOptions.IncludeName){"$showName - $epStr - $epName$ext"}else{"$epStr - $epName$ext"}

                $fileDir    = [System.IO.Path]::GetDirectoryName($f)
                $parentName = [System.IO.Path]::GetFileName($fileDir)
                $alreadyInSeasonFolder = Test-IsSeasonFolder $parentName

                if ($RenameInPlace -or $alreadyInSeasonFolder) {
                    # File is already inside a season folder (or user chose rename-in-place)
                    # — just rename it where it sits, no new folders created
                    $destDir  = $fileDir
                    $destPath = [System.IO.Path]::Combine($destDir, $newName)
                    if ($alreadyInSeasonFolder -and -not $RenameInPlace) {
                        Append-Log "  [already in season folder: $parentName — renaming in place]" "Gray"
                    }
                } else {
                    $destDir  = [System.IO.Path]::Combine($fileDir, "$showName ($showYear)", ("Season {0:D2}" -f $season))
                    $destPath = [System.IO.Path]::Combine($destDir, $newName)
                }

                if ($fileName -eq $newName -and $fileDir -eq $destDir) {
                    Append-Log "[$epStr] $fileName" "Gray"
                    Append-Log "      ✔ already correct — skipped" "Gray"
                } else {
                    Append-Log "[$epStr] $fileName" "Gray"
                    Append-Log "      -> $newName" "LightGreen"
                    if (-not $DryRun) {
                        try {
                            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                            Move-Item -LiteralPath $f -Destination $destPath -Force
                            $script:UndoStack.Push(@{From=$destPath;To=$f;Dir=$destDir})
                        } catch { Append-Log "  ERROR: $($_.Exception.Message)" "Red" }
                    }
                }
                $done++; $Bar.Value=[int](($done/$total)*100); $Bar.Refresh(); [System.Windows.Forms.Application]::DoEvents()
            }
        }
    } else {
        Append-Log "-- Movie Mode$(if($RenameInPlace){' (Rename in Place)'}) --" "Cyan"
        foreach ($entry in $MovieOptions.Entries) {
            $f=$entry.File; $ext=[System.IO.Path]::GetExtension($f)
            $title=Sanitize-Filename $entry.Title; $year=$entry.Year
            $fileBaseDir=[System.IO.Path]::GetDirectoryName($f)
            
            if ($RenameInPlace) {
                $newName="$title ($year)$ext"
                $destDir=$fileBaseDir
                $destPath=[System.IO.Path]::Combine($destDir,$newName)
            } else {
                $folderName="$title ($year)"; $newName="$folderName$ext"
                $destDir=[System.IO.Path]::Combine($fileBaseDir,$folderName)
                $destPath=[System.IO.Path]::Combine($destDir,$newName)
            }
            $movieFileName = [System.IO.Path]::GetFileName($f)
            if ($movieFileName -eq $newName -and $fileBaseDir -eq $destDir) {
                Append-Log "$movieFileName" "Gray"
                Append-Log "  ✔ already correct — skipped" "Gray"
            } else {
                Append-Log "$movieFileName" "Gray"
                if ($RenameInPlace) {
                    Append-Log "  -> $newName" "LightGreen"
                } else {
                    Append-Log "  -> $folderName\$newName" "LightGreen"
                }
                if (-not $DryRun) {
                    try {
                        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                        Move-Item -LiteralPath $f -Destination $destPath -Force
                        $script:UndoStack.Push(@{From=$destPath;To=$f;Dir=$destDir})
                    } catch { Append-Log "  ERROR: $($_.Exception.Message)" "Red" }
                }
            }
            $done++; $Bar.Value=[int](($done/$total)*100); $Bar.Refresh(); [System.Windows.Forms.Application]::DoEvents()
        }
    }
    # Count skipped (already correct) from log
    $skippedCount = 0
    $logText = $LogBox.Text
    $skippedCount = ([regex]::Matches($logText, '✔ already correct')).Count
    $renamedCount = $done - $skippedCount
    if ($DryRun) {
        $finalMsg = "Preview complete — $done file(s) checked, $skippedCount already correct."
    } else {
        $finalMsg = "Done — $renamedCount file(s) renamed, $skippedCount already correct (skipped). Undo available."
    }
    Append-Log $finalMsg "Yellow"
    $Bar.Value=100; $Bar.Refresh()
}

# ─────────────────────────────────────────────────────────────────────────────
#  DUPLICATE SCANNER
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-DuplicateScan {
    param(
        [string[]]$FilePaths,
        [string]$Mode,           # 'TV' or 'Movie'
        [System.Windows.Forms.RichTextBox]$LogBox
    )

    function Dup-Log { param([string]$Msg,[string]$Color="White")
        $LogBox.SelectionStart=$LogBox.TextLength; $LogBox.SelectionLength=0
        $LogBox.SelectionColor=Get-LogColor $Color; $LogBox.AppendText("$Msg`n")
        $atBottom = ($LogBox.SelectionStart -ge ($LogBox.TextLength - 2))
        if ($atBottom) { $LogBox.ScrollToCaret() }
    }

    # Scan the actual directories where files now live (post-rename)
    # Build a list of all media files in every unique directory touched
    $dirsToScan = $FilePaths | ForEach-Object {
        [System.IO.Path]::GetDirectoryName($_)
    } | Sort-Object -Unique

    $allFiles = @()
    $mediaExts = @('.mkv','.mp4','.avi','.m4v','.mov','.wmv')
    foreach ($dir in $dirsToScan) {
        if (Test-Path $dir) {
            $allFiles += [System.IO.Directory]::GetFiles($dir) |
                Where-Object { $mediaExts -contains [System.IO.Path]::GetExtension($_).ToLower() }
        }
    }

    if ($allFiles.Count -eq 0) { return }

    # Build duplicate key per file
    $keyMap = @{}   # key -> list of file paths
    foreach ($f in $allFiles) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f)
        if ($Mode -eq 'TV') {
            # Key = SxxExx token (e.g. S01E03) — case-insensitive
            if ($base -match '(?i)(S\d{1,2}E\d{1,3})') {
                $key = $Matches[1].ToUpper()
            } else {
                continue   # can't determine episode — skip
            }
        } else {
            # Key = Title (Year) — normalise spacing/case
            $key = ($base -replace '\s+',' ').ToLower().Trim()
        }

        if (-not $keyMap.ContainsKey($key)) { $keyMap[$key] = @() }
        $keyMap[$key] += $f
    }

    # Filter to only keys with more than one file
    $dupes = $keyMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }

    if (-not $dupes -or @($dupes).Count -eq 0) {
        Dup-Log "-- Duplicate scan: no duplicates found ✔ --" "LightGreen"
        return
    }

    Dup-Log "" "Gray"
    Dup-Log "-- ⚠ DUPLICATE SCAN RESULTS --" "Orange"

    $totalDupes = 0
    foreach ($entry in ($dupes | Sort-Object { $_.Key })) {
        $key   = $entry.Key
        $files = $entry.Value | Sort-Object { [System.IO.Path]::GetFileName($_) }
        Dup-Log "" "Gray"
        Dup-Log "  [$key] — $($files.Count) copies found:" "Orange"
        foreach ($fp in $files) {
            $size = [math]::Round((Get-Item -LiteralPath $fp).Length / 1MB, 1)
            Dup-Log "      $([System.IO.Path]::GetFileName($fp))  [$($size) MB]" "Yellow"
            Dup-Log "      $fp" "Gray"
        }
        $totalDupes++
    }

    Dup-Log "" "Gray"
    Dup-Log "-- $totalDupes duplicate group(s) found — review above and remove unwanted copies manually --" "Orange"
}

# ─────────────────────────────────────────────────────────────────────────────
#  SEARCH PICKER DIALOG
# ─────────────────────────────────────────────────────────────────────────────
function Show-SearchDialog {
    param([string]$Query,[string]$Type)
    $results=Search-TMDB $Query $Type
    if (-not $results -or $results.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No results found for: $Query","No Results",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
        return $null
    }
    $dlg=New-Object System.Windows.Forms.Form; $dlg.Text="Select $Type match"
    $dlg.Size=New-Object System.Drawing.Size(540,380); $dlg.StartPosition="CenterParent"
    $dlg.Font=New-Object System.Drawing.Font("Segoe UI",9)
    $dlg.BackColor=[System.Drawing.Color]::FromArgb(28,28,36); $dlg.ForeColor=[System.Drawing.Color]::White
    $dlg.FormBorderStyle="FixedDialog"; $dlg.MaximizeBox=$false
    $lbl=New-Object System.Windows.Forms.Label; $lbl.Text="Results for: $Query"
    $lbl.Location=New-Object System.Drawing.Point(12,10); $lbl.Size=New-Object System.Drawing.Size(510,20)
    $lbl.ForeColor=[System.Drawing.Color]::FromArgb(160,160,180)
    $list=New-Object System.Windows.Forms.ListBox; $list.Location=New-Object System.Drawing.Point(12,36)
    $list.Size=New-Object System.Drawing.Size(510,262); $list.BackColor=[System.Drawing.Color]::FromArgb(40,40,52)
    $list.ForeColor=[System.Drawing.Color]::White; $list.BorderStyle="FixedSingle"
    $list.Font=New-Object System.Drawing.Font("Consolas",9)
    $tagMap=@{}
    foreach ($item in $results) {
        $name=if($Type -eq 'tv'){$item.name}else{$item.title}
        $yr=if($Type -eq 'tv'){Get-Year $item.first_air_date}else{Get-Year $item.release_date}
        $entry="$name ($yr)  [id: $($item.id)]"; $list.Items.Add($entry)|Out-Null; $tagMap[$entry]=$item
    }
    if ($list.Items.Count -gt 0) { $list.SelectedIndex=0 }
    $btnOK=New-Object System.Windows.Forms.Button; $btnOK.Text="Select"
    $btnOK.Location=New-Object System.Drawing.Point(334,308); $btnOK.Size=New-Object System.Drawing.Size(88,28)
    $btnOK.BackColor=[System.Drawing.Color]::FromArgb(99,102,241); $btnOK.ForeColor=[System.Drawing.Color]::White
    $btnOK.FlatStyle="Flat"; $btnOK.DialogResult=[System.Windows.Forms.DialogResult]::OK
    $btnCancel=New-Object System.Windows.Forms.Button; $btnCancel.Text="Cancel"
    $btnCancel.Location=New-Object System.Drawing.Point(432,308); $btnCancel.Size=New-Object System.Drawing.Size(88,28)
    $btnCancel.BackColor=[System.Drawing.Color]::FromArgb(60,60,72); $btnCancel.ForeColor=[System.Drawing.Color]::White
    $btnCancel.FlatStyle="Flat"; $btnCancel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.AddRange(@($lbl,$list,$btnOK,$btnCancel))
    $dlg.AcceptButton=$btnOK; $dlg.CancelButton=$btnCancel
    $list.Add_DoubleClick({ $dlg.DialogResult=[System.Windows.Forms.DialogResult]::OK })
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $list.SelectedItem) { return $tagMap[$list.SelectedItem] }
    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
#  MOVIE ENTRY DIALOG
# ─────────────────────────────────────────────────────────────────────────────
function Show-MovieEntryDialog {
    param([string]$Filename)
    $dlg=New-Object System.Windows.Forms.Form; $dlg.Text="Match Movie"
    $dlg.Size=New-Object System.Drawing.Size(500,180); $dlg.StartPosition="CenterParent"
    $dlg.Font=New-Object System.Drawing.Font("Segoe UI",9)
    $dlg.BackColor=[System.Drawing.Color]::FromArgb(22,22,32); $dlg.ForeColor=[System.Drawing.Color]::White
    $dlg.FormBorderStyle="FixedDialog"; $dlg.MaximizeBox=$false
    # Filename shown as read-only TextBox so it can be highlighted and copied
    $lblFile=New-Object System.Windows.Forms.TextBox; $lblFile.Text=$Filename
    $lblFile.Location=New-Object System.Drawing.Point(12,10); $lblFile.Size=New-Object System.Drawing.Size(462,28)
    $lblFile.ForeColor=[System.Drawing.Color]::FromArgb(180,180,230)
    $lblFile.BackColor=[System.Drawing.Color]::FromArgb(22,22,32)
    $lblFile.Font=New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Italic)
    $lblFile.ReadOnly=$true; $lblFile.BorderStyle="None"; $lblFile.TabStop=$false
    $lbl=New-Object System.Windows.Forms.Label; $lbl.Text="Type the movie name and click Search:"
    $lbl.Location=New-Object System.Drawing.Point(12,46); $lbl.Size=New-Object System.Drawing.Size(470,18)
    $lbl.ForeColor=[System.Drawing.Color]::FromArgb(140,140,170)
    $txt=New-Object System.Windows.Forms.TextBox; $txt.Location=New-Object System.Drawing.Point(12,68)
    $txt.Size=New-Object System.Drawing.Size(360,24); $txt.BackColor=[System.Drawing.Color]::FromArgb(38,38,52)
    $txt.ForeColor=[System.Drawing.Color]::White; $txt.BorderStyle="FixedSingle"
    $btnSearch=New-Object System.Windows.Forms.Button; $btnSearch.Text="Search"
    $btnSearch.Location=New-Object System.Drawing.Point(380,67); $btnSearch.Size=New-Object System.Drawing.Size(96,26)
    $btnSearch.BackColor=[System.Drawing.Color]::FromArgb(99,102,241); $btnSearch.ForeColor=[System.Drawing.Color]::White; $btnSearch.FlatStyle="Flat"
    $btnSkip=New-Object System.Windows.Forms.Button; $btnSkip.Text="Skip File"
    $btnSkip.Location=New-Object System.Drawing.Point(380,102); $btnSkip.Size=New-Object System.Drawing.Size(96,26)
    $btnSkip.BackColor=[System.Drawing.Color]::FromArgb(60,60,72); $btnSkip.ForeColor=[System.Drawing.Color]::White
    $btnSkip.FlatStyle="Flat"; $btnSkip.DialogResult=[System.Windows.Forms.DialogResult]::Cancel
    $script:pickedMovie=$null
    $btnSearch.Add_Click({
        $q=$txt.Text.Trim(); if(-not $q){return}
        $found=Show-SearchDialog $q 'movie'
        if($found){$script:pickedMovie=$found;$dlg.DialogResult=[System.Windows.Forms.DialogResult]::OK;$dlg.Close()}
    })
    $txt.Add_KeyDown({ param($s,$e); if($e.KeyCode -eq [System.Windows.Forms.Keys]::Return){$btnSearch.PerformClick();$e.SuppressKeyPress=$true} })
    $dlg.Controls.AddRange(@($lblFile,$lbl,$txt,$btnSearch,$btnSkip))
    $dlg.AcceptButton=$btnSearch; $dlg.CancelButton=$btnSkip; $dlg.Add_Shown({$txt.Focus()})
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $script:pickedMovie) { return $script:pickedMovie }
    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
#  API KEY + FFMPEG DIALOG
# ─────────────────────────────────────────────────────────────────────────────
function Show-APIKeyDialog {
    $dlg=New-Object System.Windows.Forms.Form; $dlg.Text="Connect to TMDB"
    $dlg.Size=New-Object System.Drawing.Size(480,310); $dlg.StartPosition="CenterParent"
    $dlg.Font=New-Object System.Drawing.Font("Segoe UI",9)
    $dlg.BackColor=[System.Drawing.Color]::FromArgb(22,22,32); $dlg.ForeColor=[System.Drawing.Color]::White
    $dlg.FormBorderStyle="FixedDialog"; $dlg.MaximizeBox=$false

    $lbl1=New-Object System.Windows.Forms.Label; $lbl1.Text="TMDB API Key (v3 auth)"
    $lbl1.Location=New-Object System.Drawing.Point(16,16); $lbl1.Size=New-Object System.Drawing.Size(440,18)
    $lbl1.ForeColor=[System.Drawing.Color]::FromArgb(160,160,185)

    $txtKey=New-Object System.Windows.Forms.TextBox; $txtKey.Location=New-Object System.Drawing.Point(16,38)
    $txtKey.Size=New-Object System.Drawing.Size(440,24); $txtKey.BackColor=[System.Drawing.Color]::FromArgb(38,38,52)
    $txtKey.ForeColor=[System.Drawing.Color]::White; $txtKey.BorderStyle="FixedSingle"
    $txtKey.UseSystemPasswordChar=$true; $txtKey.Text=$script:TMDB_API_KEY

    $chkShow=New-Object System.Windows.Forms.CheckBox; $chkShow.Text="Show key"
    $chkShow.Location=New-Object System.Drawing.Point(16,68); $chkShow.Size=New-Object System.Drawing.Size(100,20)
    $chkShow.ForeColor=[System.Drawing.Color]::FromArgb(140,140,165)
    $chkShow.Add_CheckedChanged({$txtKey.UseSystemPasswordChar=-not $chkShow.Checked})

    $lblStatus=New-Object System.Windows.Forms.Label; $lblStatus.Location=New-Object System.Drawing.Point(16,94)
    $lblStatus.Size=New-Object System.Drawing.Size(440,20); $lblStatus.ForeColor=[System.Drawing.Color]::FromArgb(140,140,165)
    $lblStatus.Text="Key saved to %APPDATA%\JellyfinRenamer"

    $btnGetKey=New-Btn "Get API Key" 16 112 96 22 $true
    $btnGetKey.Add_Click({ Start-Process "https://www.themoviedb.org/settings/api" })

    $lbl2=New-Object System.Windows.Forms.Label; $lbl2.Text="Get a free key at themoviedb.org/settings/api"
    $lbl2.Location=New-Object System.Drawing.Point(120,117); $lbl2.Size=New-Object System.Drawing.Size(336,18)
    $lbl2.ForeColor=[System.Drawing.Color]::FromArgb(100,100,130)

    $div=New-Object System.Windows.Forms.Panel; $div.Location=New-Object System.Drawing.Point(16,140)
    $div.Size=New-Object System.Drawing.Size(440,1); $div.BackColor=[System.Drawing.Color]::FromArgb(50,50,68)

    $lblFfHead=New-Object System.Windows.Forms.Label; $lblFfHead.Text="FFmpeg Path (for Audio Fix mode)"
    $lblFfHead.Location=New-Object System.Drawing.Point(16,148); $lblFfHead.Size=New-Object System.Drawing.Size(440,18)
    $lblFfHead.ForeColor=[System.Drawing.Color]::FromArgb(160,160,185)

    $txtFfmpeg=New-Object System.Windows.Forms.TextBox; $txtFfmpeg.Location=New-Object System.Drawing.Point(16,170)
    $txtFfmpeg.Size=New-Object System.Drawing.Size(330,24); $txtFfmpeg.BackColor=[System.Drawing.Color]::FromArgb(38,38,52)
    $txtFfmpeg.ForeColor=[System.Drawing.Color]::White; $txtFfmpeg.BorderStyle="FixedSingle"; $txtFfmpeg.Text=$script:FFmpegPath

    $btnBrowseFf=New-Btn "Browse..." 354 169 102 26
    $btnBrowseFf.Add_Click({
        $ofd=New-Object System.Windows.Forms.OpenFileDialog; $ofd.Title="Select ffmpeg.exe"; $ofd.Filter="ffmpeg.exe|ffmpeg.exe|All Files|*.*"
        if($ofd.ShowDialog() -eq "OK"){$txtFfmpeg.Text=$ofd.FileName}
    })

    $lblFfHint=New-Object System.Windows.Forms.Label; $lblFfHint.Text="Point to ffmpeg.exe — ffprobe.exe must be in the same folder."
    $lblFfHint.Location=New-Object System.Drawing.Point(16,198); $lblFfHint.Size=New-Object System.Drawing.Size(440,18)
    $lblFfHint.ForeColor=[System.Drawing.Color]::FromArgb(100,100,130)

    $btnTest=New-Btn "Test TMDB" 16 232 100 28
    $btnTest.Add_Click({
        $script:TMDB_API_KEY=$txtKey.Text.Trim(); $r=Invoke-TMDB "/configuration"
        if($r){$lblStatus.Text="Connected successfully";$lblStatus.ForeColor=[System.Drawing.Color]::FromArgb(100,220,150)}
        else{$lblStatus.Text="Invalid key — check and retry";$lblStatus.ForeColor=[System.Drawing.Color]::FromArgb(240,80,80)}
    })

    $btnSave=New-Btn "Save & Close" 240 232 110 28 $true
    $btnSave.DialogResult=[System.Windows.Forms.DialogResult]::OK

    $btnCancel=New-Btn "Cancel" 360 232 96 28
    $btnCancel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel

    $dlg.Controls.AddRange(@($lbl1,$txtKey,$chkShow,$lblStatus,$btnGetKey,$lbl2,$div,$lblFfHead,$txtFfmpeg,$btnBrowseFf,$lblFfHint,$btnTest,$btnSave,$btnCancel))
    $dlg.AcceptButton=$btnSave; $dlg.CancelButton=$btnCancel

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $key=$txtKey.Text.Trim(); if($key){$script:TMDB_API_KEY=$key;Save-APIKey $key}
        $ffPath=$txtFfmpeg.Text.Trim(); if($ffPath -and (Test-Path $ffPath)){Set-FFmpegPaths $ffPath;Save-FFmpegPath $ffPath}
        return $true
    }
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
#  PROGRESS HELPER  — call Set-Progress to update bar + force UI repaint
# ─────────────────────────────────────────────────────────────────────────────
function Set-Progress {
    param([int]$Value,[string]$Style="Continuous")
    $prog.Style  = $Style
    $v = [math]::Max(0,[math]::Min(100,$Value))
    $prog.Value  = $v
    # Force immediate visual update so bar doesn't lag behind on long tasks
    $prog.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}
function Start-Marquee { Set-Progress 0 "Marquee" }
function Stop-Marquee  { param([int]$Val=100); Set-Progress $Val "Continuous" }

# ─────────────────────────────────────────────────────────────────────────────
#  CONTROL HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function New-Label { param([string]$Text,[int]$X,[int]$Y,[int]$W=120,[int]$H=20)
    $c=New-Object System.Windows.Forms.Label; $c.Text=$Text
    $c.Location=New-Object System.Drawing.Point($X,$Y); $c.Size=New-Object System.Drawing.Size($W,$H)
    $c.ForeColor=[System.Drawing.Color]::FromArgb(160,160,185); return $c }
function New-TextBox { param([int]$X,[int]$Y,[int]$W=200,[int]$H=24,[string]$Default="")
    $c=New-Object System.Windows.Forms.TextBox; $c.Location=New-Object System.Drawing.Point($X,$Y)
    $c.Size=New-Object System.Drawing.Size($W,$H); $c.BackColor=[System.Drawing.Color]::FromArgb(38,38,52)
    $c.ForeColor=[System.Drawing.Color]::White; $c.BorderStyle="FixedSingle"; $c.Text=$Default; return $c }
function New-Btn { param([string]$Text,[int]$X,[int]$Y,[int]$W=110,[int]$H=28,[bool]$Accent=$false)
    $c=New-Object RoundedButton; $c.Text=$Text
    $c.Location=New-Object System.Drawing.Point($X,$Y); $c.Size=New-Object System.Drawing.Size($W,$H)
    $c.BackColor=if($Accent){[System.Drawing.Color]::FromArgb(99,102,241)}else{[System.Drawing.Color]::FromArgb(55,55,70)}
    $c.ForeColor=[System.Drawing.Color]::White; $c.Cursor="Hand"; return $c }

$ANC_TLR  = [System.Windows.Forms.AnchorStyles]"Top,Left,Right"
$ANC_TBLR = [System.Windows.Forms.AnchorStyles]"Top,Bottom,Left,Right"
$ANC_TR   = [System.Windows.Forms.AnchorStyles]"Top,Right"
$ANC_BLR  = [System.Windows.Forms.AnchorStyles]"Bottom,Left,Right"
$ANC_BR   = [System.Windows.Forms.AnchorStyles]"Bottom,Right"
$ANC_TL   = [System.Windows.Forms.AnchorStyles]"Top,Left"

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN FORM
# ─────────────────────────────────────────────────────────────────────────────
$form=New-Object System.Windows.Forms.Form; $form.Text="MediaForge"
$form.Size=New-Object System.Drawing.Size(980,840); $form.MinimumSize=New-Object System.Drawing.Size(980,720)
$form.StartPosition="CenterScreen"; $form.BackColor=[System.Drawing.Color]::FromArgb(18,18,26)
$form.ForeColor=[System.Drawing.Color]::White; $form.Font=New-Object System.Drawing.Font("Segoe UI",9)
$form.AllowDrop=$true

# ─────────────────────────────────────────────────────────────────────────────
#  LOGO / ICON
# ─────────────────────────────────────────────────────────────────────────────
$script:AppRoot = if ($MyInvocation.MyCommand.Path) {
    [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
} else {
    [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$icoPath = [System.IO.Path]::Combine($script:AppRoot, "static", "logo.ico")
if (Test-Path $icoPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($icoPath) } catch {}
}

# ── Menu Bar ──────────────────────────────────────────────────────────────────
$menuStrip=New-Object System.Windows.Forms.MenuStrip
$menuStrip.BackColor=[System.Drawing.Color]::FromArgb(28,28,40); $menuStrip.ForeColor=[System.Drawing.Color]::White
$menuStrip.Renderer=New-Object DarkMenuRenderer
$menuConnect=New-Object System.Windows.Forms.ToolStripMenuItem; $menuConnect.Text="Connect"; $menuConnect.ForeColor=[System.Drawing.Color]::White
$menuSetKey=New-Object System.Windows.Forms.ToolStripMenuItem; $menuSetKey.Text="Set TMDB API Key & FFmpeg Path..."; $menuSetKey.ForeColor=[System.Drawing.Color]::White
$menuConnect.DropDownItems.Add($menuSetKey) | Out-Null
$menuStrip.Items.Add($menuConnect)|Out-Null


$form.Controls.Add($menuStrip); $form.MainMenuStrip=$menuStrip

function Update-ConnectStatus {
    if ($script:TMDB_API_KEY) {
        $menuConnect.Text      = "✔  TMDB Connected"
        $menuConnect.ForeColor = [System.Drawing.Color]::FromArgb(100,220,150)
    } else {
        $menuConnect.Text      = "Connect"
        $menuConnect.ForeColor = [System.Drawing.Color]::White
    }
}
$menuSetKey.Add_Click({if(Show-APIKeyDialog){Update-ConnectStatus}})

# ── Header ────────────────────────────────────────────────────────────────────
$header=New-Object System.Windows.Forms.Panel; $header.Location=New-Object System.Drawing.Point(0,28)
$header.Size=New-Object System.Drawing.Size(980,46); $header.BackColor=[System.Drawing.Color]::FromArgb(28,28,40)
$header.Anchor=$ANC_TLR; $header.AllowDrop=$true; $form.Controls.Add($header)
$lblTitle=New-Object System.Windows.Forms.Label; $lblTitle.Text="  MediaForge"
$lblTitle.Font=New-Object System.Drawing.Font("Segoe UI Semibold",13); $lblTitle.ForeColor=[System.Drawing.Color]::White
$lblTitle.Location=New-Object System.Drawing.Point(46,8); $lblTitle.Size=New-Object System.Drawing.Size(400,28); $lblTitle.Anchor=$ANC_TL
# Logo image in header
$logoPng = [System.IO.Path]::Combine($script:AppRoot, "static", "logo.png")
$picLogo = New-Object System.Windows.Forms.PictureBox
$picLogo.Location = New-Object System.Drawing.Point(8, 7)
$picLogo.Size     = New-Object System.Drawing.Size(32, 32)
$picLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picLogo.BackColor = [System.Drawing.Color]::Transparent
if (Test-Path $logoPng) {
    try { $picLogo.Image = [System.Drawing.Image]::FromFile($logoPng) } catch {}
}
$header.Controls.Add($picLogo)
$header.Controls.Add($lblTitle)
$lblSub=New-Object System.Windows.Forms.Label; $lblSub.Text="Smart media tools, TMDB‑powered"
$lblSub.ForeColor=[System.Drawing.Color]::FromArgb(100,100,130); $lblSub.Location=New-Object System.Drawing.Point(620,16)
$lblSub.Size=New-Object System.Drawing.Size(320,18); $lblSub.Anchor=$ANC_TR; $header.Controls.Add($lblSub)

function New-Divider { param([int]$Y)
    $d=New-Object System.Windows.Forms.Panel; $d.Location=New-Object System.Drawing.Point(12,$Y)
    $d.Size=New-Object System.Drawing.Size(940,1); $d.BackColor=[System.Drawing.Color]::FromArgb(50,50,68)
    $d.Anchor=$ANC_TLR; $form.Controls.Add($d) }

# ── Mode Radio Buttons ────────────────────────────────────────────────────────
$panMode=New-Object System.Windows.Forms.Panel; $panMode.Location=New-Object System.Drawing.Point(12,82)
$panMode.Size=New-Object System.Drawing.Size(940,36); $panMode.Anchor=$ANC_TLR; $panMode.AllowDrop=$true
$form.Controls.Add($panMode)
$panMode.Controls.Add((New-Label "Mode:" 0 8 44))

$rbTV=New-Object System.Windows.Forms.RadioButton; $rbTV.Text="TV Show"
$rbTV.Location=New-Object System.Drawing.Point(50,6); $rbTV.Size=New-Object System.Drawing.Size(90,24)
$rbTV.Checked=$true; $rbTV.ForeColor=[System.Drawing.Color]::White; $panMode.Controls.Add($rbTV)

$rbMovie=New-Object System.Windows.Forms.RadioButton; $rbMovie.Text="Movie"
$rbMovie.Location=New-Object System.Drawing.Point(148,6); $rbMovie.Size=New-Object System.Drawing.Size(80,24)
$rbMovie.ForeColor=[System.Drawing.Color]::White; $panMode.Controls.Add($rbMovie)

$rbAudio=New-Object System.Windows.Forms.RadioButton; $rbAudio.Text="Audio Fix"
$rbAudio.Location=New-Object System.Drawing.Point(236,6); $rbAudio.Size=New-Object System.Drawing.Size(90,24)
$rbAudio.ForeColor=[System.Drawing.Color]::FromArgb(255,160,60); $panMode.Controls.Add($rbAudio)

New-Divider 124

# ═════════════════════════════════════════════════════════════════════════════
#  TV OPTIONS PANEL  (no HE-AAC checkbox — Audio Fix mode handles that)
# ═════════════════════════════════════════════════════════════════════════════
$panTV=New-Object System.Windows.Forms.Panel; $panTV.Location=New-Object System.Drawing.Point(12,132)
$panTV.Size=New-Object System.Drawing.Size(940,120); $panTV.BackColor=[System.Drawing.Color]::FromArgb(24,24,34)
$panTV.Anchor=$ANC_TLR; $panTV.AllowDrop=$true; $form.Controls.Add($panTV)

$lhTV=New-Object System.Windows.Forms.Label; $lhTV.Text="TV SHOW OPTIONS"
$lhTV.Font=New-Object System.Drawing.Font("Segoe UI",7,[System.Drawing.FontStyle]::Bold)
$lhTV.ForeColor=[System.Drawing.Color]::FromArgb(99,102,241); $lhTV.Location=New-Object System.Drawing.Point(8,6)
$lhTV.Size=New-Object System.Drawing.Size(200,16); $panTV.Controls.Add($lhTV)

$panTV.Controls.Add((New-Label "Show ID / Name:" 8 30 104))
$txtShowSearch=New-TextBox 116 28 0 24; $txtShowSearch.Anchor=$ANC_TLR
$txtShowSearch.Width=$panTV.Width-116-240; $panTV.Controls.Add($txtShowSearch)
$btnShowSearch=New-Btn "Search TMDB" 0 27 108 26 $true; $btnShowSearch.Anchor=$ANC_TR
$btnShowSearch.Left=$panTV.Width-108-128; $panTV.Controls.Add($btnShowSearch)
$lblShowPicked=New-Object System.Windows.Forms.Label; $lblShowPicked.Text="(none picked)"
$lblShowPicked.Anchor=$ANC_TR; $lblShowPicked.Size=New-Object System.Drawing.Size(120,18)
$lblShowPicked.Left=$panTV.Width-124; $lblShowPicked.Top=32
$lblShowPicked.ForeColor=[System.Drawing.Color]::FromArgb(100,220,150); $panTV.Controls.Add($lblShowPicked)

$chkManualOverride=New-Object System.Windows.Forms.CheckBox; $chkManualOverride.Text="Force manual season/episode override"
$chkManualOverride.Location=New-Object System.Drawing.Point(8,68); $chkManualOverride.Size=New-Object System.Drawing.Size(260,20)
$chkManualOverride.ForeColor=[System.Drawing.Color]::FromArgb(160,160,185); $chkManualOverride.Checked=$false
$panTV.Controls.Add($chkManualOverride)

$chkShowName=New-Object System.Windows.Forms.CheckBox; $chkShowName.Text="Include show name in filename"
$chkShowName.Location=New-Object System.Drawing.Point(280,68); $chkShowName.Size=New-Object System.Drawing.Size(220,20)
$chkShowName.ForeColor=[System.Drawing.Color]::FromArgb(160,160,185); $chkShowName.Checked=$true
$chkShowName.Add_CheckedChanged({Update-Preview}); $panTV.Controls.Add($chkShowName)

$chkTVRenameInPlace=New-Object System.Windows.Forms.CheckBox; $chkTVRenameInPlace.Text="Rename in Place"
$chkTVRenameInPlace.Location=New-Object System.Drawing.Point(508,68); $chkTVRenameInPlace.Size=New-Object System.Drawing.Size(140,20)
$chkTVRenameInPlace.ForeColor=[System.Drawing.Color]::FromArgb(160,160,185); $chkTVRenameInPlace.Checked=$false
$panTV.Controls.Add($chkTVRenameInPlace)

$panTV.Controls.Add((New-Label "Extensions:" 684 68 72))
$txtExts=New-TextBox 760 66 160 24 ".mkv,.mp4,.avi"; $panTV.Controls.Add($txtExts)

$lblSeason=New-Label "Season:" 8 92 50
$lblSeason.Visible=$false
$panTV.Controls.Add($lblSeason)
$txtSeason=New-TextBox 58 90 50 24 "1"; $txtSeason.Add_TextChanged({Update-Preview}); $txtSeason.Visible=$false; $panTV.Controls.Add($txtSeason)

$lblStartEp=New-Label "Start Ep:" 128 92 60
$lblStartEp.Visible=$false
$panTV.Controls.Add($lblStartEp)
$txtStartEp=New-TextBox 196 90 50 24 "1"; $txtStartEp.Add_TextChanged({Update-Preview}); $txtStartEp.Visible=$false; $panTV.Controls.Add($txtStartEp)

$lblFallbackHint=New-Object System.Windows.Forms.Label
$lblFallbackHint.Text="When checked, season and episode numbers will be rewritten from the values above."
$lblFallbackHint.Location=New-Object System.Drawing.Point(260,92)
$lblFallbackHint.Size=New-Object System.Drawing.Size(420,18)
$lblFallbackHint.ForeColor=[System.Drawing.Color]::FromArgb(90,90,120)
$lblFallbackHint.Font=New-Object System.Drawing.Font("Segoe UI",7.5,[System.Drawing.FontStyle]::Italic)
$lblFallbackHint.Visible=$false
$panTV.Controls.Add($lblFallbackHint)

$chkManualOverride.Add_CheckedChanged({
    $visible = $chkManualOverride.Checked
    $lblSeason.Visible = $visible
    $txtSeason.Visible = $visible
    $lblStartEp.Visible = $visible
    $txtStartEp.Visible = $visible
    $lblFallbackHint.Visible = $visible
    Update-Preview
})


$script:TVShowData=$null
$btnShowSearch.Add_Click({
    if(-not $script:TMDB_API_KEY){[System.Windows.Forms.MessageBox]::Show("Connect your TMDB API key first.","Not Connected",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning);return}
    $q=$txtShowSearch.Text.Trim(); if(-not $q){return}
    $item=if($q -match '^\d+$' -or $q -match '^tt\d+'){Get-TMDBById $q 'tv'}else{Show-SearchDialog $q 'tv'}
    if($item){$script:TVShowData=$item;$script:SeasonCache=@{};$lblShowPicked.Text="$($item.name) ($(Get-Year $item.first_air_date))";Update-Preview}
})
$txtShowSearch.Add_KeyDown({param($s,$e);if($e.KeyCode -eq [System.Windows.Forms.Keys]::Return){$btnShowSearch.PerformClick();$e.SuppressKeyPress=$true}})

# ═════════════════════════════════════════════════════════════════════════════
#  MOVIE OPTIONS PANEL  (no HE-AAC checkbox)
# ═════════════════════════════════════════════════════════════════════════════
$panMovie=New-Object System.Windows.Forms.Panel; $panMovie.Location=New-Object System.Drawing.Point(12,132)
$panMovie.Size=New-Object System.Drawing.Size(940,116); $panMovie.BackColor=[System.Drawing.Color]::FromArgb(24,24,34)
$panMovie.Anchor=$ANC_TLR; $panMovie.AllowDrop=$true; $panMovie.Visible=$false; $form.Controls.Add($panMovie)

$lhMovie=New-Object System.Windows.Forms.Label; $lhMovie.Text="MOVIE OPTIONS"
$lhMovie.Font=New-Object System.Drawing.Font("Segoe UI",7,[System.Drawing.FontStyle]::Bold)
$lhMovie.ForeColor=[System.Drawing.Color]::FromArgb(99,102,241); $lhMovie.Location=New-Object System.Drawing.Point(8,6)
$lhMovie.Size=New-Object System.Drawing.Size(200,16); $panMovie.Controls.Add($lhMovie)

$btnMovieSearchTMDB=New-Btn "Search TMDB" 8 27 108 26 $true; $panMovie.Controls.Add($btnMovieSearchTMDB)
$lblMovieMatched=New-Object System.Windows.Forms.Label; $lblMovieMatched.Text="(none matched)"
$lblMovieMatched.Location=New-Object System.Drawing.Point(124,32); $lblMovieMatched.Size=New-Object System.Drawing.Size(400,18)
$lblMovieMatched.ForeColor=[System.Drawing.Color]::FromArgb(130,130,160); $panMovie.Controls.Add($lblMovieMatched)

$panMovie.Controls.Add((New-Label "Extensions:" 8 68 72))
$txtMovieExts=New-TextBox 82 66 160 24 ".mkv,.mp4,.avi"; $panMovie.Controls.Add($txtMovieExts)

$chkMovieRenameInPlace=New-Object System.Windows.Forms.CheckBox; $chkMovieRenameInPlace.Text="Rename in Place"
$chkMovieRenameInPlace.Location=New-Object System.Drawing.Point(256,68); $chkMovieRenameInPlace.Size=New-Object System.Drawing.Size(140,20)
$chkMovieRenameInPlace.ForeColor=[System.Drawing.Color]::FromArgb(160,160,185); $chkMovieRenameInPlace.Checked=$false
$panMovie.Controls.Add($chkMovieRenameInPlace)

$lblMovieHint=New-Object System.Windows.Forms.Label
$lblMovieHint.Text="Add files below, then click Search TMDB — you will be prompted to match each file. Rename Now applies the result."
$lblMovieHint.ForeColor=[System.Drawing.Color]::FromArgb(100,100,130); $lblMovieHint.Location=New-Object System.Drawing.Point(8,90)
$lblMovieHint.Size=New-Object System.Drawing.Size(924,18); $lblMovieHint.Anchor=$ANC_TLR; $panMovie.Controls.Add($lblMovieHint)

$btnMovieSearchTMDB.Add_Click({
    if(-not $script:TMDB_API_KEY){[System.Windows.Forms.MessageBox]::Show("Connect your TMDB API key first.","Not Connected",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning);return}
    if($script:SelectedFiles.Count -eq 0){Write-Log "No files queued." "Yellow";return}
    Start-Marquee; $log.Clear()
    $entries=Build-MovieEntries; if($entries.Count -eq 0){Write-Log "No movies matched." "Yellow";return}
    $script:CachedMovieEntries=$entries; $script:CachedForFiles=$script:SelectedFiles.Clone()
    $lblMovieMatched.Text="$($entries.Count) file(s) matched — click Rename Now."
    $lblMovieMatched.ForeColor=[System.Drawing.Color]::FromArgb(100,220,150); Stop-Marquee 100; Update-Preview
})

# ═════════════════════════════════════════════════════════════════════════════
#  AUDIO FIX OPTIONS PANEL
# ═════════════════════════════════════════════════════════════════════════════
$panAudio=New-Object System.Windows.Forms.Panel; $panAudio.Location=New-Object System.Drawing.Point(12,132)
$panAudio.Size=New-Object System.Drawing.Size(940,126); $panAudio.BackColor=[System.Drawing.Color]::FromArgb(24,24,34)
$panAudio.Anchor=$ANC_TLR; $panAudio.AllowDrop=$true; $panAudio.Visible=$false; $form.Controls.Add($panAudio)

$lhAudio=New-Object System.Windows.Forms.Label; $lhAudio.Text="AUDIO FIX OPTIONS"
$lhAudio.Font=New-Object System.Drawing.Font("Segoe UI",7,[System.Drawing.FontStyle]::Bold)
$lhAudio.ForeColor=[System.Drawing.Color]::FromArgb(255,160,60); $lhAudio.Location=New-Object System.Drawing.Point(8,6)
$lhAudio.Size=New-Object System.Drawing.Size(200,16); $panAudio.Controls.Add($lhAudio)

# ── Row 1: Step 1 label | Scan button | Extensions label+box | FFmpeg status ─
$lblStep1=New-Object System.Windows.Forms.Label; $lblStep1.Text="Step 1 — Scan"
$lblStep1.Font=New-Object System.Drawing.Font("Segoe UI",8,[System.Drawing.FontStyle]::Bold)
$lblStep1.ForeColor=[System.Drawing.Color]::FromArgb(160,160,200)
$lblStep1.Location=New-Object System.Drawing.Point(8,28); $lblStep1.Size=New-Object System.Drawing.Size(100,18)
$panAudio.Controls.Add($lblStep1)

$btnAudioScan=New-Btn "Re-Scan" 8 48 90 26 $false
$btnAudioScan.BackColor=[System.Drawing.Color]::FromArgb(50,80,100); $panAudio.Controls.Add($btnAudioScan)

$lblAudioExt=New-Label "Extensions:" 118 52 72; $panAudio.Controls.Add($lblAudioExt)

$txtAudioExts=New-Object System.Windows.Forms.TextBox
$txtAudioExts.Location=New-Object System.Drawing.Point(192,50)
$txtAudioExts.Size=New-Object System.Drawing.Size(160,24)
$txtAudioExts.BackColor=[System.Drawing.Color]::FromArgb(38,38,52)
$txtAudioExts.ForeColor=[System.Drawing.Color]::White; $txtAudioExts.BorderStyle="FixedSingle"
$txtAudioExts.Text=".mkv,.mp4,.avi"; $panAudio.Controls.Add($txtAudioExts)

$lblAudioFfmpeg=New-Object System.Windows.Forms.Label
$lblAudioFfmpeg.Location=New-Object System.Drawing.Point(364,54)
$lblAudioFfmpeg.Size=New-Object System.Drawing.Size(568,18)
$lblAudioFfmpeg.Anchor=$ANC_TLR
$lblAudioFfmpeg.ForeColor=[System.Drawing.Color]::FromArgb(100,180,100)
$panAudio.Controls.Add($lblAudioFfmpeg)

$lblScanResult=New-Object System.Windows.Forms.Label
$lblScanResult.Text="Add files or folders — audio codec is detected automatically for each file."
$lblScanResult.ForeColor=[System.Drawing.Color]::FromArgb(120,120,150)
$lblScanResult.Location=New-Object System.Drawing.Point(118,30); $lblScanResult.Size=New-Object System.Drawing.Size(610,16)
$lblScanResult.Anchor=$ANC_TLR; $panAudio.Controls.Add($lblScanResult)

# ── Divider ──────────────────────────────────────────────────────────────────
$adiv=New-Object System.Windows.Forms.Panel; $adiv.Location=New-Object System.Drawing.Point(8,82)
$adiv.Size=New-Object System.Drawing.Size(922,1); $adiv.BackColor=[System.Drawing.Color]::FromArgb(50,50,68)
$adiv.Anchor=$ANC_TLR; $panAudio.Controls.Add($adiv)

# ── Row 2: Step 2 label | hint text ─────────────────────────────────────────
$lblStep2=New-Object System.Windows.Forms.Label; $lblStep2.Text="Step 2 — Review & Fix"
$lblStep2.Font=New-Object System.Drawing.Font("Segoe UI",8,[System.Drawing.FontStyle]::Bold)
$lblStep2.ForeColor=[System.Drawing.Color]::FromArgb(160,160,200)
$lblStep2.Location=New-Object System.Drawing.Point(8,92); $lblStep2.Size=New-Object System.Drawing.Size(160,18)
$panAudio.Controls.Add($lblStep2)

$lblStep2Hint=New-Object System.Windows.Forms.Label
$lblStep2Hint.Text="Orange = HE-AAC (will be converted to AAC LC stereo).  Green = fine (will be skipped).  Click Fix Now to apply."
$lblStep2Hint.ForeColor=[System.Drawing.Color]::FromArgb(120,120,150)
$lblStep2Hint.Location=New-Object System.Drawing.Point(176,94); $lblStep2Hint.Size=New-Object System.Drawing.Size(754,18)
$lblStep2Hint.Anchor=$ANC_TLR; $panAudio.Controls.Add($lblStep2Hint)

$script:AudioScanDone=$false
$script:FixingNow=$false
$script:CancelFix=$false
$script:CurrentFFmpegProc=$null

# ── HTML Report saving Mode switching ────────────────────────────────────────────────────────────
function Save-AudioReport {
    if ($script:AudioReport.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No report data yet.`nRun a scan and Fix Now first.",
            "No Report Data",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title    = "Save MediaForge Report"
    $sfd.Filter   = "HTML Report|*.html|All Files|*.*"
    $sfd.FileName = "MediaForge-Report-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"
    if ($sfd.ShowDialog() -ne "OK") { return }

    $fixed   = @($script:AudioReport | Where-Object { $_.Status -eq "Fixed"   })
    $failed  = @($script:AudioReport | Where-Object { $_.Status -eq "Failed"  })
    $skipped = @($script:AudioReport | Where-Object { $_.Status -eq "Skipped" })

    function HE([string]$s) {
        return $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
    }
    function Make-Rows([array]$items,[string]$css) {
        ($items | ForEach-Object {
            "<tr class='$css'><td class='fn'>$(HE $_.File)</td><td class='st'>$($_.Status)</td><td class='dt'>$(HE $_.Detail)</td></tr>"
        }) -join "`n"
    }

    $ts = Get-Date -Format "dddd, MMMM d yyyy  h:mm tt"

    $logoSrc  = ""
$logoPath = ""

# Try app root first
if ($script:AppRoot -and (Test-Path $script:AppRoot)) {
    $logoPath = [System.IO.Path]::Combine($script:AppRoot, "static", "logo.png")
}

# Fallback: try relative to this script/executable
if (-not $logoPath -or -not (Test-Path $logoPath)) {
    $exePath = if ($MyInvocation.MyCommand.Path) {
        [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
    } else {
        [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
    }
    $logoPath = [System.IO.Path]::Combine($exePath, "static", "logo.png")
}

if (Test-Path $logoPath) {
    try {
        $logoBytes = [System.IO.File]::ReadAllBytes($logoPath)
        $logoB64   = [Convert]::ToBase64String($logoBytes)
        $logoSrc   = "data:image/png;base64,$logoB64"
        Write-Log "Report logo loaded: $logoPath" "LightGreen"
    } catch {
        Write-Log "Report logo read failed: $($_.Exception.Message)" "Orange"
    }
} else {
    Write-Log "Report logo not found: $logoPath" "Yellow"
}

$html = @"
<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8"><title>MediaForge Report</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',sans-serif;background:#0f0f17;color:#d0d0e0;padding:36px 40px}
.top{display:flex;align-items:center;gap:14px;margin-bottom:6px}
.logo{
    width:46px;
    height:46px;
    flex:0 0 46px;
    display:flex;
    align-items:center;
    justify-content:center;
    background:#1a1a28;
    border:1px solid #2a2a40;
    border-radius:10px;
    overflow:hidden;
    margin-top:-25px; /* optional: to visually align with header if logo is centered there */
}
.logo img{width:90%;height:90%;object-fit:contain;display:block}
.logo-fallback{
    width:46px;
    height:46px;
    flex:0 0 46px;
    display:flex;
    align-items:center;
    justify-content:center;
    background:#1a1a28;
    border:1px solid #2a2a40;
    border-radius:10px;
    color:#9090ff;
    font-size:18px;
    font-weight:700;
    font-family:'Segoe UI Semibold',sans-serif;
    margin-top:-25px; /* optional: to visually align with header if logo is centered there */
}
.titlewrap{display:flex;flex-direction:column}
h1{font-size:22px;color:#fff;margin:0}
.sub{color:#5858a0;font-size:13px;margin:4px 0 28px 0}
.cards{display:flex;gap:14px;flex-wrap:wrap;margin-bottom:32px}
.card{background:#1a1a28;border-radius:10px;padding:14px 22px;min-width:130px;text-align:center}
.num{font-size:38px;font-weight:700;line-height:1}
.lbl{font-size:11px;color:#7070a0;margin-top:3px;letter-spacing:.06em;text-transform:uppercase}
.card.total .num{color:#9090ff}.card.ok .num{color:#64dc96}.card.fail .num{color:#f05050}.card.skip .num{color:#7070a0}
h2{font-size:12px;color:#7070b0;letter-spacing:.08em;text-transform:uppercase;margin:26px 0 10px}
table{width:100%;border-collapse:collapse;background:#12121e;border-radius:8px;overflow:hidden;font-size:13px;margin-bottom:4px}
thead th{background:#1a1a2c;color:#5858a0;text-align:left;padding:9px 13px;font-weight:600;font-size:11px;letter-spacing:.05em;text-transform:uppercase}
tbody tr{border-bottom:1px solid #1a1a2c}tbody tr:last-child{border-bottom:none}
td{padding:8px 13px;vertical-align:top}
td.fn{font-family:Consolas,monospace;color:#b0b0d8;word-break:break-all;width:42%}
td.st{font-weight:700;width:9%}td.dt{color:#6868a0;font-size:12px}
tr.ok td.st{color:#64dc96}tr.fail td.st{color:#f05050}tr.skip td.st{color:#6868a8}
tr.fail td.dt{color:#e08080;font-size:12px}
@media print{
body{background:#fff;color:#000;padding:20px}
.logo,.logo-fallback{background:#f0f0f8;border:1px solid #ddd}
.card{background:#f0f0f8;border:1px solid #ddd}
table{background:#fff}thead th{background:#e8e8f0;color:#333}
tbody tr{border-bottom:1px solid #e0e0e0}td.fn{color:#222}td.dt{color:#555}
h1{color:#000}tr.ok td.st{color:#1a7a3a}tr.fail td.st{color:#c00}tr.skip td.st{color:#666}
}
</style></head><body>
<div class="top">
  $(if ($logoSrc) {
      '<div class="logo"><img src="' + $logoSrc + '" alt="MediaForge logo"></div>'
    } else {
      '<div class="logo-fallback">MF</div>'
    })
  <div class="titlewrap">
    <h1>MediaForge Report</h1>
    <div class="sub">Generated - $ts </div>
  </div>
</div>
<div class="cards">
  <div class="card total"><div class="num">$($script:AudioReport.Count)</div><div class="lbl">Total</div></div>
  <div class="card ok"><div class="num">$($fixed.Count)</div><div class="lbl">Fixed</div></div>
  <div class="card fail"><div class="num">$($failed.Count)</div><div class="lbl">Failed</div></div>
  <div class="card skip"><div class="num">$($skipped.Count)</div><div class="lbl">Skipped</div></div>
</div>
"@

if ($failed.Count -gt 0) {
    $html += "<h2>Failed ($($failed.Count))</h2><table><thead><tr><th>File</th><th>Status</th><th>Reason</th></tr></thead><tbody>`n"
    $html += Make-Rows $failed "fail"
    $html += "`n</tbody></table>"
}
if ($fixed.Count -gt 0) {
    $html += "<h2>Fixed ($($fixed.Count))</h2><table><thead><tr><th>File</th><th>Status</th><th>Detail</th></tr></thead><tbody>`n"
    $html += Make-Rows $fixed "ok"
    $html += "`n</tbody></table>"
}
if ($skipped.Count -gt 0) {
    $html += "<h2>Skipped / Already Fine ($($skipped.Count))</h2><table><thead><tr><th>File</th><th>Status</th><th>Detail</th></tr></thead><tbody>`n"
    $html += Make-Rows $skipped "skip"
    $html += "`n</tbody></table>"
}
$html += "`n</body></html>"

    try {
        [System.IO.File]::WriteAllText($sfd.FileName, $html, [System.Text.Encoding]::UTF8)
        Write-Log "Report saved: $($sfd.FileName)" "LightGreen"
        $ans=[System.Windows.Forms.MessageBox]::Show(
            "Report saved to:`n$($sfd.FileName)`n`nOpen it now?",
            "Report Saved",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        if ($ans -eq "Yes") { Start-Process $sfd.FileName }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to save:`n$($_.Exception.Message)","Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Switch-Mode {
    $panTV.Visible    = $rbTV.Checked
    $panMovie.Visible = $rbMovie.Checked
    $panAudio.Visible = $rbAudio.Checked

    if ($rbAudio.Checked) {
        $btnSaveLog.Visible  = $true
        $lblTallyFix.Visible = $true
        $lblTallyPend.Visible = $true
        $lblTallyNow.Visible = $true
        $lblTallyOk.Visible  = $true
        $btnEndTask.Visible  = $true
        $btnRename.Text      = "Fix Now"
        $btnRename.BackColor = [System.Drawing.Color]::FromArgb(160,110,20)
        # Update FFmpeg status label
        if ($script:FFmpegPath -and (Test-Path $script:FFmpegPath)) {
            $lblAudioFfmpeg.Text      = "FFmpeg ready: $script:FFmpegPath"
            $lblAudioFfmpeg.ForeColor = [System.Drawing.Color]::FromArgb(100,180,100)
        } else {
            $lblAudioFfmpeg.Text      = "FFmpeg not configured — set path in Connect menu."
            $lblAudioFfmpeg.ForeColor = [System.Drawing.Color]::FromArgb(255,100,80)
        }
    } else {
        $btnSaveLog.Visible  = $false
        $lblTallyFix.Visible = $false
        $lblTallyPend.Visible = $false
        $lblTallyNow.Visible = $false
        $lblTallyOk.Visible  = $false
        $btnEndTask.Visible  = $false
        $btnRename.Text      = "Rename Now"
        $btnRename.BackColor = [System.Drawing.Color]::FromArgb(99,102,241)
    }

    $script:AudioScanDone = $false
    Update-FileList
    Update-Preview
}

$rbTV.Add_CheckedChanged({    if($rbTV.Checked)    {Switch-Mode} })
$rbMovie.Add_CheckedChanged({ if($rbMovie.Checked) {Switch-Mode} })
$rbAudio.Add_CheckedChanged({ if($rbAudio.Checked) {Switch-Mode} })

New-Divider 256

# ═════════════════════════════════════════════════════════════════════════════
#  FILES / FOLDER SECTION
# ═════════════════════════════════════════════════════════════════════════════
$panFiles=New-Object System.Windows.Forms.Panel; $panFiles.Location=New-Object System.Drawing.Point(12,292)
$panFiles.Size=New-Object System.Drawing.Size(940,300); $panFiles.Anchor=$ANC_TBLR; $panFiles.AllowDrop=$true
$form.Controls.Add($panFiles)

$lblFilesHead=New-Object System.Windows.Forms.Label
$lblFilesHead.Text="FILES / FOLDER  —  drag files or folders anywhere onto this window"
$lblFilesHead.Font=New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$lblFilesHead.ForeColor=[System.Drawing.Color]::FromArgb(99,102,241); $lblFilesHead.Location=New-Object System.Drawing.Point(0,0)
$lblFilesHead.Size=New-Object System.Drawing.Size(700,20); $lblFilesHead.Anchor=$ANC_TL; $panFiles.Controls.Add($lblFilesHead)

# ListView — File Name | Audio | Action / Proposed Name | Proposed Dest.
$lstFiles=New-Object System.Windows.Forms.ListView; $lstFiles.Location=New-Object System.Drawing.Point(0,24)
$lstFiles.Size=New-Object System.Drawing.Size(808,270); $lstFiles.Anchor=$ANC_TBLR
$lstFiles.View=[System.Windows.Forms.View]::Details; $lstFiles.FullRowSelect=$true; $lstFiles.GridLines=$false
$lstFiles.BackColor=[System.Drawing.Color]::FromArgb(28,28,40); $lstFiles.ForeColor=[System.Drawing.Color]::FromArgb(180,180,210)
$lstFiles.BorderStyle="FixedSingle"; $lstFiles.Font=New-Object System.Drawing.Font("Consolas",10)
$lstFiles.AllowDrop=$true; $lstFiles.HeaderStyle="Nonclickable"
$null=$lstFiles.Columns.Add("File Name",200)
$null=$lstFiles.Columns.Add("Audio",80)
$null=$lstFiles.Columns.Add("Action / Proposed Name",220)
$null=$lstFiles.Columns.Add("Proposed Dest.",270)
$panFiles.Controls.Add($lstFiles)

$lstFiles.Add_Resize({
    $w=$lstFiles.ClientSize.Width-4
    $lstFiles.Columns[0].Width=[int]($w*0.22); $lstFiles.Columns[1].Width=[int]($w*0.09)
    $lstFiles.Columns[2].Width=[int]($w*0.30); $lstFiles.Columns[3].Width=[int]($w*0.39)
})

# Sidebar
$btnBrowseFolder=New-Btn "Browse Folder" 816 20 124 28; $btnBrowseFolder.Anchor=$ANC_TR; $panFiles.Controls.Add($btnBrowseFolder)
$btnAddFiles=New-Btn "Add Files" 816 54 124 28; $btnAddFiles.Anchor=$ANC_TR; $panFiles.Controls.Add($btnAddFiles)
$btnClearSelected=New-Btn "Clear Selected" 816 88 124 28; $btnClearSelected.Anchor=$ANC_TR; $panFiles.Controls.Add($btnClearSelected)
$btnClearFiles=New-Btn "Clear All" 816 122 124 28; $btnClearFiles.Anchor=$ANC_TR; $panFiles.Controls.Add($btnClearFiles)
$btnEndTask=New-Btn "End Task" 816 154 124 28; $btnEndTask.Anchor=$ANC_TR
$btnEndTask.BackColor=[System.Drawing.Color]::FromArgb(100,30,30)
$btnEndTask.ForeColor=[System.Drawing.Color]::White
$btnEndTask.Enabled=$false; $btnEndTask.Visible=$false; $panFiles.Controls.Add($btnEndTask)
$lblFileCount=New-Object System.Windows.Forms.Label; $lblFileCount.Text="0 files queued"
$lblFileCount.Location=New-Object System.Drawing.Point(816,188); $lblFileCount.Size=New-Object System.Drawing.Size(124,18)
$lblFileCount.ForeColor=[System.Drawing.Color]::FromArgb(120,120,150); $lblFileCount.Font=New-Object System.Drawing.Font("Segoe UI",9); $lblFileCount.TextAlign="MiddleCenter"
$lblFileCount.Anchor=$ANC_TR; $panFiles.Controls.Add($lblFileCount)

# ── Audio Fix tally labels ────────────────────────────────────────────────────
function New-TallyLabel([string]$txt,[int]$y,[int[]]$rgb){
    $l=New-Object System.Windows.Forms.Label; $l.Text=$txt
    $l.Location=New-Object System.Drawing.Point(812,$y); $l.Size=New-Object System.Drawing.Size(136,18)
    $l.ForeColor=[System.Drawing.Color]::FromArgb($rgb[0],$rgb[1],$rgb[2])
    $l.Font=New-Object System.Drawing.Font("Segoe UI",9); $l.TextAlign="MiddleLeft"
    $l.Anchor=$ANC_TR; $l.Visible=$false; $panFiles.Controls.Add($l); return $l
}
$lblTallyFix  = New-TallyLabel "● Failed        0" 212 @(220,  80,  80)
$lblTallyPend = New-TallyLabel "● Pending       0" 232 @(255, 140,  40)
$lblTallyNow  = New-TallyLabel "● Converting    0" 252 @(220, 200,  60)
$lblTallyOk   = New-TallyLabel "● Operational   0" 272 @( 80, 200, 120)

function Update-Tally {
    # Pending  = queued to convert but not yet active
    $pending     = ($lstFiles.Items | Where-Object { $_.SubItems[2].Text -like "Will convert*" }).Count
    # Converting = 1 while FFmpeg is actively running, else 0
    $converting  = if ($script:FixingNow) { 1 } else { 0 }
    # Failed     = rows where FFmpeg errored
    $failed      = ($lstFiles.Items | Where-Object { $_.SubItems[2].Text -like "Fix failed*" }).Count
    # Operational = already fine + successfully converted
    $operational = ($lstFiles.Items | Where-Object { $_.SubItems[2].Text -like "OK*" -or $_.SubItems[2].Text -like "Fixed*" }).Count
    $lblTallyFix.Text  = "● Failed        $failed"
    $lblTallyPend.Text = "● Pending       $pending"
    $lblTallyNow.Text  = "● Converting    $converting"
    $lblTallyOk.Text   = "● Operational   $operational"
}

$script:SelectedFiles=@(); $script:DropHintShown=$true

# ── Audio cell painter ────────────────────────────────────────────────────────
function Set-AudioCell {
    param($Row,[string]$Label,[bool]$IsHeAac)
    $Row.UseItemStyleForSubItems=$false; $Row.SubItems[1].Text=$Label
    if     ($IsHeAac)                     { $Row.SubItems[1].ForeColor=[System.Drawing.Color]::FromArgb(255,140,0) }
    elseif ($Label -eq "—")              { $Row.SubItems[1].ForeColor=[System.Drawing.Color]::FromArgb(90,90,110) }
    else                                  { $Row.SubItems[1].ForeColor=[System.Drawing.Color]::FromArgb(100,220,150) }
}

function Update-FileList {
    $lstFiles.Items.Clear(); $script:DropHintShown=($script:SelectedFiles.Count -eq 0)
    if ($script:SelectedFiles.Count -eq 0) { $lblFileCount.Text="0 files queued"; return }

    $isAudio  = $rbAudio.Checked
    $canProbe = (-not $isAudio) -and $script:FFprobePath -and (Test-Path $script:FFprobePath)

    foreach ($f in $script:SelectedFiles) {
        $row=New-Object System.Windows.Forms.ListViewItem([System.IO.Path]::GetFileName($f))
        $row.SubItems.Add("—")|Out-Null          # Audio col placeholder
        if ($isAudio) {
            $row.SubItems.Add("Scanning…")|Out-Null
            $row.SubItems.Add("")|Out-Null
        } else {
            $row.SubItems.Add("")|Out-Null
            $row.SubItems.Add("")|Out-Null
        }
        $row.UseItemStyleForSubItems=$false
        $row.SubItems[1].ForeColor=[System.Drawing.Color]::FromArgb(90,90,110)  # dim dash
        if ($isAudio) { $row.SubItems[2].ForeColor=[System.Drawing.Color]::FromArgb(110,110,130) }
        $row.Tag=$f; $lstFiles.Items.Add($row)|Out-Null

        # Auto-probe audio for TV/Movie modes if FFprobe is available
        if ($canProbe) {
            $info = Get-AudioInfo $f
            Set-AudioCell $row $info.Label $info.IsHeAac
        }
    }
    $lblFileCount.Text="$($script:SelectedFiles.Count) file(s)"

    # Auto-scan when in Audio Fix mode
    if ($isAudio -and $script:SelectedFiles.Count -gt 0) {
        Invoke-AudioScan
    }
}

function Update-Preview {
    if ($script:SelectedFiles.Count -eq 0 -or $rbAudio.Checked) { return }
    if ($rbTV.Checked) {
        if (-not $script:TVShowData -and -not $script:CachedTVEntries) { return }
        $manualOverride = $chkManualOverride.Checked
        $fallbackSeason = [int]$txtSeason.Text.Trim()
        $fallbackStartEp = [int]$txtStartEp.Text.Trim()

        # Sequential fallback counter per season (for files with no SxxEyy in name)
        $seqCounters = @{}

        foreach ($row in $lstFiles.Items) {
            $f    = $row.Tag
            $ext  = [System.IO.Path]::GetExtension($f)
            $det  = Get-SeasonEpisodeFromPath $f

                if ($manualOverride) {
                $season = $fallbackSeason
                if (-not $seqCounters.ContainsKey($season)) { $seqCounters[$season] = $fallbackStartEp }
                $epNum = $seqCounters[$season]
                $seqCounters[$season]++
            } else {
                # Season: explicit season can be overridden if manual override is enabled
                $season = if ($det -and $det.Season) { $det.Season } else { $fallbackSeason }

                # Episode: from filename > sequential counter per season
                if (-not $seqCounters.ContainsKey($season)) { $seqCounters[$season] = $fallbackStartEp }
                $epNum = if ($det -and $det.Episode) {
                    $det.Episode
                } else {
                    $c = $seqCounters[$season]; $seqCounters[$season]++; $c
                }
            }

            $entry = if ($script:CachedTVEntries) { $script:CachedTVEntries | Where-Object { $_.File -eq $f } | Select-Object -First 1 } else { $null }
            if ($entry) {
                # Use per-file show data
                $showName = Sanitize-Filename $entry.ShowName
                $showYear = $entry.ShowYear
                $tmdbId   = [int]([string]$entry.TMDBId)
                # Pre-fetch season for this show
                $cacheKey = [string]$tmdbId + '-' + [string]$season
                if (-not $script:SeasonCache.ContainsKey($cacheKey)) {
                    Write-Log "  Fetching TMDB season metadata for $showName S$season" "Gray"
                }
                Get-SeasonEpisodes $tmdbId $season | Out-Null
            } elseif ($script:TVShowData) {
                # Use single show data
                $showName = Sanitize-Filename $script:TVShowData.name
                $showYear = Get-Year $script:TVShowData.first_air_date
                $tmdbId   = [int]([string]$script:TVShowData.id)
                # Ensure season episode metadata is loaded for the selected show
                $cacheKey = [string]$tmdbId + '-' + [string]$season
                if (-not $script:SeasonCache.ContainsKey($cacheKey)) {
                    Write-Log "  Fetching TMDB season metadata for $showName S$season" "Gray"
                }
                Get-SeasonEpisodes $tmdbId $season | Out-Null
            } else {
                # No show data for this file
                $row.SubItems[2].Text = "No show detected"
                $row.SubItems[3].Text = ""
                continue
            }

            $epMap  = $script:SeasonCache[([string]$tmdbId + '-' + [string]$season)]
            $epObj  = if ($epMap -and $epMap.ContainsKey($epNum)) { $epMap[$epNum] } else { $null }

            if (-not $epObj -and $season -gt 1) {
                $fallbackMap = Get-SeasonEpisodes $tmdbId 1
                if ($fallbackMap -and $fallbackMap.Count -gt 0) {
                    $priorCount = 0
                    for ($s = 1; $s -lt $season; $s++) {
                        $priorCount += ($script:SelectedFiles | Where-Object {
                            $det2 = Get-SeasonEpisodeFromPath $_
                            $det2 -and $det2.Season -eq $s
                        }).Count
                    }
                    $globalEp = $priorCount + $epNum
                    if ($fallbackMap.ContainsKey($globalEp)) {
                        Write-Log "  Fallback: using combined TMDB season 1 metadata for $showName S$season E$epNum -> ep $globalEp" "Gray"
                        $epObj = $fallbackMap[$globalEp]
                    }
                }
            }

            $epName = if ($epObj -and $epObj.name) { Sanitize-Filename $epObj.name } else { "Episode $epNum" }
            $epStr  = "S{0:D2}E{1:D2}" -f $season,$epNum
            $newName = if($chkShowName.Checked){"$showName - $epStr - $epName$ext"}else{"$epStr - $epName$ext"}
            $row.SubItems[2].Text = $newName
            $fileDir2    = [System.IO.Path]::GetDirectoryName($f)
            $parentName2 = [System.IO.Path]::GetFileName($fileDir2)
            if ($chkTVRenameInPlace.Checked -or (Test-IsSeasonFolder $parentName2)) {
                # Already in a season folder or rename-in-place — show filename only
                $row.SubItems[3].Text = $newName
            } else {
                $row.SubItems[3].Text = [System.IO.Path]::Combine("$showName ($showYear)", ("Season {0:D2}" -f $season), $newName)
            }
        }
    } elseif ($script:CachedMovieEntries) {
        foreach ($entry in $script:CachedMovieEntries) {
            $fn=[System.IO.Path]::GetFileName($entry.File)
            $row=$lstFiles.Items | Where-Object {$_.Text -eq $fn}
            if($row){
                $ext=[System.IO.Path]::GetExtension($entry.File); $fn2="$($entry.Title) ($($entry.Year))"
                $newName="$fn2$ext"
                $row.SubItems[2].Text=$newName
                if ($chkMovieRenameInPlace.Checked) {
                    $row.SubItems[3].Text=$newName
                } else {
                    $row.SubItems[3].Text="$fn2\$newName"
                }
            }
        }
    }
}

# ── Audio Scan ────────────────────────────────────────────────────────────────
# ── Invoke-AudioScan: called automatically on file add OR manually via button ──
function Invoke-AudioScan {
    param([switch]$Silent)  # $Silent = skip log header (for per-file incremental scans)
    if ($script:SelectedFiles.Count -eq 0) { return }
    if (-not $script:FFprobePath -or -not (Test-Path $script:FFprobePath)) {
        if (-not $Silent) { Write-Log "FFmpeg not configured — set path in Connect menu first." "Orange" }
        return
    }

    if (-not $Silent) { $log.Clear() }
    Start-Marquee
    if (-not $Silent) { Write-Log "-- Scanning $($script:SelectedFiles.Count) file(s) --" "Cyan" }

    $heCount=0; $okCount=0; $total=$lstFiles.Items.Count; $done=0

    foreach ($row in $lstFiles.Items) {
        $f=$row.Tag; $info=Get-AudioInfo $f
        Set-AudioCell $row $info.Label $info.IsHeAac
        if ($info.IsHeAac) {
            $heCount++
            $row.SubItems[2].Text="Will convert  HE-AAC → AAC LC stereo"
            $row.UseItemStyleForSubItems=$false
            $row.SubItems[2].ForeColor=[System.Drawing.Color]::FromArgb(255,140,0)
            $br = if ($info.Bitrate -gt 0) { "  ~$([int]($info.Bitrate/1000))kbps" } else { "" }
            if (-not $Silent) { Write-Log "  NEEDS FIX   $([System.IO.Path]::GetFileName($f))   [$($info.Label)$br]" "Orange" }
        } else {
            $okCount++
            $row.SubItems[2].Text="OK — will be skipped"
            $row.UseItemStyleForSubItems=$false
            $row.SubItems[2].ForeColor=[System.Drawing.Color]::FromArgb(100,220,150)
            $br2 = if ($info.Bitrate -gt 0) { "  ~$([int]($info.Bitrate/1000))kbps" } else { "" }
            if (-not $Silent) { Write-Log "  OK          $([System.IO.Path]::GetFileName($f))   [$($info.Label)$br2]" "Gray" }
        }
        $done++; Set-Progress ([int](($done/$total)*100))
        [System.Windows.Forms.Application]::DoEvents()
        if ($rbAudio.Checked) { Update-Tally }
        if ($script:CancelFix) {
            Write-Log "-- End Task: stopped by user after $done file(s) --" "Orange"
            break
        }
    }

    $lstFiles.Refresh(); $script:AudioScanDone=$true

    if (-not $Silent) {
        Write-Log "" "Gray"
        if ($heCount -gt 0) {
            Write-Log "$heCount file(s) flagged for conversion   |   $okCount file(s) will be skipped" "Yellow"
            Write-Log "Click Fix Now to proceed." "Cyan"
        } else {
            Write-Log "All files have standard audio — nothing to fix." "LightGreen"
        }
    }
    Stop-Marquee 100
}

$btnAudioScan.Add_Click({
    if ($script:SelectedFiles.Count -eq 0) { Write-Log "No files queued — add files first." "Yellow"; return }
    Invoke-AudioScan
})

# ── File list helpers ─────────────────────────────────────────────────────────
function Sort-MediaFiles {
    param([string[]]$FilePaths)
    $files = $FilePaths | ForEach-Object {
        $fileName = [System.IO.Path]::GetFileName($_)
        $season = $null; $episode = $null
        
        # Try S##E## pattern (case-insensitive)
        if ($fileName -match '(?i)s(\d+)e(\d+)') {
            $season = [int]$Matches[1]
            $episode = [int]$Matches[2]
        }
        # Try #x## or #x### pattern (like 1x01, 2x03)
        elseif ($fileName -match '(?i)(\d+)x(\d+)') {
            $season = [int]$Matches[1]
            $episode = [int]$Matches[2]
        }
        # Try Season ## Episode ## pattern
        elseif ($fileName -match '(?i)season\s+(\d+).*episode\s+(\d+)') {
            $season = [int]$Matches[1]
            $episode = [int]$Matches[2]
        }
        
        @{ Path = $_; FileName = $fileName; Season = $season; Episode = $episode }
    }
    # Sort by: Season (asc), Episode (asc), then by filename (string)
    $sorted = $files | Sort-Object -Property @(
        @{ Expression = { if ($null -eq $_.Season) { 999999 } else { $_.Season } } },
        @{ Expression = { if ($null -eq $_.Episode) { 999999 } else { $_.Episode } } },
        @{ Expression = { $_.FileName } }
    )
    return @($sorted | ForEach-Object { $_.Path })
}

function Add-FilesToList {
    param([string[]]$NewFiles)
    $exts=if($rbAudio.Checked){$txtAudioExts.Text}elseif($rbTV.Checked){$txtExts.Text}else{$txtMovieExts.Text}
    $extArr=$exts -split ',' | ForEach-Object{$_.Trim().ToLower()}
    $added=0
    foreach ($f in $NewFiles) {
        if([System.IO.Directory]::Exists($f)){
            # Recursive scan — AllDirectories so Season subfolders are included
            # Use custom Sort-MediaFiles to handle S##E## ordering properly
            $found = [System.IO.Directory]::GetFiles($f,"*",[System.IO.SearchOption]::AllDirectories) |
                Where-Object { $extArr -contains [System.IO.Path]::GetExtension($_).ToLower() }
            $found = Sort-MediaFiles $found
            foreach ($file in $found) {
                if ($script:SelectedFiles -notcontains $file) { $script:SelectedFiles += $file; $added++ }
            }
        } elseif([System.IO.File]::Exists($f)){
            $ext=[System.IO.Path]::GetExtension($f).ToLower()
            if($extArr -contains $ext -and $script:SelectedFiles -notcontains $f){$script:SelectedFiles+=$f;$added++}
        }
    }
    Update-FileList
    if ($rbTV.Checked) { Invoke-AutoDetectShow } elseif ($rbMovie.Checked) { Invoke-AutoDetectMovie }
    Update-Preview
    return $added
}

$ddo=[System.Windows.Forms.DragEventHandler]{
    if($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)){$_.Effect=[System.Windows.Forms.DragDropEffects]::Copy}
    else{$_.Effect=[System.Windows.Forms.DragDropEffects]::None}
}
$ddd=[System.Windows.Forms.DragEventHandler]{
    $dropped=$_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    if(-not $dropped -or $dropped.Count -eq 0){return}
    $exts=if($rbAudio.Checked){$txtAudioExts.Text}elseif($rbTV.Checked){$txtExts.Text}else{$txtMovieExts.Text}
    $extArr=$exts -split ',' | ForEach-Object{$_.Trim().ToLower()}; $added=0
    foreach ($f in $dropped) {
        if([System.IO.Directory]::Exists($f)){
            # Recursive scan — AllDirectories so Season subfolders are included
            $found = [System.IO.Directory]::GetFiles($f,"*",[System.IO.SearchOption]::AllDirectories) |
                Where-Object { $extArr -contains [System.IO.Path]::GetExtension($_).ToLower() }
            $found = Sort-MediaFiles $found
            foreach ($file in $found) {
                if ($script:SelectedFiles -notcontains $file) { $script:SelectedFiles += $file; $added++ }
            }
        } elseif([System.IO.File]::Exists($f)){
            $ext=[System.IO.Path]::GetExtension($f).ToLower()
            if($extArr -contains $ext -and $script:SelectedFiles -notcontains $f){$script:SelectedFiles+=$f;$added++}
        }
    }
    Update-FileList
    $log.SelectionStart=$log.TextLength;$log.SelectionLength=0
    $log.SelectionColor=[System.Drawing.Color]::FromArgb(100,220,150)
    $log.AppendText("Dropped: $added file(s) added.`n");if($log.SelectionStart -ge ($log.TextLength-2)){$log.ScrollToCaret()};
    if ($rbTV.Checked) { Invoke-AutoDetectShow } elseif ($rbMovie.Checked) { Invoke-AutoDetectMovie }
    Update-Preview
}
$lstFiles.AllowDrop=$true;$lstFiles.Add_DragOver($ddo);$lstFiles.Add_DragDrop($ddd)
$panFiles.AllowDrop=$true;$panFiles.Add_DragOver($ddo);$panFiles.Add_DragDrop($ddd)
# ── Right-click context menu on lstFiles ──────────────────────────────────────
$ctxFiles = New-Object System.Windows.Forms.ContextMenuStrip
$ctxFiles.BackColor    = [System.Drawing.Color]::FromArgb(24,24,36)
$ctxFiles.ForeColor    = [System.Drawing.Color]::FromArgb(210,210,230)
$ctxFiles.Font         = New-Object System.Drawing.Font("Segoe UI",9.5)
$ctxFiles.ShowImageMargin   = $false
$ctxFiles.ShowCheckMargin   = $false
$ctxFiles.Padding      = New-Object System.Windows.Forms.Padding(0,4,0,4)
$ctxFiles.RenderMode   = [System.Windows.Forms.ToolStripRenderMode]::Professional

# Custom renderer for full dark-theme control — guard against re-compilation
if (-not ([System.Management.Automation.PSTypeName]'DarkMenuRenderer').Type) {
Add-Type -TypeDefinition @"
using System.Drawing;
using System.Windows.Forms;

public class DarkMenuRenderer : ToolStripProfessionalRenderer {
    public DarkMenuRenderer() : base() { }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
        e.Graphics.Clear(Color.FromArgb(24, 24, 36));
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        var item = e.Item;
        var g    = e.Graphics;
        var rect = new Rectangle(4, 0, item.Width - 8, item.Height);
        if (item.Selected && item.Enabled) {
            using (var b = new SolidBrush(Color.FromArgb(50, 100, 180)))
                g.FillRectangle(b, rect);
            // left accent bar
            using (var b = new SolidBrush(Color.FromArgb(99, 160, 255)))
                g.FillRectangle(b, new Rectangle(4, 2, 3, item.Height - 4));
        }
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
        var g = e.Graphics;
        int y = e.Item.Height / 2;
        using (var p = new Pen(Color.FromArgb(55, 55, 75)))
            g.DrawLine(p, 12, y, e.Item.Width - 12, y);
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
        if (e.Item.ForeColor != Color.White && e.Item.ForeColor != SystemColors.ControlText && e.Item.ForeColor != SystemColors.Control)
            e.TextColor = e.Item.ForeColor;
        else
            e.TextColor = e.Item.Selected
                ? Color.FromArgb(240, 240, 255)
                : (e.Item.Enabled ? Color.FromArgb(200, 200, 225) : Color.FromArgb(100, 100, 120));
        base.OnRenderItemText(e);
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) {
        using (var p = new Pen(Color.FromArgb(60, 60, 85)))
            e.Graphics.DrawRectangle(p, 0, 0, e.AffectedBounds.Width - 1, e.AffectedBounds.Height - 1);
    }
}
"@ -ReferencedAssemblies System.Windows.Forms, System.Drawing
} # end if type not exists

$ctxFiles.Renderer = New-Object DarkMenuRenderer

# Open Folder — primary action, slightly larger + accent colour
$mnuSearchMedia = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuSearchMedia.Text   = "    Search TMDB/AniList"
$mnuSearchMedia.Font   = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
$mnuSearchMedia.ForeColor = [System.Drawing.Color]::FromArgb(100, 220, 180)
$mnuSearchMedia.Padding = New-Object System.Windows.Forms.Padding(8, 5, 16, 5)

# Open Folder — primary action, slightly larger + accent colour
$mnuOpenFolder = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuOpenFolder.Text   = "    Open Folder Location"
$mnuOpenFolder.Font   = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
$mnuOpenFolder.ForeColor = [System.Drawing.Color]::FromArgb(100, 180, 255)
$mnuOpenFolder.ShortcutKeyDisplayString = "Ctrl+E"
$mnuOpenFolder.Padding = New-Object System.Windows.Forms.Padding(8, 5, 16, 5)

# Copy Path — secondary, normal weight
$mnuCopyPath = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuCopyPath.Text   = "    Copy Full Path"
$mnuCopyPath.Font   = New-Object System.Drawing.Font("Segoe UI", 9.5)
$mnuCopyPath.ShortcutKeyDisplayString = "Ctrl+Shift+C"
$mnuCopyPath.Padding = New-Object System.Windows.Forms.Padding(8, 5, 16, 5)

# Divider
$mnuSep = New-Object System.Windows.Forms.ToolStripSeparator
$mnuSep.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)

$null = $ctxFiles.Items.Add($mnuSearchMedia)
$null = $ctxFiles.Items.Add($mnuOpenFolder)
$null = $ctxFiles.Items.Add($mnuSep)
$null = $ctxFiles.Items.Add($mnuCopyPath)

$btnEndTask.Add_Click({
    $script:CancelFix = $true
    $btnEndTask.Enabled = $false
    $btnEndTask.BackColor = [System.Drawing.Color]::FromArgb(220,180,0)
    $btnEndTask.ForeColor = [System.Drawing.Color]::FromArgb(30,30,30)
    $btnEndTask.Text = "Stopping..."
    Write-Log "-- End Task requested by user --" "Orange"
    # Kill any in-progress FFmpeg process immediately
    if ($script:CurrentFFmpegProc -and -not $script:CurrentFFmpegProc.HasExited) {
        try {
            $script:CurrentFFmpegProc.Kill()
            Write-Log "   FFmpeg process terminated immediately." "Orange"
        } catch {
            Write-Log "   Could not kill FFmpeg process: $($_.Exception.Message)" "Red"
        }
        $script:CurrentFFmpegProc = $null
    }
    Write-Log "   Waiting for current operation to finalize..." "Orange"
})

$lstFiles.ContextMenuStrip = $ctxFiles

# Only show menu if a row is actually right-clicked
$ctxFiles.Add_Opening({
    if ($lstFiles.SelectedItems.Count -eq 0) { $_.Cancel = $true }
})

$mnuOpenFolder.Add_Click({
    $item = $lstFiles.SelectedItems[0]; if (-not $item) { return }
    $path = $item.Tag
    if ($path -and (Test-Path $path)) {
        Start-Process explorer.exe "/select,`"$path`""
    } elseif ($path) {
        $dir = [System.IO.Path]::GetDirectoryName($path)
        if ($dir -and (Test-Path $dir)) { Start-Process explorer.exe "`"$dir`"" }
    }
})

$mnuSearchMedia.Add_Click({
    $item = $lstFiles.SelectedItems[0]; if (-not $item) { return }
    Search-SelectedMediaFile $item
})

$mnuCopyPath.Add_Click({
    $item = $lstFiles.SelectedItems[0]; if (-not $item) { return }
    if ($item.Tag) { [System.Windows.Forms.Clipboard]::SetText($item.Tag) }
})

function Search-SelectedMediaFile {
    param([System.Windows.Forms.ListViewItem]$Item)
    if (-not $Item -or -not $Item.Tag) { return }
    if ($rbTV.Checked) {
        Search-SelectedTVFile $Item.Tag
    } elseif ($rbMovie.Checked) {
        Search-SelectedMovieFile $Item.Tag
    } else {
        Write-Log "Right-click search is only available in TV or Movie mode." "Yellow"
    }
}

function Search-SelectedTVFile {
    param([string]$FilePath)
    if ($script:SelectedFiles.Count -eq 0) { return }
    $showData = Find-TMDBShowMatch $FilePath
    if (-not $showData) {
        Write-Log "No TMDB/AniList show match found for: $([IO.Path]::GetFileName($FilePath))" "Yellow"
        return
    }

    $showName = if ($showData.name) { $showData.name } else { $showData.original_name }
    $showYear = Get-Year $showData.first_air_date
    $tmdbId = $showData.id

    Write-Log "-- Right-click search result: $showName ($showYear) --" "Cyan"

    $entries = New-Object System.Collections.Generic.List[hashtable]
    foreach ($f in $script:SelectedFiles) {
        if (Matches-ShowByName $f $showName) {
            $entries.Add(@{File=$f; ShowData=$showData; ShowName=$showName; ShowYear=$showYear; TMDBId=$tmdbId})
        }
    }

    if ($entries.Count -eq 0) {
        Write-Log "No related files matched the same show." "Yellow"
        return
    }

    $script:CachedTVEntries = $entries
    $script:SeasonCache = @{}
    $lblShowPicked.Text = "$showName ($showYear)"
    $lblShowPicked.ForeColor = [System.Drawing.Color]::FromArgb(100,220,150)

    if ($entries.Count -gt 1) {
        Write-Log "Matched $($entries.Count) file(s) to '$showName'." "LightGreen"
    } else {
        Write-Log "Matched 1 file to '$showName'." "LightGreen"
    }

    Update-Preview
}

function Search-SelectedMovieFile {
    param([string]$FilePath)
    if ($script:SelectedFiles.Count -eq 0) { return }
    $item = Find-TMDBMovieMatch $FilePath
    if (-not $item) {
        Write-Log "No TMDB/AniList movie match found for: $([IO.Path]::GetFileName($FilePath))" "Yellow"
        return
    }

    $title = if ($item.title) { $item.title } else { $item.original_title }
    $year = Get-Year $item.release_date

    Write-Log "-- Right-click search result: $title ($year) --" "Cyan"

    $entries = New-Object System.Collections.Generic.List[hashtable]
    foreach ($f in $script:SelectedFiles) {
        if (Matches-MovieByTitle $f $title) {
            $entries.Add(@{File=$f; Title=$title; Year=$year})
        }
    }

    if ($entries.Count -eq 0) {
        Write-Log "No related files matched the same movie title." "Yellow"
        return
    }

    $script:CachedMovieEntries = $entries
    $script:CachedForFiles = $script:SelectedFiles.Clone()
    $lblMovieMatched.Text = "Matched $($entries.Count) file(s) to '$title'"
    $lblMovieMatched.ForeColor = [System.Drawing.Color]::FromArgb(100,220,150)

    Update-Preview
}

function Open-SelectedListFileLocation {
    param([System.Windows.Forms.ListViewItem]$item)
    if (-not $item -or -not $item.Tag) { return }
    $path = $item.Tag
    if (Test-Path $path) {
        Start-Process explorer.exe "/select,`"$path`""
    } else {
        $dir = [System.IO.Path]::GetDirectoryName($path)
        if ($dir -and (Test-Path $dir)) {
            Start-Process explorer.exe "`"$dir`""
        }
    }
}

$lstFiles.Add_MouseDown({ param($sender,$e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $hit = $lstFiles.HitTest($e.Location)
        if ($hit -and $hit.Item) {
            $lstFiles.SelectedItems.Clear()
            $hit.Item.Selected = $true
        }
    }
})

$lstFiles.Add_MouseClick({ param($sender,$e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $hit = $lstFiles.HitTest($e.Location)
    if (-not $hit -or -not $hit.Item -or -not $hit.SubItem) { return }
    if ($hit.Item.SubItems[0] -ne $hit.SubItem) { return }
    Open-SelectedListFileLocation $hit.Item
})

# Ctrl+E / Ctrl+Shift+C keyboard shortcuts on the list
$lstFiles.Add_KeyDown({param($s,$e)
    if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::E) {
        $mnuOpenFolder.PerformClick(); $e.Handled = $true
    }
    if ($e.Control -and $e.Shift -and $e.KeyCode -eq [System.Windows.Forms.Keys]::C) {
        $mnuCopyPath.PerformClick(); $e.Handled = $true
    }
})

$form.AllowDrop=$true;$form.Add_DragOver($ddo);$form.Add_DragDrop($ddd)

$btnBrowseFolder.Add_Click({$fd=New-Object System.Windows.Forms.FolderBrowserDialog;$fd.Description="Select root folder (subfolders/seasons scanned automatically)";if($fd.ShowDialog() -eq "OK"){$n=Add-FilesToList @($fd.SelectedPath);Write-Log "Folder scan added $n file(s) (recursive)." "LightGreen"}})
$btnAddFiles.Add_Click({$ofd=New-Object System.Windows.Forms.OpenFileDialog;$ofd.Multiselect=$true;$ofd.Title="Select media files";$ofd.Filter="Media Files|*.mkv;*.mp4;*.avi;*.m4v;*.mov;*.wmv|All Files|*.*";if($ofd.ShowDialog() -eq "OK"){$n=Add-FilesToList $ofd.FileNames;Write-Log "Added $n file(s) to queue." "LightGreen"}})
$btnClearSelected.Add_Click({$toRemove=@($lstFiles.SelectedItems|ForEach-Object{$_.Tag});if($toRemove.Count -eq 0){return};$script:SelectedFiles=@($script:SelectedFiles|Where-Object{$toRemove -notcontains $_});$script:CachedMovieEntries=$null;$script:CachedForFiles=@();Update-FileList;Update-Preview;Write-Log "Removed $($toRemove.Count) file(s)." "Gray"})
$btnClearFiles.Add_Click({
    $script:SelectedFiles=@();$script:CachedMovieEntries=$null;$script:CachedForFiles=@()
    $lstFiles.Items.Clear();$script:DropHintShown=$true;$lblFileCount.Text="0 files queued"
    $lblMovieMatched.Text="(none matched)";$lblMovieMatched.ForeColor=[System.Drawing.Color]::FromArgb(130,130,160)
    $script:AudioScanDone=$false;$script:FixingNow=$false;$log.Clear();$prog.Value=0
    $lblTallyFix.Text ="● Failed        0"
    $lblTallyPend.Text="● Pending       0"
    $lblTallyNow.Text ="● Converting    0"
    $lblTallyOk.Text  ="● Operational   0"
    $script:CancelFix=$false; $btnEndTask.Enabled=$false; $btnEndTask.BackColor=[System.Drawing.Color]::FromArgb(100,30,30); $btnEndTask.ForeColor=[System.Drawing.Color]::White; $btnEndTask.Text="End Task"
    $txtShowSearch.Text="";$lblShowPicked.Text="(none picked)";$script:TVShowData=$null
    Write-Log "File list and form fields cleared." "Gray"
})
$lstFiles.Add_KeyDown({param($s,$e);if($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete){$toRemove=@($lstFiles.SelectedItems|ForEach-Object{$_.Tag});if($toRemove.Count -gt 0){$script:SelectedFiles=@($script:SelectedFiles|Where-Object{$toRemove -notcontains $_});Update-FileList;Update-Preview}}})

# ── Bottom divider & actions ──────────────────────────────────────────────────
$divBottom=New-Object System.Windows.Forms.Panel; $divBottom.Size=New-Object System.Drawing.Size(940,1)
$divBottom.BackColor=[System.Drawing.Color]::FromArgb(50,50,68); $divBottom.Anchor=$ANC_BLR
$divBottom.Location=New-Object System.Drawing.Point(12,($form.ClientSize.Height-94)); $form.Controls.Add($divBottom)

$panActions=New-Object System.Windows.Forms.Panel; $panActions.Size=New-Object System.Drawing.Size(940,36)
$panActions.Anchor=$ANC_BLR; $panActions.Location=New-Object System.Drawing.Point(12,($form.ClientSize.Height-88))
$form.Controls.Add($panActions)

$btnRename=New-Btn "Rename Now" 0 4 128 28 $true
$btnUndo=New-Btn "Undo" 136 4 90 28
$btnSaveLog=New-Btn "Save Log" 0 4 100 28; $btnSaveLog.Anchor=$ANC_BR; $btnSaveLog.Visible=$false
$btnClearLog=New-Btn "Clear Log" 0 4 100 28; $btnClearLog.Anchor=$ANC_BR; $btnClearLog.Left=$panActions.Width-100
$btnSaveLog.Left=$panActions.Width-208
$panActions.Controls.AddRange(@($btnRename,$btnUndo,$btnSaveLog,$btnClearLog))

function Update-UndoButton {
    if($script:UndoStack.Count -gt 0){$btnUndo.BackColor=[System.Drawing.Color]::FromArgb(180,100,30);$btnUndo.Text="Undo ($($script:UndoStack.Count))";$btnUndo.Enabled=$true}
    else{$btnUndo.BackColor=[System.Drawing.Color]::FromArgb(45,45,58);$btnUndo.Text="Undo";$btnUndo.Enabled=$false}
}
Update-UndoButton

$prog=New-Object System.Windows.Forms.ProgressBar; $prog.Size=New-Object System.Drawing.Size(940,16)
$prog.Anchor=[System.Windows.Forms.AnchorStyles]::None; $prog.Style="Continuous"
$prog.ForeColor=[System.Drawing.Color]::FromArgb(99,102,241)
$prog.Location=New-Object System.Drawing.Point(12,($form.ClientSize.Height-48)); $form.Controls.Add($prog)

$log=New-Object System.Windows.Forms.RichTextBox; $log.Size=New-Object System.Drawing.Size(940,1)
$log.Anchor=$ANC_BLR; $log.BackColor=[System.Drawing.Color]::FromArgb(10,10,16); $log.ForeColor=[System.Drawing.Color]::White
$log.Font=New-Object System.Drawing.Font("Consolas",8.5); $log.BorderStyle="None"; $log.ReadOnly=$true
$log.ScrollBars=[System.Windows.Forms.RichTextBoxScrollBars]::Both
$log.WordWrap=$false; $log.HideSelection=$false
$log.Location=New-Object System.Drawing.Point(12,($panFiles.Bottom+8)); $log.Height=$divBottom.Top-4-$log.Top
$form.Controls.Add($log)

# Recalculate log/divider/progressbar positions on resize without touching .Text
$form.Add_Resize({
    $cH = $form.ClientSize.Height
    # Progress bar: full width, always 16px tall, pinned 32px from bottom
    $prog.SetBounds(12, $cH - 32, $form.ClientSize.Width - 24, 16)
    # Action panel stays 62px from bottom
    $panActions.Top = $cH - 62
    # Bottom divider stays 72px from bottom
    $divBottom.Top  = $cH - 72
    # Log fills from below the file list down to the divider
    $newLogTop    = $panFiles.Bottom + 8
    $newLogHeight = $divBottom.Top - 4 - $newLogTop
    if ($newLogHeight -lt 40) { $newLogHeight = 40 }
    $log.SuspendLayout()
    $newLogWidth = $form.ClientSize.Width - 24
    $log.SetBounds($log.Left, $newLogTop, $newLogWidth, $newLogHeight)
    $log.ResumeLayout($false)
})

function Write-Log {
    param([string]$Msg,[string]$Color="White")
    $log.SelectionStart=$log.TextLength
    $log.SelectionLength=0
    $log.SelectionColor=Get-LogColor $Color
    $log.AppendText("$Msg`n")
    # Only auto-scroll if the user hasn't manually scrolled up
    $atBottom = ($log.SelectionStart -ge ($log.TextLength - 2))
    if ($atBottom) { $log.ScrollToCaret() }
}

$btnSaveLog.Add_Click({ Save-AudioReport })
$btnClearLog.Add_Click({$log.Clear();$prog.Value=0})

# ── Undo ──────────────────────────────────────────────────────────────────────
$btnUndo.Add_Click({
    if($script:UndoStack.Count -eq 0){return}
    $ans=[System.Windows.Forms.MessageBox]::Show("Undo all $($script:UndoStack.Count) rename(s)?`nFiles will be moved back.","Confirm Undo",[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question)
    if($ans -ne "Yes"){return}
    $log.Clear();$prog.Value=0;$total=$script:UndoStack.Count;$done=0;$errors=0
    Write-Log "-- Undoing $total rename(s) --" "Orange"
    $ops=[System.Collections.Generic.List[hashtable]]::new()
    while($script:UndoStack.Count -gt 0){$ops.Add($script:UndoStack.Pop())}
    foreach($op in $ops){
        Write-Log "$([System.IO.Path]::GetFileName($op.From))" "Gray"
        Write-Log "  -> $([System.IO.Path]::GetFileName($op.To))" "LightGreen"
        try{
            $toDir=[System.IO.Path]::GetDirectoryName($op.To)
            if(-not [System.IO.Directory]::Exists($toDir)){[System.IO.Directory]::CreateDirectory($toDir)|Out-Null}
            Move-Item -LiteralPath $op.From -Destination $op.To -Force
            if($op.Dir -and [System.IO.Directory]::Exists($op.Dir)){
                if(-not @([System.IO.Directory]::GetFileSystemEntries($op.Dir,"*",[System.IO.SearchOption]::AllDirectories))){
                    Remove-Item -LiteralPath $op.Dir -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "  Removed empty folder: $([System.IO.Path]::GetFileName($op.Dir))" "Gray"
                }
            }
        }catch{Write-Log "  ERROR: $($_.Exception.Message)" "Red";$errors++}
        $done++; Set-Progress ([int](($done/$total)*100))
    }
    $script:UndoStack.Clear();Update-UndoButton
    $undoMsg = if($errors -eq 0){"Undo complete — $done file(s) restored."}else{"Undo done with $errors error(s)."}
    Write-Log $undoMsg "Yellow"
    Stop-Marquee 100
})

# ── Main button handler ───────────────────────────────────────────────────────
function Validate-Inputs {
    if(-not $rbAudio.Checked -and -not $script:TMDB_API_KEY){Write-Log "Not connected. Use Connect > Set TMDB API Key first." "Yellow";return $false}
    if($script:SelectedFiles.Count -eq 0){Write-Log "No files queued." "Yellow";return $false}
    if($rbTV.Checked -and -not $script:TVShowData){Write-Log "No TV show selected. Use Search TMDB first." "Yellow";return $false}
    return $true
}

$script:CachedMovieEntries=$null;$script:CachedForFiles=@()

function Build-MovieEntries {
    $entries=New-Object System.Collections.Generic.List[hashtable]
    foreach($f in $script:SelectedFiles){
        $fn=[System.IO.Path]::GetFileName($f)
        $item = Find-TMDBMovieMatch $f
        if ($item) {
            if ($item.title) { $title = $item.title } else { $title = $item.original_title }
            Write-Log "Auto-detected movie for '$fn' -> $title ($(Get-Year $item.release_date))" "Gray"
        } else {
            $item = Show-MovieEntryDialog $fn
        }

        if($item){$entries.Add(@{File=$f;Title=$item.title;Year=(Get-Year $item.release_date)})}else{Write-Log "Skipped: $fn" "Gray"}
    }
    return $entries
}

$btnRename.Add_Click({

    # ── AUDIO FIX mode ────────────────────────────────────────────────────────
    if ($rbAudio.Checked) {
        if($script:SelectedFiles.Count -eq 0){Write-Log "No files queued." "Yellow";return}
        if(-not $script:FFmpegPath -or -not (Test-Path $script:FFmpegPath)){
            [System.Windows.Forms.MessageBox]::Show("FFmpeg is not configured.`nSet path in Connect menu.","FFmpeg Not Configured",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning);return}
        if(-not $script:AudioScanDone){
            [System.Windows.Forms.MessageBox]::Show("Please click Scan Files first so you can review what will change.","Scan First",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information);return}

        $toFix=@($lstFiles.Items | Where-Object {$_.SubItems[1].Text -eq "HE-AAC"})
        if($toFix.Count -eq 0){Write-Log "No HE-AAC files found — nothing to fix." "LightGreen";return}

        $ans=[System.Windows.Forms.MessageBox]::Show(
            "$($toFix.Count) file(s) will be converted from HE-AAC → AAC LC stereo in place.`n$($script:SelectedFiles.Count - $toFix.Count) file(s) will be skipped (already fine).`n`nContinue?",
            "Confirm Audio Fix",[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question)
        if($ans -ne "Yes"){return}

        $log.Clear(); Set-Progress 0
        $script:AudioReport.Clear()
        $script:FixingNow=$false; $script:CancelFix=$false
        $btnEndTask.Enabled=$true; $btnEndTask.Text="End Task"
    Write-Log "-- Audio Fix: converting $($toFix.Count) file(s) --" "Cyan"
        $total=$script:SelectedFiles.Count;$done=0;$fixed=0;$skipped=0

        foreach($row in $lstFiles.Items){
            # ── Check cancel flag before starting each file ──────────────────
            if ($script:CancelFix) {
                Write-Log "-- End Task: stopped before processing $([System.IO.Path]::GetFileName($row.Tag)) --" "Orange"
                break
            }

            $f=$row.Tag;$name=[System.IO.Path]::GetFileName($f)
            if($row.SubItems[1].Text -eq "HE-AAC"){
                Write-Log "Converting: $name" "Orange"
                $script:FixingNow = $true; Update-Tally
                Start-Marquee
                $result=Invoke-HeAacFix $f
                Stop-Marquee ([int](($done+1)/$total*100))
                if($result.Success){
                    $fixed++
                    $newInfo=Get-AudioInfo $f
                    Set-AudioCell $row $newInfo.Label $newInfo.IsHeAac
                    $row.SubItems[2].Text="Fixed — now $($newInfo.Label)"
                    $row.UseItemStyleForSubItems=$false
                    $row.SubItems[2].ForeColor=[System.Drawing.Color]::FromArgb(100,220,150)
                    Write-Log "  Done: $name" "LightGreen"
                    $script:FixingNow = $false; Update-Tally
                    $script:AudioReport.Add(@{File=$name;Status="Fixed";Detail="HE-AAC converted to $($newInfo.Label)";Color="green"})
                } else {
                    $reason = $result.FailReason
                    $row.SubItems[2].Text="Fix failed — $reason"
                    $row.UseItemStyleForSubItems=$false
                    $row.SubItems[2].ForeColor=[System.Drawing.Color]::FromArgb(240,80,80)
                    Write-Log "  FAILED: $name — $reason" "Red"
                    $script:FixingNow = $false; Update-Tally
                    $script:AudioReport.Add(@{File=$name;Status="Failed";Detail=$reason;Color="red"})
                }
            } else {
                $skipped++
                Write-Log "Skipped: $name  [$($row.SubItems[1].Text)]" "Gray"
                $script:AudioReport.Add(@{File=$name;Status="Skipped";Detail="Audio is $($row.SubItems[1].Text) — no fix needed";Color="gray"})
            }
            $done++; Set-Progress ([int](($done/$total)*100))
            [System.Windows.Forms.Application]::DoEvents()
        }
        $lstFiles.Refresh()
        Write-Log "" "Gray"
        if ($script:CancelFix) {
            Write-Log "-- End Task: audio fix stopped by user — $fixed fixed, $skipped skipped, $([math]::Max(0,$toFix.Count-$fixed)) remaining --" "Orange"
        } else {
            Write-Log "Done — $fixed fixed, $skipped skipped." "Yellow"
        }
        $script:FixingNow=$false; $script:CancelFix=$false; Update-Tally
        $btnEndTask.Enabled=$false; $btnEndTask.BackColor=[System.Drawing.Color]::FromArgb(100,30,30); $btnEndTask.ForeColor=[System.Drawing.Color]::White; $btnEndTask.Text="End Task"
        Stop-Marquee 100; $script:AudioScanDone=$false
        return
    }

    # ── TV / MOVIE mode ───────────────────────────────────────────────────────
    if(-not (Validate-Inputs)){return}
    
    # Determine which Rename in Place checkbox to use
    $renameInPlace = if($rbTV.Checked) { $chkTVRenameInPlace.Checked } else { $chkMovieRenameInPlace.Checked }
    
    # Only show confirmation dialog if NOT Rename in Place
    if (-not $renameInPlace) {
        $ans=[System.Windows.Forms.MessageBox]::Show("This will MOVE files on disk.`nFiles can be restored with Undo. Continue?","Confirm Rename",[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
        if($ans -ne "Yes"){return}
    }

    $prog.Value=0;$log.Clear()
    if($rbTV.Checked){
        if ($script:CachedTVEntries) {
            $entries = $script:CachedTVEntries
            Start-RenameJob 'TV' ($entries | ForEach-Object { $_.File }) @{Season=$txtSeason.Text.Trim();StartEp=$txtStartEp.Text.Trim();ManualOverride=$chkManualOverride.Checked;IncludeName=$chkShowName.Checked;Entries=$entries} $null $log $prog $false $renameInPlace
        } else {
            Start-RenameJob 'TV' $script:SelectedFiles @{Season=$txtSeason.Text.Trim();StartEp=$txtStartEp.Text.Trim();ManualOverride=$chkManualOverride.Checked;ShowName=$script:TVShowData.name;ShowYear=(Get-Year $script:TVShowData.first_air_date);ShowTMDBId=$script:TVShowData.id;IncludeName=$chkShowName.Checked} $null $log $prog $false $renameInPlace
        }
        Invoke-DuplicateScan $script:SelectedFiles 'TV' $log
    } else {
        $entries=$script:CachedMovieEntries;Write-Log "(Applying matched files)" "Gray"
        Start-RenameJob 'Movie' ($entries|ForEach-Object{$_.File}) $null @{Entries=$entries} $log $prog $false $renameInPlace
        Invoke-DuplicateScan ($entries|ForEach-Object{$_.File}) 'Movie' $log
    }
    Update-UndoButton;$script:CachedMovieEntries=$null;$script:CachedTVEntries=$null;$script:CachedForFiles=@();$lblMovieMatched.Text="";$lblShowPicked.Text="(none picked)";$script:TVShowData=$null
})

# ── Startup ───────────────────────────────────────────────────────────────────
$script:TMDB_API_KEY=Load-APIKey
$savedFfmpeg=Load-FFmpegPath;if($savedFfmpeg -and (Test-Path $savedFfmpeg)){Set-FFmpegPaths $savedFfmpeg}
Update-ConnectStatus

Write-Log "MediaForge ready." "Cyan"
if($script:TMDB_API_KEY){Write-Log "API key loaded from saved config." "LightGreen"}else{Write-Log "No API key found. Use Connect > Set TMDB API Key." "Yellow"}
Update-ConnectStatus
if($script:FFmpegPath){Write-Log "FFmpeg loaded: $script:FFmpegPath" "LightGreen"}else{Write-Log "FFmpeg not configured. Set path in Connect menu for Audio Fix mode." "Orange"}
Write-Log "Audio column:  orange = HE-AAC (needs fix)   green = fine   — = not scanned yet" "Gray"
Write-Log "-----------------------------------------------------------" "Gray"

[System.Windows.Forms.Application]::Run($form)