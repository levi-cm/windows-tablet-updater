Surface / Windows-Tablet Wartungs-Updater - No-Admin
==================================================

Zweck
-----
Dieses Paket ist die kompromissbereite Variante fuer kleine Windows-Tablets,
wenn keine Administratorrechte verfuegbar sind. Es macht alles, was Windows im
normalen Benutzerkontext sinnvoll erlaubt:

- Benutzer-Temp-Ordner bereinigen
- Browser-Cache von Edge, Chrome, WebView2 und Firefox bereinigen
- Windows Thumbnail-/Icon-Cache des aktuellen Benutzers bereinigen
- Papierkorb des aktuellen Benutzers leeren, soweit Windows es erlaubt
- Firefox ueber vorhandenes WinGet im Benutzerkontext installieren/aktualisieren
- regulaere Windows Updates suchen/anzeigen, soweit die Windows Update API es erlaubt
- Windows Update Einstellungen fuer die manuelle Installation oeffnen
- einen Wochenlauf fuer den aktuellen Benutzer einrichten

Dateien
-------
1. Tablet-Updater-Starten-NoAdmin.bat
   - Diese Datei startet der Kunde.
   - Kein Rechtsklick mit erhoehten Rechten noetig.

2. Windows-Tablet-Updater-NoAdmin.ps1
   - PowerShell-Skript fuer No-Admin-Bereinigung, Firefox, Update-Check und
     den Benutzer-Wochenlauf.

3. ABLAUF-DIAGRAMM.txt
   - Deutsches Text-Diagramm, das den No-Admin-Ablauf erklaert.

Bedienung
---------
Nach dem Start zeigt das Fenster fuenf Eintraege:

1 - Jetzt No-Admin-Wartung ausfuehren
    Fuehrt sofort eine Wartung aus:
    - Benutzer-Caches bereinigen
    - Firefox per WinGet pflegen
    - Windows Updates suchen/anzeigen
    - Windows Update Einstellungen oeffnen

2 - No-Admin Wochenlauf fuer diesen Benutzer einrichten
    Richtet einen Wochenlauf ein:
    - jede Woche Dienstag um 03:30 Uhr
    - nur fuer das aktuelle Benutzerkonto
    - laeuft nur, wenn dieser Benutzer angemeldet ist
    - ein Autostart-Statusfenster wird im Benutzerprofil angelegt

3 - Windows Update Einstellungen oeffnen
    Oeffnet die Windows Update Seite, damit Updates manuell gestartet werden
    koennen.

4 - Probelauf ohne Aenderungen
    Zeigt Preflight, bereinigbare Pfade und angebotene Updates an, ohne Dateien,
    Pakete, Aufgaben oder Windows-Einstellungen zu aendern.

5 - Beenden
    Schliesst das Startmenue.

Sicherheit
----------
Loeschziele werden gegen feste Benutzerpfad-Allowlisten geprueft. WinGet wird
nur mit gueltiger Microsoft-Publishersignatur genutzt; Paketinstallationen aus
der autoritativen WinGet-Quelle verwenden deren SHA256-Manifestpruefung.
`-ExecutionPolicy Bypass` gilt nur fuer den jeweiligen PowerShell-Prozess und
aendert keine persistente Richtlinie.

Protokolle
----------
Die Protokolle liegen hier:

%LOCALAPPDATA%\SurfaceTabletUpdater-NoAdmin\Logs

Was ohne Admin nicht moeglich ist
--------------------------------
Windows blockiert ohne Administratorrechte bewusst mehrere Aktionen. Diese
No-Admin-Variante protokolliert sie als SKIP und bricht deswegen nicht ab:

- Windows Updates automatisch installieren
- Treiber-/Firmwareupdates automatisch installieren
- Windows Update Downloadcache systemweit loeschen
- Windows Update Dienste stoppen/starten
- DISM Komponentenbereinigung ausfuehren
- alte CBS-/DISM-Protokolle systemweit loeschen
- Ruhezustand deaktivieren oder hiberfil.sys entfernen
- CompactOS fuer Systemdateien aktivieren
- SYSTEM-Aufgaben in der Aufgabenplanung erstellen
- Firefox maschinenweit installieren, wenn Windows dafuer Adminrechte verlangt
- WinGet/App Installer systemweit reparieren oder provisionieren

Was bleibt erhalten?
--------------------
- Dokumente
- Downloads
- Desktop-Dateien
- Browser-Cookies und gespeicherte Logins
- Firefox-Bookmarks und Firefox-Profile
- installierte Programme

Wichtige Einschraenkung
-----------------------
Diese Variante ersetzt den Admin-Updater nicht vollstaendig. Sie holt das
Maximum aus einem normalen Benutzerkonto heraus und fuehrt den Benutzer danach
zu Windows Update, wo die eigentliche Systeminstallation manuell gestartet
werden muss.
