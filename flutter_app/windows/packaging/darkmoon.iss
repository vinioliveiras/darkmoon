; Inno Setup script for the darkmoon Windows installer.
;
; Built by tool/package_windows.sh, which passes AppVersion and SourceDir
; on the command line so nothing here has to be edited per release.
;
; The portable .zip stays the primary artifact for people who want it. This
; exists for the far more common expectation: an installer that puts the
; app in the Start Menu and can be uninstalled from Settings.

#define AppName "darkmoon"
#define AppPublisher "Vini"
#define AppURL "https://darkmoon.pt"
#define AppExe "darkmoon.exe"

[Setup]
; Never change this GUID. It is how Windows recognises an existing
; installation, so a new one would turn every upgrade into a second,
; parallel copy of a 1.3GB application.
AppId={{710b2cdf-4dc1-4ee3-a88f-ff35f00e0523}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; No admin rights by default: nothing here writes outside the install
; directory, so demanding elevation would be asking for a privilege the
; installer does not use. Someone who wants it in Program Files for all
; users can still choose that at the prompt.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName} {#AppVersion}
; lzma2/fast, not /max: the payload is 1.3GB and roughly 1.2GB of that is
; ONNX weights, which barely compress. /max costs a great deal of build
; time for very little size, so this trades a few percent for a packaging
; step that finishes.
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
; The install is large enough that saying so up front is a courtesy.
DiskSpanning=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
