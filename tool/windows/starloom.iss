; Starloom installer for Windows (built by GitHub Actions with Inno Setup).
; Installs per-user (no admin prompt) and installs over the old version,
; so your library, playlists and settings stay put.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{CEBD12F0-CB30-4BCC-B49E-82FB47766167}
AppName=Starloom
AppVersion={#AppVersion}
AppPublisher=FTSFrosTy
DefaultDirName={localappdata}\Programs\Starloom
DefaultGroupName=Starloom
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=Starloom-Setup
OutputDir=..\..\dist
SetupIconFile=..\icon\app_icon.ico
UninstallDisplayIcon={app}\Starloom.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Close Starloom if it's open so the files can be replaced.
CloseApplications=force
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Put a Starloom shortcut on the desktop"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Starloom"; Filename: "{app}\Starloom.exe"
Name: "{userdesktop}\Starloom"; Filename: "{app}\Starloom.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Starloom.exe"; Description: "Open Starloom"; Flags: nowait postinstall
