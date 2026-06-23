# Windows Tablet Updater

Dieses Repository enthaelt zwei Varianten eines Wartungs-Updaters fuer kleine
Windows-Tablets, zum Beispiel Surface-Go-Geraete mit wenig Speicher.

Die Dateien sind absichtlich in zwei getrennte Ordner aufgeteilt:

```text
mit-admin/
ohne-admin/
```

## Welche Variante soll ich nutzen?

Nutze `mit-admin/`, wenn du Administratorrechte hast und Windows Updates
moeglichst automatisch installieren lassen willst.

Startdatei:

```text
mit-admin/Tablet-Updater-Starten.bat
```

Diese Variante kann mehr tun:

- Speicher systemweit bereinigen
- Firefox gezielt ueber WinGet pflegen
- normale Windows Updates installieren
- automatisch angebotene Treiber-/Firmwareupdates installieren
- Wochenlauf als Windows-Aufgabe mit SYSTEM-Rechten einrichten
- bei Bedarf Neustart und Fortsetzung nach Neustart vorbereiten

Nutze `ohne-admin/`, wenn keine Administratorrechte verfuegbar sind.

Startdatei:

```text
ohne-admin/Tablet-Updater-Starten-NoAdmin.bat
```

Diese Variante holt aus einem normalen Benutzerkonto heraus, was Windows
sinnvoll erlaubt:

- Benutzer-Temp und Benutzer-Caches bereinigen
- Browser-Cache fuer Edge, Chrome, WebView2 und Firefox bereinigen
- Firefox ueber vorhandenes WinGet im Benutzerkontext pflegen
- Windows Updates suchen oder anzeigen, soweit erlaubt
- Windows Update Einstellungen fuer manuelle Installation oeffnen
- Wochenlauf fuer den aktuellen Benutzer einrichten

## Wichtige Einschraenkung

Ohne Administratorrechte kann Windows systemweite Wartung nicht vollstaendig
automatisieren. Die `ohne-admin/` Variante installiert deshalb keine Windows
Updates selbst und erstellt keine SYSTEM-Aufgaben. Sie protokolliert solche
Aktionen als `SKIP`, statt den Lauf komplett abzubrechen.

## Weitere Informationen

Die genauen Bedienungsanleitungen liegen in den jeweiligen Ordnern:

- `mit-admin/readme.md`
- `ohne-admin/readme.md`

Die Ablaufdiagramme liegen hier:

- `mit-admin/ABLAUF-DIAGRAMM.txt`
- `ohne-admin/ABLAUF-DIAGRAMM.txt`
