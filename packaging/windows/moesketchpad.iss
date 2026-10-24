# MoeSketchpad Windows installer and .moesp file association.
# Build with Inno Setup 6+ after:
#   flutter build windows --release
# The script registers a per-machine association and an image/icon for .moesp.
; SPDX-License-Identifier: GPL-3.0-only

#define MyAppName "萌板 / MoeSketchpad"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Coloryi-MIAO"
#define MyAppURL "https://github.com/Coloryi-MIAO/MoeSketchpad"
#define MyAppExeName "moesketchpad.exe"
#define MyAppId "{{6D6635DB-8A87-4C5B-BC7B-55F2D2A98D3A}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\MoeSketchpad
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputBaseFilename=moesketchpad-{#MyAppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\..\COPYING
InfoBeforeFile=..\..\NOTICE
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "associate"; Description: "Associate .moesp files with MoeSketchpad"; GroupDescription: "Integration:"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\assets\if.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\COPYING"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\NOTICE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\SOURCE-AVAILABILITY.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCR; Subkey: ".moesp"; ValueType: string; ValueName: ""; ValueData: "MoeSketchpad.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKCR; Subkey: ".moesp"; ValueType: string; ValueName: "Content Type"; ValueData: "application/x-moesketchpad"; Flags: uninsdeletevalue; Tasks: associate
Root: HKCR; Subkey: ".moesp"; ValueType: string; ValueName: "PerceivedType"; ValueData: "document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKCR; Subkey: "MoeSketchpad.Document"; ValueType: string; ValueName: ""; ValueData: "MoeSketchpad Geometry Document"; Flags: uninsdeletekey; Tasks: associate
Root: HKCR; Subkey: "MoeSketchpad.Document\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\if.ico,0"; Flags: uninsdeletekey; Tasks: associate
Root: HKCR; Subkey: "MoeSketchpad.Document\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey; Tasks: associate
Root: HKCR; Subkey: "MoeSketchpad.Document\shell\open"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#MyAppName}"; Flags: uninsdeletekey; Tasks: associate
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName}"; Flags: uninsdeletekey
