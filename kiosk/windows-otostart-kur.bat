@echo off
REM Kabin PC icin: Windows acilinca Arcade Box kiosk gelsin.
REM Bu bilgisayardaki Cursor / masaustunu degistirmez; sadece Baslangic klasorune kisayol koyar.

cd /d "%~dp0.."
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
if not exist "%STARTUP%" mkdir "%STARTUP%"
copy /Y "%~dp0..\start-kiosk.bat" "%STARTUP%\ArcadeBox.bat" >nul
echo Arcade Box, Windows oturum acilisina eklendi.
echo Kabin PC'de otomatik oturum ac (netplwiz) ve 800x600 cozunurluk kullan.
pause
