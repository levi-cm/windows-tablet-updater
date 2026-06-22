Surface / Windows-Tablet Wartungs-Updater
=========================================

Zweck
-----
Dieses Paket ist fuer kleine Windows-Tablets mit wenig Speicher gedacht, zum
Beispiel Surface Go Geraete mit 64 GB. Es bereinigt Speicher, aktualisiert
Firefox und installiert normale Windows Updates.

Es werden keine optionalen Preview-/Extra-Updates erzwungen. Es wird auch kein
"winget upgrade --all" ausgefuehrt. Ueber WinGet wird nur Mozilla Firefox
gepflegt.

Dateien
-------
1. Tablet-Updater-Starten.bat
   - Diese Datei startet der Kunde.
   - Rechtsklick -> Als Administrator ausfuehren.

2. Windows-Tablet-Updater.ps1
   - PowerShell-Skript fuer Speicherbereinigung, Firefox, Windows Update und
     den automatischen Wochenlauf.

3. ABLAUF-DIAGRAMM.txt
   - Deutsches Text-Diagramm, das den Ablauf fuer Kunden erklaert.

Bedienung
---------
Nach dem Start zeigt das Fenster nur drei Eintraege:

1 - Jetzt aktualisieren
    Fuehrt sofort eine Wartung aus:
    - Speicher bereinigen
    - Firefox installieren/aktualisieren
    - normale Windows Updates installieren
    - automatisch angebotene Treiber-/Firmwareupdates installieren
    - bei Bedarf neu starten und nach dem Neustart fortsetzen

2 - Automatischen Dienstag-Updater starten
    Richtet den Wochenlauf ein:
    - jede Woche Dienstag um 03:30 Uhr
    - die Updates laufen als Windows-Aufgabe mit Systemrechten
    - ein sichtbares Hinweisfenster bleibt offen
    - das Hinweisfenster startet nach einer Anmeldung automatisch wieder

3 - Beenden
    Schliesst das Startmenue.

Wichtig zum offenen Fenster
---------------------------
Das offene Fenster ist Absicht. Es zeigt:

"Bitte dieses Fenster nicht schliessen."

So erkennt auch jemand ohne Vorwissen, dass das Tablet auf den naechsten
Dienstag wartet und der Wartungs-Updater aktiv ist.

Autostart
---------
Bei Option 2 wird diese Autostart-Datei erstellt:

%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Tablet-Updater-Autostart.bat

Dadurch erscheint das Hinweisfenster nach der naechsten Anmeldung wieder. Die
eigentliche Update-Installation laeuft weiterhin ueber die Windows-Aufgabe mit
Systemrechten.

Protokolle
----------
Die Protokolle liegen hier:

C:\ProgramData\SurfaceTabletUpdater\Logs

Was wird bereinigt?
-------------------
- Windows Temp-Dateien
- Benutzer-Temp-Ordner
- Browser-Cache von Edge, Chrome und Firefox
- WebView2-Cache fuer Kiosk-/Webseiten-Apps
- Windows Thumbnail-/Icon-Cache
- Papierkorb
- Windows Update Downloadcache
- Delivery Optimization Cache
- Windows Fehlerberichte und Crash-Dumps
- alte CBS-/DISM-Protokolle
- ersetzte Windows-Komponenten per DISM-Bereinigung

Was bleibt erhalten?
--------------------
- Dokumente
- Downloads
- Desktop-Dateien
- Browser-Cookies und gespeicherte Logins
- Firefox-Bookmarks und Firefox-Profile
- installierte Programme
