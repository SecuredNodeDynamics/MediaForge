#define MyAppName "MediaForge"
#define MyAppVersion "1.0"
#define MyAppPublisher "MediaForge"
#define MyAppExeName "MediaForge.exe"
#define FFmpegVer "7.1"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=installer
OutputBaseFilename=MediaForge-install
Compression=lzma
SolidCompression=yes
WizardStyle=modern

SetupIconFile=static\\logo.ico
UninstallDisplayIcon={app}\\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";   Description: "Create a &desktop icon";                            GroupDescription: "Additional icons:"
Name: "startmenuicon"; Description: "Create a &Start Menu shortcut";                     GroupDescription: "Additional icons:"
Name: "ffmpeg";        Description: "Install bundled FFmpeg {#FFmpegVer} (recommended)"; GroupDescription: "Components:"

[Files]
; Main application
Source: "MediaForge.exe";          DestDir: "{app}"; Flags: ignoreversion

; App icon for shortcuts
Source: "static\\logo.ico";        DestDir: "{app}\\static"; Flags: ignoreversion

; README
Source: "README.txt";              DestDir: "{app}"; Flags: ignoreversion isreadme

; Bundled FFmpeg binaries — only installed if ffmpeg task is selected
Source: "ffmpeg\\bin\\ffmpeg.exe";  DestDir: "{app}\\ffmpeg\\bin"; Flags: ignoreversion; Tasks: ffmpeg
Source: "ffmpeg\\bin\\ffprobe.exe"; DestDir: "{app}\\ffmpeg\\bin"; Flags: ignoreversion; Tasks: ffmpeg
Source: "ffmpeg\\bin\\ffplay.exe";  DestDir: "{app}\\ffmpeg\\bin"; Flags: ignoreversion; Tasks: ffmpeg

[Icons]
Name: "{autoprograms}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; Tasks: startmenuicon
Name: "{autodesktop}\\{#MyAppName}";  Filename: "{app}\\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
