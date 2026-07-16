@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM  Einfacher deutscher Starter fuer den Surface-/Tablet-Updater.
REM  Der Kunde sieht nur zwei Arbeitsmodi und Beenden.
REM ============================================================================

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Windows-Tablet-Updater.ps1"

set "APP_DIR=%ProgramData%\SurfaceTabletUpdater\"
set "APP_BAT=%APP_DIR%Tablet-Updater-Starten.bat"
set "APP_PS1=%APP_DIR%Windows-Tablet-Updater.ps1"
set "STARTUP_BAT=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Tablet-Updater-Autostart.bat"

REM Standard fuer den automatischen Wochenlauf.
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

if /I "%~1"=="--warte-auf-dienstag" goto WAIT_FOR_TUESDAY

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo.
    echo [FEHLER] Bitte diese Datei per Rechtsklick ^> Als Administrator ausfuehren starten.
    echo.
    pause
    exit /b 1
)

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
echo Surface / 64GB Windows-Tablet Wartungs-Updater
echo ================================================================
echo.
echo 1 - Jetzt aktualisieren
echo     Speicher bereinigen, Firefox aktualisieren und Windows Updates installieren
echo.
echo 2 - Automatischen Dienstag-Updater starten
echo     Richtet den Wochenlauf ein und laesst ein Hinweisfenster offen
echo.
echo 3 - Probelauf ohne Aenderungen
echo     Zeigt Preflight, Bereinigung und Update-Auswahl nur an
echo.
echo 4 - Beenden
echo.
set /p "CHOICE=Option eingeben [1-4]: "

if "%CHOICE%"=="1" goto UPDATE_NOW
if "%CHOICE%"=="2" goto START_AUTO
if "%CHOICE%"=="3" goto DRY_RUN
if "%CHOICE%"=="4" goto END

echo.
echo Ungueltige Eingabe.
pause
goto MENU

:DRY_RUN
cls
echo Starte Probelauf ohne Aenderungen...
echo.
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" ^
    -Mode UpdateNow ^
    -CleanupLevel Deep ^
    -RegularOnly ^
    -IncludeAutomaticDrivers:$true ^
    -FirefoxUpdateMode %FIREFOX_UPDATE_MODE% ^
    -FirefoxPackageId "%FIREFOX_PACKAGE_ID%" ^
    -FirefoxLocale "%FIREFOX_LOCALE%" ^
    -DisableHibernate:$true ^
    -EnableCompactOS:$true ^
    -RestartPolicy AlwaysAfterInstall ^
    -MaxPasses 4 ^
    -DryRun
echo.
echo Probelauf beendet. Es wurden keine Aenderungen ausgefuehrt.
pause
goto MENU

:UPDATE_NOW
cls
echo Starte die Aktualisierung jetzt...
echo.
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" ^
    -Mode UpdateNow ^
    -CleanupLevel Deep ^
    -RegularOnly ^
    -IncludeAutomaticDrivers:$true ^
    -FirefoxUpdateMode %FIREFOX_UPDATE_MODE% ^
    -FirefoxPackageId "%FIREFOX_PACKAGE_ID%" ^
    -FirefoxLocale "%FIREFOX_LOCALE%" ^
    -DisableHibernate:$true ^
    -EnableCompactOS:$true ^
    -RestartPolicy AlwaysAfterInstall ^
    -MaxPasses 4
echo.
echo Der Lauf ist beendet oder ein Neustart wurde geplant.
pause
goto MENU

:START_AUTO
cls
echo Richte den automatischen Dienstag-Updater ein...
echo.
call :INSTALL_STARTUP_MONITOR
if not "%errorlevel%"=="0" goto MENU

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" ^
    -Mode InstallAutoUpdater ^
    -AutoDay %AUTO_DAY% ^
    -AutoTime %AUTO_TIME% ^
    -CleanupLevel Deep ^
    -RegularOnly ^
    -IncludeAutomaticDrivers:$true ^
    -FirefoxUpdateMode %FIREFOX_UPDATE_MODE% ^
    -FirefoxPackageId "%FIREFOX_PACKAGE_ID%" ^
    -FirefoxLocale "%FIREFOX_LOCALE%" ^
    -DisableHibernate:$true ^
    -EnableCompactOS:$true
if not "%errorlevel%"=="0" (
    echo.
    echo [FEHLER] Der automatische Updater konnte nicht eingerichtet werden.
    pause
    goto MENU
)

echo.
echo Der automatische Dienstag-Updater ist eingerichtet.
echo Dieses Fenster wechselt jetzt in den Wartemodus.
timeout /t 4 /nobreak >nul
goto WAIT_FOR_TUESDAY

:INSTALL_STARTUP_MONITOR
if not exist "%APP_DIR%" mkdir "%APP_DIR%" >nul 2>&1
copy /Y "%~f0" "%APP_BAT%" >nul
if errorlevel 1 (
    echo [FEHLER] Konnte die Startdatei nicht nach ProgramData kopieren.
    pause
    exit /b 1
)

copy /Y "%PS_SCRIPT%" "%APP_PS1%" >nul
if errorlevel 1 (
    echo [FEHLER] Konnte das PowerShell-Skript nicht nach ProgramData kopieren.
    pause
    exit /b 1
)

> "%STARTUP_BAT%" echo @echo off
>> "%STARTUP_BAT%" echo cd /d "%APP_DIR%"
>> "%STARTUP_BAT%" echo call "%APP_BAT%" --warte-auf-dienstag
if errorlevel 1 (
    echo [FEHLER] Konnte den Autostart-Eintrag nicht schreiben.
    pause
    exit /b 1
)

echo Autostart-Eintrag erstellt:
echo %STARTUP_BAT%
exit /b 0

:WAIT_FOR_TUESDAY
title Surface Wartungs-Updater - Bitte nicht schliessen
cls
echo ================================================================
echo Automatischer Surface / Windows-Tablet Wartungs-Updater
echo ================================================================
echo.
echo Bitte dieses Fenster nicht schliessen.
echo Der Wartungs-Updater wartet auf den naechsten Dienstag.
echo Die Updates laufen automatisch als Windows-Aufgabe mit Systemrechten.
echo Dieses Fenster startet nach einer Anmeldung automatisch wieder.
echo.
echo Zeitplan: jede Woche Dienstag um %AUTO_TIME% Uhr.
echo.
schtasks /Query /TN "\SurfaceTabletUpdater\WeeklyAutoUpdater" >nul 2>&1
if errorlevel 1 (
    echo Die Update-Aufgabe wurde noch nicht gefunden.
    echo Bitte Option 2 einmal als Administrator starten.
) else (
    echo Die automatische Windows-Aufgabe ist eingerichtet.
    echo Sie installiert Updates jeden Dienstag automatisch.
)
echo.
echo Dieses Fenster prueft den Status alle 5 Minuten erneut.
timeout /t 300 /nobreak >nul
goto WAIT_FOR_TUESDAY

:END
endlocal
exit /b 0
