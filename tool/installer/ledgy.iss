; Build with tool/package_installer.ps1 so the complete validated bundle is used.
#ifndef StageDir
  #error StageDir is required. Use tool/package_installer.ps1.
#endif
#ifndef AppVersion
  #error AppVersion is required.
#endif
#ifndef FileVersion
  #error FileVersion is required.
#endif
#ifndef OutputDir
  #error OutputDir is required.
#endif
#ifndef OutputName
  #error OutputName is required.
#endif

[Setup]
AppId={{33D2267D-7D60-46FE-B3C7-7A48657F27AA}
AppName=Ledgy 2.0
AppVersion={#AppVersion}
AppPublisher=Ledgy
AppComments=Pencatatan keuangan pribadi
DefaultDirName={localappdata}\Programs\Ledgy 2.0
DefaultGroupName=Ledgy 2.0
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
UninstallDisplayName=Ledgy 2.0
UninstallDisplayIcon={app}\ledgy_2_0.exe
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
VersionInfoVersion={#FileVersion}
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
Uninstallable=yes
ChangesAssociations=yes

[Languages]
Name: "indonesian"; MessagesFile: "languages\Indonesian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat shortcut Ledgy 2.0 di Desktop"; GroupDescription: "Shortcut tambahan:"; Flags: unchecked

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Ledgy 2.0"; Filename: "{app}\ledgy_2_0.exe"; WorkingDir: "{app}"; AppUserModelID: "com.ledgy.ledgy2"; AppUserModelToastActivatorCLSID: "28cabc1f-7180-4ed3-b4d4-801d8b7bed0a"
Name: "{autodesktop}\Ledgy 2.0"; Filename: "{app}\ledgy_2_0.exe"; WorkingDir: "{app}"; Tasks: desktopicon; AppUserModelID: "com.ledgy.ledgy2"; AppUserModelToastActivatorCLSID: "28cabc1f-7180-4ed3-b4d4-801d8b7bed0a"

[Registry]
Root: HKCU; Subkey: "Software\Classes\com.ledgy.ledgy2"; ValueType: string; ValueName: ""; ValueData: "URL:Ledgy 2.0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\com.ledgy.ledgy2"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\com.ledgy.ledgy2\DefaultIcon"; ValueType: string; ValueData: "{app}\ledgy_2_0.exe,0"
Root: HKCU; Subkey: "Software\Classes\com.ledgy.ledgy2\shell\open\command"; ValueType: string; ValueData: """{app}\ledgy_2_0.exe"" ""%1"""

[Run]
Filename: "{app}\ledgy_2_0.exe"; WorkingDir: "{app}"; Description: "Buka Ledgy 2.0"; Flags: nowait postinstall skipifsilent

; No UninstallDelete entries: personal databases and user-created files stay intact.
