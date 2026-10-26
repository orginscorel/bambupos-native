; BamBumPOS POS — Windows kurulum paketi (Inno Setup 6)
; CI: iscc /DSurum=1.0.0 /DKaynak=..\build\windows\x64\runner\Release dagitim\windows-kurulum.iss

#ifndef Surum
  #define Surum "0.0.0"
#endif
#ifndef Kaynak
  #define Kaynak "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6B1E0C52-7A44-4C5B-9E0B-BB05B05A0001}
AppName=BamBumPOS
AppVersion={#Surum}
AppPublisher=BamBumPOS
AppPublisherURL=https://bambumpos.com
DefaultDirName={autopf}\BamBumPOS
DefaultGroupName=BamBumPOS
DisableProgramGroupPage=yes
OutputDir=..\cikti
OutputBaseFilename=BamBumPOS-POS-{#Surum}-Windows-Kurulum
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\BamBumPOS.exe
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "masaustu"; Description: "Masaüstüne kısayol oluştur"; Flags: checkedonce
Name: "baslangic"; Description: "Windows açılınca BamBumPOS'u başlat (kasa / mutfak bilgisayarı için)"; Flags: unchecked

[Files]
Source: "{#Kaynak}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BamBumPOS"; Filename: "{app}\BamBumPOS.exe"
Name: "{autodesktop}\BamBumPOS"; Filename: "{app}\BamBumPOS.exe"; Tasks: masaustu
Name: "{userstartup}\BamBumPOS"; Filename: "{app}\BamBumPOS.exe"; Tasks: baslangic

[Run]
Filename: "{app}\BamBumPOS.exe"; Description: "BamBumPOS'u başlat"; Flags: nowait postinstall skipifsilent
