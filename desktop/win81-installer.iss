; Instalador alternativo para Windows 8.1, independiente del instalador NSIS anterior.
#define MyAppName "Aquabri System"
#define MyAppVersion "1.0.3"
#define MyAppExeName "Aquabri System Windows 8.1.exe"

[Setup]
AppId={{682EF40D-C151-4921-B7DC-79C8A1DA3E11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Aquabri
AppVerName=Aquabri System Windows 8.1 (1.0.3)
DefaultDirName={localappdata}\Programs\Aquabri System Win81
DefaultGroupName=Aquabri System
DisableDirPage=no
OutputDir=dist
OutputBaseFilename=Aquabri-System-Win81-Instalador-1.0.3
SetupIconFile=build\icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ArchitecturesAllowed=x86 x64
VersionInfoDescription=Instalador Aquabri System Windows 8.1
VersionInfoProductName=Aquabri System
VersionInfoProductVersion=1.0.3

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos:"; Flags: checkedonce

[Files]
Source: "dist\win-ia32-unpacked\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Aquabri System"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Aquabri System"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir Aquabri System"; Flags: nowait postinstall skipifsilent
