; VoiceInk — Inno Setup Installer Script
; Generates a single VoiceInk-Setup.exe installer for Windows

#define MyAppName "VoiceInk"
#define MyAppPublisher "Baljeet Singh"
#define MyAppURL "https://github.com/iambaljeet/VoiceInk"
#define MyAppExeName "VoiceInk.exe"

; Version is passed via /DMyAppVersion=x.x.x on the command line
; Fallback to 1.0.0 if not provided
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

; Source directory is passed via /DSourceDir=... on the command line
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

; Output filename can be overridden via /DMyOutputFilename=...
#ifndef MyOutputFilename
  #define MyOutputFilename "VoiceInk-Windows-x64-Setup"
#endif

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputBaseFilename={#MyOutputFilename}
OutputDir=..\..\
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
DisableProgramGroupPage=yes
LicenseFile=
InfoBeforeFile=

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
