; Inno Setup Compiler Script for Sondra Music Platform
; Compiles the Flutter Windows release bundle into a single setup.exe installer

[Setup]
AppName=Sondra Music
AppVersion=1.0.0
DefaultDirName={autopf}\SondraMusic
DefaultGroupName=Sondra Music
OutputDir=..\build\windows\installer
OutputBaseFilename=SondraSetup
Compression=lzma
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\app_icon.ico
DisableProgramGroupPage=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\sondra.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Sondra Music"; Filename: "{app}\sondra.exe"
Name: "{autodesktop}\Sondra Music"; Filename: "{app}\sondra.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sondra.exe"; Description: "{cm:LaunchProgram,Sondra Music}"; Flags: nowait postinstall skipifsilent
