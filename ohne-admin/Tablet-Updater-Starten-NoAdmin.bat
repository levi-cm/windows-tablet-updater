@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM  No-Admin Starter fuer den Surface-/Tablet-Updater.
REM  Diese Variante laeuft ohne Adminrechte und aendert nur den aktuellen Benutzer.
REM ============================================================================

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Windows-Tablet-Updater-NoAdmin.ps1"

REM Standard fuer den automatischen Wochenlauf im aktuellen Benutzerkonto.
set "AUTO_DAY=Tuesday"
set "AUTO_TIME=03:30"

REM Firefox wird gezielt gepflegt. Es wird kein "winget upgrade --all" genutzt.
set "FIREFOX_UPDATE_MODE=InstallIfMissing"
set "FIREFOX_PACKAGE_ID=Mozilla.Firefox"
set "FIREFOX_LOCALE=de-DE"

set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" (
    set "POWERSHELL_EXE=%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe"
)

REM ExecutionPolicy Bypass gilt nur je powershell.exe-Prozess. Keine persistente
REM Richtlinie wird geaendert; lokale und geplante Laeufe bleiben unattended.

if not exist "%PS_SCRIPT%" (
    echo.
    echo [FEHLER] PowerShell-Skript nicht gefunden:
    echo %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

:MENU
cls
echo ================================================================
echo Surface / 64GB Windows-Tablet Wartungs-Updater - No-Admin
echo ================================================================
echo.
echo Diese Variante braucht keine Adminrechte.
echo Manche Systemaktionen werden nur protokolliert und uebersprungen.
echo.
echo 1 - Jetzt No-Admin-Wartung ausfuehren
echo     Benutzer-Caches bereinigen, Firefox per WinGet pflegen, Updates anzeigen
echo.
echo 2 - No-Admin Wochenlauf fuer diesen Benutzer einrichten
echo     Laeuft nur, wenn dieser Benutzer angemeldet ist
echo.
echo 3 - Windows Update Einstellungen oeffnen
echo.
echo 4 - Probelauf ohne Aenderungen
echo.
echo 5 - Beenden
echo.
set /p "CHOICE=Option eingeben [1-5]: "

if "%CHOICE%"=="1" goto UPDATE_NOW
if "%CHOICE%"=="2" goto START_AUTO
if "%CHOICE%"=="3" goto OPEN_WU
if "%CHOICE%"=="4" goto DRY_RUN
if "%CHOICE%"=="5" goto END

echo.
echo Ungueltige Eingabe.
pause
goto MENU

:DRY_RUN
cls
echo Starte No-Admin-Probelauf ohne Aenderungen...
echo.
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" ^
    -Mode UpdateNow ^
    -CleanupLevel Deep ^
    -FirefoxUpdateMode %FIREFOX_UPDATE_MODE% ^
    -FirefoxPackageId "%FIREFOX_PACKAGE_ID%" ^
    -FirefoxLocale "%FIREFOX_LOCALE%" ^
    -IncludeAutomaticDrivers:$true ^
    -OpenWindowsUpdateSettings:$true ^
    -DryRun
echo.
echo Probelauf beendet. Es wurden keine Aenderungen ausgefuehrt.
pause
goto MENU

:UPDATE_NOW
cls
echo Starte die No-Admin-Wartung jetzt...
echo.
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" ^
    -Mode UpdateNow ^
    -CleanupLevel Deep ^
    -FirefoxUpdateMode %FIREFOX_UPDATE_MODE% ^
    -FirefoxPackageId "%FIREFOX_PACKAGE_ID%" ^
    -FirefoxLocale "%FIREFOX_LOCALE%" ^
    -IncludeAutomaticDrivers:$true ^
    -OpenWindowsUpdateSettings:$true
echo.
echo Der No-Admin-Lauf ist beendet oder Windows Update wurde geoeffnet.
pause
goto MENU

:START_AUTO
cls
echo Richte den No-Admin Wochenlauf fuer diesen Benutzer ein...
echo.
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" ^
    -Mode InstallAutoUpdater ^
    -AutoDay %AUTO_DAY% ^
    -AutoTime %AUTO_TIME% ^
    -CleanupLevel Deep ^
    -FirefoxUpdateMode %FIREFOX_UPDATE_MODE% ^
    -FirefoxPackageId "%FIREFOX_PACKAGE_ID%" ^
    -FirefoxLocale "%FIREFOX_LOCALE%" ^
    -IncludeAutomaticDrivers:$true ^
    -OpenWindowsUpdateSettings:$false
echo.
echo Der No-Admin Wochenlauf wurde soweit moeglich eingerichtet.
pause
goto MENU

:OPEN_WU
cls
echo Oeffne Windows Update Einstellungen...
echo.
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" ^
    -Mode OpenWindowsUpdateSettings
echo.
pause
goto MENU

:END
endlocal
exit /b 0
