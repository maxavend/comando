; Comando's installer, like dragging the .dmg to Aplicaciones on a Mac: for
; this user only (no administrator), in the Start menu, and uninstalled from
; Configuración › Aplicaciones. It installs the portable build as is.
;
; CI builds it with:
;   ISCC /DAppVersion=0.2.0 /DPlatform=x64 /DSourceDir=<publish folder> /O<out> Comando.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Platform
  #define Platform "x64"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\out\Comando"
#endif

[Setup]
; Never change AppId: it is how an update finds the installed version.
AppId={{1EFC8335-C105-4E96-9515-2B583597F87A}
AppName=Comando
AppVersion={#AppVersion}
AppVerName=Comando {#AppVersion}
AppPublisher=Maximiliano Avendaño
AppPublisherURL=https://comando.maxavend.com
AppSupportURL=https://github.com/maxavend/comando/issues
AppUpdatesURL=https://comando.maxavend.com/instalar/
VersionInfoVersion={#AppVersion}
; With lowest privileges, {autopf} is %LOCALAPPDATA%\Programs.
PrivilegesRequired=lowest
DefaultDirName={autopf}\Comando
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
OutputBaseFilename=Comando-Windows-{#Platform}-setup
SetupIconFile=..\src\Comando.App\Assets\Comando.ico
UninstallDisplayIcon={app}\Comando.exe
UninstallDisplayName=Comando
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
MinVersion=10.0.19041
; An update closes the running app first.
CloseApplications=force
#if Platform == "ARM64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Comando"; Filename: "{app}\Comando.exe"
Name: "{autodesktop}\Comando"; Filename: "{app}\Comando.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Comando.exe"; Description: "{cm:LaunchProgram,Comando}"; Flags: nowait postinstall skipifsilent
