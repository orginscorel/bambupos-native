@echo off
rem BamBumPOS - Windows 7 SP1 x64 baslatma ve denetim betigi (pos-win7 dali).
rem Uygulama acilmiyorsa bunu cift tiklayin; rapor ekranda ve
rem %LOCALAPPDATA%\BamBumPOS\logs\baslat-denetim.txt dosyasinda olur.
setlocal
cd /d "%~dp0"
set "LOGDIR=%LOCALAPPDATA%\BamBumPOS\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
call :denetim > "%LOGDIR%\baslat-denetim.txt" 2>&1
type "%LOGDIR%\baslat-denetim.txt"
echo.
echo Uygulama baslatiliyor... (pencere kapaninca cikis kodu yazilir)
start "" /wait "%~dp0BamBumPOS.exe"
set "KOD=%ERRORLEVEL%"
call :cikis %KOD% >> "%LOGDIR%\baslat-denetim.txt"
call :cikis %KOD%
echo.
echo ---- baslangic.log (son 40 satir) ----
powershell -NoProfile -Command "if (Test-Path '%LOGDIR%\baslangic.log') { Get-Content -Encoding UTF8 -Path '%LOGDIR%\baslangic.log' | Select-Object -Last 40 }" 2>nul
echo --------------------------------------
echo Gunluk klasoru: %LOGDIR%
echo (baslangic.log ve baslat-denetim.txt dosyalarini destek ekibine gonderin)
pause
exit /b %KOD%

:denetim
echo BamBumPOS - Windows 7 baslatma denetimi
echo Tarih: %DATE% %TIME%
echo Klasor: %~dp0
ver
wmic os get Caption,CSDVersion,OSArchitecture,Version /value 2>nul | findstr "="
echo.
echo [Windows guncellemeleri]
echo   KB2670838 = Platform Update (Direct3D 11.1 - Flutter cizimi icin GEREKLI)
echo   KB2999226 / KB3118401 = Universal C Runtime (uygulama klasorunde de var)
echo   KB2533623 / KB3063858 = guvenli DLL yukleme (onerilir)
echo   KB4019990 = d3dcompiler_47.dll (uygulama klasorunde de var)
wmic qfe get HotFixID > "%TEMP%\bbp-kb.txt" 2>nul
for %%K in (KB2670838 KB2999226 KB3118401 KB2533623 KB3063858 KB4019990) do (
  findstr /i "%%K" "%TEMP%\bbp-kb.txt" >nul && (echo   %%K : kurulu) || (echo   %%K : yok)
)
del "%TEMP%\bbp-kb.txt" >nul 2>&1
echo.
echo [Uygulama klasoru]
for %%F in (BamBumPOS.exe flutter_windows.dll url_launcher_windows_plugin.dll vcruntime140.dll vcruntime140_1.dll msvcp140.dll ucrtbase.dll api-ms-win-crt-runtime-l1-1-0.dll d3dcompiler_47.dll data\app.so data\icudtl.dat data\flutter_assets\AssetManifest.json) do (
  if exist "%~dp0%%F" (echo   %%F : var) else (echo   %%F : EKSIK)
)
echo.
echo [Sistem]
if exist "%SystemRoot%\System32\ucrtbase.dll" (echo   Sistem UCRT ucrtbase.dll : var) else (echo   Sistem UCRT ucrtbase.dll : yok - uygulama klasorundeki kullanilir)
if exist "%SystemRoot%\System32\d3d11.dll" (echo   d3d11.dll : var) else (echo   d3d11.dll : YOK)
if exist "%SystemRoot%\System32\d3dcompiler_47.dll" (echo   Sistem d3dcompiler_47.dll : var) else (echo   Sistem d3dcompiler_47.dll : yok - uygulama klasorundeki kullanilir)
wmic path win32_VideoController get Name,DriverVersion /value 2>nul | findstr "="
exit /b 0

:cikis
echo Cikis kodu: %1
if "%1"=="0" echo   = normal kapandi
if "%1"=="-1073741515" echo   = 0xC0000135: bir DLL bulunamadi (VC++/UCRT ya da Windows guncellemesi eksik)
if "%1"=="-1073741511" echo   = 0xC0000139: DLL icinde islev bulunamadi (Windows 8+ islevi / eksik guncelleme)
if "%1"=="-1073741701" echo   = 0xC000007B: 32/64 bit uyumsuz DLL (klasorde yanlis mimari DLL)
if "%1"=="-1073740791" echo   = 0xC0000409: guvenlik denetimi / hizli sonlandirma (motor ici hata)
if "%1"=="-1073741819" echo   = 0xC0000005: bellek erisim hatasi (cokme; logs klasorunde .dmp olabilir)
if "%1"=="-1073741795" echo   = 0xC000001D: islemci komutu desteklenmiyor (cok eski islemci)
if "%1"=="1" echo   = uygulama hata ile kapandi (baslangic.log'a bakin)
exit /b 0
