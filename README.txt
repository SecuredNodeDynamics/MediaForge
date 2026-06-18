MediaForge
TMDB/AniList-powered media toolkit for Jellyfin/Plex

MediaForge is a modular toolkit that cleans, fixes, and organizes your movie, TV, and anime libraries
using TMDB and AniList-powered metadata with a dark-themed WinForms GUI.
It supports TV episode renaming, movie renaming, anime renaming (via AniList), HE-AAC audio repair,
and duplicate detection, with additional media management features planned.

──────────────────────────────────────────────────────────────────────────────
REQUIREMENTS
──────────────────────────────────────────────────────────────────────────────

Windows GUI:
- Windows 10 or 11
- PowerShell 5.1 (built into Windows)
- A free TMDB API key (optional — AniList is used as a fallback without one)
- FFmpeg and ffprobe (required for Audio Fix mode)
- PS2EXE module (only needed if compiling to .exe)

Linux / Windows standalone app:
- Python 3.10+
- ffmpeg and ffprobe from your distribution packages (required for Audio Fix mode)
- A free TMDB API key (optional — AniList fallback works without one)
- PyInstaller (only needed if building the standalone app yourself)

──────────────────────────────────────────────────────────────────────────────
GETTING A TMDB API KEY
──────────────────────────────────────────────────────────────────────────────

1. Go to https://www.themoviedb.org and create a free account.
2. Open Settings -> API -> Create -> Developer.
3. Fill out the form (app name: "MediaForge", personal use is fine).
4. Copy your API Key (v3 auth).

Note: A TMDB API key is optional. If no key is set, MediaForge will fall back to AniList
for anime content, but TMDB-based matching for live-action TV and movies will not be available.

──────────────────────────────────────────────────────────────────────────────
FIRST-TIME SETUP
──────────────────────────────────────────────────────────────────────────────

Linux / Windows desktop app
1. Launch MediaForge from the packaged app:
   Linux:   dist/MediaForge/MediaForge
   Windows: dist\MediaForge\MediaForge.exe
2. Open Settings and set your TMDB key and FFmpeg path.
3. Add files or a folder, click Preview, then click Apply when the proposed changes look right.

Build the standalone app yourself:
  Linux:   ./build-app.sh
  Windows: powershell -ExecutionPolicy Bypass -File .\Build-App.ps1

Build a single-file executable:
  Linux:   ./build-app.sh onefile
  Windows: powershell -ExecutionPolicy Bypass -File .\Build-App.ps1 -Mode onefile

Linux FFmpeg install notes:
1. Install FFmpeg:
   Debian/Ubuntu: sudo apt install ffmpeg
   Fedora:        sudo dnf install ffmpeg
   Arch:          sudo pacman -S ffmpeg

App config storage path:
Linux:   ~/.config/MediaForge/config.json
Windows: %APPDATA%\MediaForge\config.json

Legacy Windows WinForms app
Option A — Run as a script
- Right-click your MediaForge-GUI.ps1 file and choose Run with PowerShell.

Option B — Compile to a standalone .exe
1. Open PowerShell and run:
   Install-Module ps2exe -Scope CurrentUser -Force
2. Run Build-GUI.bat.
3. Your compiled MediaForge.exe will be created in the same folder.
4. Double-click the .exe to launch it.

Note:
- Do not run the .exe as Administrator, or drag-and-drop from Windows Explorer will not work.
- The .exe does not require admin rights.

──────────────────────────────────────────────────────────────────────────────
CONNECTING TMDB AND FFMPEG
──────────────────────────────────────────────────────────────────────────────

TMDB API key
1. Click Connect in the top menu bar.
2. Click Set TMDB API Key.
3. Paste your API key and click Test.
4. Click Save & Close.

FFmpeg / ffprobe
1. Click Connect in the top menu bar.
2. Choose the FFmpeg path option.
3. Select ffmpeg.exe.
4. MediaForge will automatically locate ffprobe.exe from the same folder.

In the cross-platform app, open Settings and choose ffmpeg. MediaForge automatically uses
ffprobe from the same folder or from PATH.

Your TMDB key and FFmpeg path are saved automatically, so this only needs to be done once.

Config storage path:
%APPDATA%\JellyfinRenamer\

Files stored there:
- key.dat    (TMDB API key, Base64-encoded)
- ffmpeg.dat (FFmpeg path, Base64-encoded)

Note:
The config folder is named JellyfinRenamer for backward compatibility.
Both values are stored as Base64 strings — not encrypted. Treat your API key as sensitive.

──────────────────────────────────────────────────────────────────────────────
METADATA SOURCES
──────────────────────────────────────────────────────────────────────────────

MediaForge uses two metadata sources, with automatic fallback:

TMDB (The Movie Database)
- Used for live-action TV shows, movies, and some anime.
- Requires a free API key (see above).
- Supports search by title, TMDB numeric ID, or IMDB ID (e.g. tt0903747).
- Episode names are fetched per season and cached to minimize API calls.

AniList (GraphQL API)
- Used automatically as a fallback when TMDB returns no match, or when no TMDB key is set.
- Covers anime series, OVA, ONA, specials, and anime movies.
- No API key required.
- Title preference order: userPreferred -> english -> romaji -> native.

Auto-detection behavior:
- When files are loaded, MediaForge automatically searches TMDB and AniList to identify the
  show or movie from the filename and parent folder.
- If all files match the same title, single-show mode is used.
- If multiple different titles are detected, multi-show mode activates automatically.
- If no match is found, manual matching is required.

──────────────────────────────────────────────────────────────────────────────
ADDING FILES
──────────────────────────────────────────────────────────────────────────────

You can add media in three ways:

- Drag & drop files or folders anywhere onto the window.
- Click Browse Folder to scan a folder for supported media files.
- Click Add Files to choose individual files manually.

Supported extensions by default:
- .mkv
- .mp4
- .avi

You can edit the Extensions field to add more types, for example:
.m4v,.mov

To remove files from the list:
- Select one or more rows and click Clear Selected, or press Delete.
- Click Clear All to empty the entire queue.

The file list preview shows:
- File Name
- Audio codec detected (e.g. AAC LC, HE-AAC, EAC3, DTS, TrueHD, FLAC, Opus)
- Action / Proposed Name
- Proposed Destination

Audio detection requires ffprobe to be configured. If ffprobe is not set, the Audio column shows "—".

──────────────────────────────────────────────────────────────────────────────
TV SHOW MODE
──────────────────────────────────────────────────────────────────────────────

Manual matching (single show):
1. Select TV Show mode.
2. Type a show name, TMDB ID, or IMDB ID in the Show ID / Name field.
3. Press Enter or click Search TMDB.
4. Pick the correct show from the results list.
5. Set Season # and Start Ep # if needed.
6. Choose whether to include the show name in the final filename.
7. Add your files and review the preview.
8. Click Rename Now to apply the changes.

Auto-detection:
- When files are loaded in TV mode, MediaForge automatically attempts to identify the show
  from each filename and its parent folder using TMDB and AniList.
- If a single show is detected, it is applied automatically.
- If multiple shows are detected across the files (multi-show mode), each file is matched
  and renamed independently.

TV naming output examples:
- Show Name - S01E01 - Episode Title.mkv
- S01E01 - Episode Title.mkv (if "include show name" is disabled)

Season / episode detection:
MediaForge detects season and episode numbers from common patterns, including:
- S01E01 or S1E1
- S01E01-E02 (uses the first episode number)
- 1x01 or 2x03
- Parent folders such as "Season 1", "Season 01", "S01", or "S1"

Fallback behavior:
- If season and episode are detected in the filename, those values are used.
- If only the season is detected from the parent folder, that season is used with Start Ep # for numbering.
- If nothing is detected, the Season # and Start Ep # fields are used as fallback.

Mixed seasons:
You can load multiple seasons of the same show at once, as long as filenames or parent folders
contain usable season information.

Default output folder structure:
Show Name (Year)\Season XX\Show Name - SxxExx - Episode Title.ext

Example:
Show Name (2024)\Season 02\Show Name - S02E03 - Episode Title.mkv

Rename in Place:
If Rename in Place is enabled, MediaForge renames the file in its current folder without
moving it into a new show/season folder structure.
If a file is already inside a folder named "Season XX" or "S##", it is automatically
renamed in place regardless of this setting.

──────────────────────────────────────────────────────────────────────────────
MOVIE MODE
──────────────────────────────────────────────────────────────────────────────

Manual matching:
1. Select Movie mode.
2. Add your movie files.
3. Click Search TMDB in the Movie Options section.
4. For each file:
   - Type the movie title and click Search, or press Enter.
   - Pick the correct result from the list.
   - Or click Skip File to leave that file unchanged.
5. Review the preview.
6. Click Rename Now.

Auto-detection:
- When files are loaded in Movie mode and a TMDB API key is set, MediaForge automatically
  searches for each movie by filename and parent folder name.
- Successfully matched files are previewed immediately without needing manual search.
- Unmatched files require manual search.
- AniList is used as a fallback for anime movies, OVA, ONA, and specials.

Default movie output:
Movie Title (Year)\Movie Title (Year).ext

Rename in Place:
If Rename in Place is enabled, the movie file is renamed in its current folder instead of
being moved into a new folder.

──────────────────────────────────────────────────────────────────────────────
AUDIO FIX MODE
──────────────────────────────────────────────────────────────────────────────

Audio Fix mode detects and repairs problematic HE-AAC audio tracks that cause playback
issues in Jellyfin and other media players.

What it does:
- Scans the first audio stream using ffprobe.
- Detects HE-AAC by codec name, profile string, or low-bitrate heuristic (< 80 kbps).
- Rebuilds audio with FFmpeg using standard AAC LC at 192k stereo.
- Copies the video stream without re-encoding it.

Recognized audio codecs displayed in the Audio column:
- HE-AAC (flagged for fix)
- AAC LC
- AC3, EAC3, DTS, TrueHD, MP3, FLAC, Opus, Vorbis

FFmpeg command used internally:
ffmpeg -i "input" -c:v copy -c:a aac -ac 2 -b:a 192k -y "output"

When Audio Fix mode is active:
- Rename Now changes to Fix Now.
- FFmpeg readiness is shown in the interface.
- Tally counters appear for: Failed, Pending, Converting, and Operational.
- End Task becomes available while a conversion is running to cancel FFmpeg.
- Save Log is available to export the audio processing report.

Conversion process:
- A temporary file (__heaac_fix_<filename>) is created during conversion.
- On success, the original file is replaced with the converted file.
- On failure, the temporary file is deleted and the original is left untouched.
- File size before and after conversion is logged.

Important:
- Audio Fix replaces the original file when conversion succeeds. Review your queue carefully.
- Undo does not apply to audio conversions (see UNDO section below).

──────────────────────────────────────────────────────────────────────────────
DUPLICATE SCANNER
──────────────────────────────────────────────────────────────────────────────

After a rename operation, MediaForge can scan the output for duplicate files.

TV mode: Groups files by SxxExx token and flags any episode that appears more than once.
Movie mode: Groups files by normalized title (alphanumeric characters only, case-insensitive)
            and flags any title that appears more than once.

Duplicate results show file sizes to help decide which copy to keep.

──────────────────────────────────────────────────────────────────────────────
RENAME / FIX NOW
──────────────────────────────────────────────────────────────────────────────

When you click Rename Now or Fix Now:
- A preview is already shown in the file list.
- A confirmation prompt appears before changes are applied.
- Files are moved or renamed on disk.
- In Audio Fix mode, the original file is replaced after a successful conversion.

Important:
- Files are moved, not copied, during rename operations.
- If a file is already named correctly and in the right location, it is skipped automatically.

──────────────────────────────────────────────────────────────────────────────
UNDO
──────────────────────────────────────────────────────────────────────────────

After a rename, the Undo button shows a count such as:
Undo (12)

Undo behavior:
- Moves renamed files back to their original locations.
- Cleans up empty folders created by the rename process.
- Clears the previous undo history when a new rename job starts.

Note:
Undo applies to rename/move operations only. Audio Fix conversions replace the original file
in-place and cannot be undone with this button.

──────────────────────────────────────────────────────────────────────────────
TIPS
──────────────────────────────────────────────────────────────────────────────

- Standard TV naming works best: S01E01 or 1x01.
- Parent folders like "Season 01" or "S01" help when filenames are incomplete.
- Mixed-season batches work best when each file or folder clearly identifies its season.
- TMDB numeric IDs can be pasted directly into the Show ID / Name field.
- IMDB IDs such as tt0903747 also work in the Show ID / Name field.
- If files do not appear after Browse Folder, make sure the extension is listed in the Extensions field.
- For the cleanest season folders, use zero-padded naming such as Season 01, Season 02, etc.
- Auto-detect runs automatically on file load — no button needed.
- If auto-detect finds the wrong show, clear the show selection and search manually.
- AniList fallback is active even without a TMDB API key, so anime libraries work out of the box.

──────────────────────────────────────────────────────────────────────────────
TROUBLESHOOTING
──────────────────────────────────────────────────────────────────────────────

Problem: Drag & drop shows a blocked cursor
Fix: Make sure the .exe is not running as Administrator.

Problem: Not connected or TMDB search fails
Fix: Open Connect and re-enter or retest your TMDB API key.

Problem: Audio Fix says FFmpeg is not configured
Fix on Windows: Open Connect and set the path to ffmpeg.exe. Make sure ffprobe.exe exists in the same folder.
Fix in the cross-platform app: Open Settings and select ffmpeg.

Problem: Files do not appear after Browse Folder
Fix: Add the file extension to the Extensions field.

Problem: Wrong episode names
Fix: Make sure your filenames or season folders contain valid season/episode information,
     or set Season # and Start Ep # correctly as fallback values.

Problem: Build-GUI.bat fails
Fix: Run Install-Module ps2exe -Scope CurrentUser -Force in PowerShell first.

Problem: Preview does not change files
Fix: This is intentional. Click Apply after reviewing the preview.

Problem: Multi-season files are being grouped incorrectly
Fix: Use standard naming such as S01E01, 1x01, "Season 01", or "S01" so MediaForge can
     detect the correct season per file.

Problem: Auto-detect matched the wrong show or movie
Fix: Clear the show/movie selection and use manual TMDB search to set the correct title.

Problem: Anime is not being matched
Fix: AniList fallback is used automatically. If it still fails, try cleaning up your
     filenames — remove codec tags, resolution info, and release group names.

Problem: Audio column shows "—" for all files
Fix on Windows: Set the FFmpeg path via Connect. Both ffmpeg.exe and ffprobe.exe must be in the same folder.
Fix on Linux: Install ffmpeg/ffprobe and confirm ffprobe is in PATH.

──────────────────────────────────────────────────────────────────────────────
FILE STRUCTURE REFERENCE
──────────────────────────────────────────────────────────────────────────────

MediaForge\
  MediaForge.py
  mediaforge_linux.py
  MediaForge-GUI.ps1
  build-app.sh
  Build-App.ps1
  Build-GUI.bat
  MediaForge.exe        (compiled output — generated by Build-GUI.bat)
  README.txt

──────────────────────────────────────────────────────────────────────────────
ABOUT
──────────────────────────────────────────────────────────────────────────────

Built with PowerShell 5.1, WinForms, Python 3, TMDB REST API, AniList GraphQL API, FFmpeg, and ffprobe.
Designed for Jellyfin media library workflows.
Windows includes a dark WinForms UI with custom rounded buttons and menu renderer.
Linux and Windows share the cross-platform MediaForge.py desktop app, packaged with PyInstaller.
