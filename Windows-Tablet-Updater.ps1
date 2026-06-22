<#
.SYNOPSIS
    Windows-Tablet Update-Werkzeug fuer kleine 64GB Windows-Geraete, z.B. Surface Go 2.

.DESCRIPTION
    Dieses Skript macht Speicher frei, aktualisiert Firefox ueber WinGet, sucht
    regulaere Windows Updates, installiert sie und startet bei Bedarf neu. Es kann
    auch eine geplante Aufgabe installieren, die woechentlich als SYSTEM im
    Hintergrund laeuft.

    Das Skript erzwingt KEINE inkompatiblen Windows-Versionen.
    Feature-Updates wie 23H2 -> 24H2 oder zukuenftige Versionen werden nur dann
    installiert, wenn Windows Update sie dem Geraet normal anbietet.

    Fuer "normale" Updates wird bewusst gefiltert:
    - IsInstalled=0             -> noch nicht installiert
    - IsHidden=0                -> nicht ausgeblendet
    - BrowseOnly=0              -> nicht optional / nicht "extra"
    - AutoSelectOnWebSites=1    -> von Windows Update automatisch auswaehlbar

    Dadurch werden keine optionalen Preview-/Extra-Updates erzwungen.

.NOTES
    - Ausfuehrung: als Administrator oder als SYSTEM.
    - Logs: C:\ProgramData\SurfaceTabletUpdater\Logs
    - Firefox-Update: ueber WinGet, Paket-ID Mozilla.Firefox, keine winget --all Updates
    - WinGet-Bootstrap: zuerst vorhandene Registrierung, dann Microsoft.WinGet.Client,
      danach offizieller App-Installer-Download ueber https://aka.ms/getwinget
    - Installierter Auto-Updater: Windows Aufgabenplanung, TaskPath \SurfaceTabletUpdater\
#>

[CmdletBinding()]
param(
    # UpdateNow: sofort bereinigen + updaten.
    # InstallAutoUpdater: woechentliche SYSTEM-Aufgabe installieren.
    # AutoRun: Modus der woechentlichen Aufgabe.
    # Resume: Fortsetzung nach einem Update-Neustart.
    [ValidateSet('UpdateNow', 'InstallAutoUpdater', 'AutoRun', 'Resume')]
    [string]$Mode = 'UpdateNow',

    # Light: Temp/Cache/Recycling.
    # Deep: zusaetzlich Windows-Update-Downloadcache, DISM-Komponentenbereinigung,
    #       optional Hibernate aus und CompactOS an.
    [ValidateSet('Light', 'Deep')]
    [string]$CleanupLevel = 'Deep',

    # RegularOnly begrenzt die Suche auf normale automatisch ausgewaehlte Updates.
    # Das verhindert optionale/extra Updates.
    [switch]$RegularOnly,

    # Surface-/Firmware-/Treiberupdates koennen als Type='Driver' kommen.
    # Durch AutoSelectOnWebSites=1 und BrowseOnly=0 werden trotzdem nur automatische,
    # nicht-optionale Treiber/Firmware-Updates installiert.
    [bool]$IncludeAutomaticDrivers = $true,

    # FirefoxUpdateMode:
    # - Disabled: Firefox/Winget komplett ignorieren.
    # - UpgradeOnly: Firefox nur aktualisieren, wenn es bereits installiert ist.
    # - InstallIfMissing: Firefox aktualisieren oder, falls es fehlt, per WinGet installieren.
    #   Fuer Kiosk-/Webseiten-Tablets ist InstallIfMissing praktisch, weil Firefox kritisch ist.
    [ValidateSet('Disabled', 'UpgradeOnly', 'InstallIfMissing')]
    [string]$FirefoxUpdateMode = 'InstallIfMissing',

    # Offizielle WinGet-Paket-ID fuer normales Mozilla Firefox.
    # Fuer ESR koennte man spaeter z.B. Mozilla.Firefox.ESR verwenden.
    [string]$FirefoxPackageId = 'Mozilla.Firefox',

    # Locale fuer Firefox. de-DE haelt deutsche Installationen deutsch.
    # Wenn ein Geraet eine andere Sprache nutzt, kann WinGet trotzdem upgraden;
    # beim InstallIfMissing wird bevorzugt Deutsch installiert.
    [string]$FirefoxLocale = 'de-DE',

    # Fuer 64GB-Tablets sinnvoll: loescht hiberfil.sys.
    # Nebenwirkung: Ruhezustand/Fast Startup werden deaktiviert.
    [bool]$DisableHibernate = $true,

    # CompactOS komprimiert Windows-Systemdateien.
    # Das spart Speicher, kann auf schwacher CPU aber minimal Performance kosten.
    [bool]$EnableCompactOS = $true,

    # Never: nie automatisch neustarten.
    # IfNeeded: nur wenn Windows Update/Pending-Reboot es braucht.
    # AlwaysAfterInstall: nach installierten Updates immer neustarten.
    [ValidateSet('Never', 'IfNeeded', 'AlwaysAfterInstall')]
    [string]$RestartPolicy = 'IfNeeded',

    # Standard fuer den Auto-Updater. Die BAT setzt standardmaessig Dienstag 03:30.
    [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
    [string]$AutoDay = 'Tuesday',

    # Uhrzeit im 24h-Format HH:mm.
    [string]$AutoTime = '03:30',

    # Mehrere Update-Durchlaeufe, weil Windows nach einem Update oft noch weitere
    # Updates findet. Bei Reboot-Pflicht wird automatisch ein Resume-Task angelegt.
    [ValidateRange(1, 10)]
    [int]$MaxPasses = 4,

    # Vor dem Neustart warten, damit ein sichtbarer Hinweis oder Remote-Session noch
    # kurz Zeit hat.
    [ValidateRange(10, 3600)]
    [int]$RestartDelaySeconds = 60
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Globale Pfade und Namen
# -----------------------------------------------------------------------------

$AppRoot        = Join-Path $env:ProgramData 'SurfaceTabletUpdater'
$LogDir         = Join-Path $AppRoot 'Logs'
$InstalledPs1   = Join-Path $AppRoot 'Windows-Tablet-Updater.ps1'
$TaskPath       = '\SurfaceTabletUpdater\'
$AutoTaskName   = 'WeeklyAutoUpdater'
$ResumeTaskName = 'ResumeAfterReboot'
$MutexName      = 'Global\SurfaceTabletUpdaterMutex'

# WinGet ist Teil des Microsoft App Installers. Dieser Family-Name ist stabil
# fuer Microsoft.DesktopAppInstaller / winget.exe.
$WingetAppInstallerFamilyName = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'

# Offizieller Microsoft-Kurzlink fuer das aktuelle App-Installer-MSIXBundle.
# Wird nur genutzt, wenn WinGet fehlt und der modulbasierte Repair-Versuch scheitert.
$WingetBootstrapUrl = 'https://aka.ms/getwinget'

New-Item -Path $AppRoot -ItemType Directory -Force | Out-Null
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null

$LogFile = Join-Path $LogDir ('{0}_{1}.log' -f $Mode, (Get-Date -Format 'yyyyMMdd_HHmmss'))

# -----------------------------------------------------------------------------
# Logging und Basisfunktionen
# -----------------------------------------------------------------------------

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
}

function Test-IsAdminOrSystem {
    # SYSTEM hat SID S-1-5-18. Die geplanten Aufgaben laufen damit.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User -and $identity.User.Value -eq 'S-1-5-18') {
        return $true
    }

    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-AdminOrSystem {
    if (-not (Test-IsAdminOrSystem)) {
        throw 'Dieses Skript muss als Administrator oder als SYSTEM ausgefuehrt werden.'
    }
}

function Get-SystemDriveInfo {
    $driveLetter = $env:SystemDrive.TrimEnd(':')
    return Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
}

function Format-BytesGB {
    param([double]$Bytes)
    return ('{0:N2} GB' -f ($Bytes / 1GB))
}

function Write-FreeSpace {
    param([string]$Label)

    $disk = Get-SystemDriveInfo
    Write-Log ('{0}: Frei {1} von {2} auf {3}' -f $Label, (Format-BytesGB $disk.FreeSpace), (Format-BytesGB $disk.Size), $disk.DeviceID)
}

function Copy-SelfToProgramData {
    # Aufgaben sollten nicht auf Downloads/Desktop eines bestimmten Benutzers zeigen.
    # Deshalb kopieren wir das PS1 nach C:\ProgramData\SurfaceTabletUpdater.
    if (-not $PSCommandPath) {
        throw 'PSCommandPath konnte nicht erkannt werden. Bitte Skript als Datei starten, nicht nur in eine Konsole kopieren.'
    }

    $source = [IO.Path]::GetFullPath($PSCommandPath)
    $dest   = [IO.Path]::GetFullPath($InstalledPs1)

    if ($source -ne $dest) {
        Copy-Item -LiteralPath $source -Destination $dest -Force
        Write-Log "PowerShell-Skript nach $dest kopiert."
    }

    return $dest
}

# -----------------------------------------------------------------------------
# Speicherbereinigung
# -----------------------------------------------------------------------------

function Remove-DirectoryContentsSafe {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    foreach ($rawPath in $Paths) {
        $expanded = [Environment]::ExpandEnvironmentVariables($rawPath)
        $resolvedPaths = @(Resolve-Path -Path $expanded -ErrorAction SilentlyContinue)

        foreach ($resolved in $resolvedPaths) {
            $path = $resolved.Path
            if (-not (Test-Path -LiteralPath $path)) {
                continue
            }

            Write-Log "Bereinige: $path ($Reason)"

            $items = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue)
            foreach ($item in $items) {
                try {
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                }
                catch {
                    # Viele Cache-Dateien sind waehrend Windows laeuft gesperrt.
                    # Das ist normal; wir protokollieren nur knapp und machen weiter.
                    Write-Log "Konnte nicht loeschen: $($item.FullName) -- $($_.Exception.Message)" 'WARN'
                }
            }
        }
    }
}

function Stop-UpdateServicesForCacheCleanup {
    # Dienste kurz stoppen, damit alte Update-Downloads geloescht werden koennen.
    # Falls ein Dienst sich nicht stoppen laesst, wird weitergemacht.
    $serviceNames = @('wuauserv', 'bits', 'dosvc', 'usosvc')

    foreach ($name in $serviceNames) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -eq $svc) { continue }

        try {
            if ($svc.Status -ne 'Stopped') {
                Write-Log "Stoppe Dienst: $name"
                Stop-Service -Name $name -Force -ErrorAction Stop
                $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
            }
        }
        catch {
            Write-Log "Dienst $name konnte nicht gestoppt werden: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Start-UpdateServices {
    # Nach Cache-Bereinigung Windows-Update-Dienste wieder starten.
    $serviceNames = @('bits', 'wuauserv', 'dosvc')

    foreach ($name in $serviceNames) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -eq $svc) { continue }

        try {
            Write-Log "Starte Dienst: $name"
            Start-Service -Name $name -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Dienst $name konnte nicht gestartet werden: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Clear-WindowsUpdateDownloadCache {
    # Nur Download-/Delivery-Optimization-Cache loeschen, nicht die komplette
    # Windows-Update-Datenbank. Das ist deutlich weniger destruktiv.
    Stop-UpdateServicesForCacheCleanup

    try {
        Remove-DirectoryContentsSafe -Reason 'alter Windows-Update-Downloadcache' -Paths @(
            (Join-Path $env:windir 'SoftwareDistribution\Download'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\DeliveryOptimization\Cache')
        )
    }
    finally {
        Start-UpdateServices
    }
}

function Clear-TempAndCrashFiles {
    # Systemweite und benutzerbezogene Temp-Ordner. Keine Dokumente, Downloads,
    # Cookies oder Profile werden geloescht.
    $paths = @(
        $env:TEMP,
        $env:TMP,
        (Join-Path $env:windir 'Temp'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'),
        (Join-Path $env:windir 'Minidump'),
        (Join-Path $env:windir 'LiveKernelReports'),
        (Join-Path $env:SystemDrive 'Users\*\AppData\Local\Temp')
    )

    Remove-DirectoryContentsSafe -Reason 'Temp-/Fehlerbericht-Dateien' -Paths $paths
}

function Clear-BrowserCaches {
    # Nur Cache-Ordner loeschen. Cookies/Login-Daten bleiben erhalten.
    $userRoot = Join-Path $env:SystemDrive 'Users'
    $profiles = @(Get-ChildItem -LiteralPath $userRoot -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') })

    foreach ($profile in $profiles) {
        $local = Join-Path $profile.FullName 'AppData\Local'
        $browserDataRoots = @(
            (Join-Path $local 'Microsoft\Edge\User Data'),
            (Join-Path $local 'Google\Chrome\User Data')
        )

        foreach ($root in $browserDataRoots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }

            # Chromium-Browserprofile heissen z.B. Default, Profile 1, Profile 2.
            # Es werden nur Cache-Ordner geloescht, nicht Cookies/Login-Daten.
            $browserProfiles = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)
            foreach ($browserProfile in $browserProfiles) {
                $cachePaths = @(
                    (Join-Path $browserProfile.FullName 'Cache'),
                    (Join-Path $browserProfile.FullName 'Code Cache'),
                    (Join-Path $browserProfile.FullName 'GPUCache'),
                    (Join-Path $browserProfile.FullName 'Media Cache'),
                    (Join-Path $browserProfile.FullName 'ShaderCache'),
                    (Join-Path $browserProfile.FullName 'GrShaderCache'),
                    (Join-Path $browserProfile.FullName 'Service Worker\CacheStorage')
                )

                Remove-DirectoryContentsSafe -Reason 'Browser-Cache, keine Cookies' -Paths $cachePaths
            }
        }

        # Firefox speichert Cache separat unter AppData\Local\Mozilla\Firefox\Profiles.
        # Der eigentliche Firefox-Profilordner mit Bookmarks, Cookies und Logins liegt
        # normalerweise unter AppData\Roaming und wird bewusst nicht angefasst.
        $firefoxProfilesRoot = Join-Path $local 'Mozilla\Firefox\Profiles'
        if (Test-Path -LiteralPath $firefoxProfilesRoot) {
            $firefoxProfiles = @(Get-ChildItem -LiteralPath $firefoxProfilesRoot -Directory -Force -ErrorAction SilentlyContinue)
            foreach ($firefoxProfile in $firefoxProfiles) {
                $firefoxCachePaths = @(
                    (Join-Path $firefoxProfile.FullName 'cache2'),
                    (Join-Path $firefoxProfile.FullName 'startupCache'),
                    (Join-Path $firefoxProfile.FullName 'shader-cache'),
                    (Join-Path $firefoxProfile.FullName 'thumbnails')
                )

                Remove-DirectoryContentsSafe -Reason 'Firefox-Cache, keine Cookies' -Paths $firefoxCachePaths
            }
        }
    }
}

function Clear-RecycleBinSafe {
    try {
        Write-Log 'Leere Papierkorb fuer alle Laufwerke.'
        Clear-RecycleBin -Force -ErrorAction Stop
    }
    catch {
        # Fallback fuer Systeme, bei denen Clear-RecycleBin nicht sauber arbeitet.
        Write-Log "Clear-RecycleBin fehlgeschlagen, nutze Fallback: $($_.Exception.Message)" 'WARN'
        Remove-DirectoryContentsSafe -Reason 'Papierkorb-Fallback' -Paths @((Join-Path $env:SystemDrive '$Recycle.Bin'))
    }
}

function Invoke-DismComponentCleanup {
    # Entfernt ersetzte Windows-Komponenten. /ResetBase wird absichtlich NICHT genutzt,
    # damit Updates weiterhin deinstallierbar bleiben.
    $dism = Join-Path $env:windir 'System32\dism.exe'
    if (-not (Test-Path -LiteralPath $dism)) { return }

    Write-Log 'Starte DISM Komponentenbereinigung. Das kann laenger dauern.'
    $proc = Start-Process -FilePath $dism -ArgumentList @('/Online', '/Cleanup-Image', '/StartComponentCleanup', '/NoRestart') -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -in @(0, 3010)) {
        Write-Log "DISM Komponentenbereinigung abgeschlossen. ExitCode=$($proc.ExitCode)"
    }
    else {
        Write-Log "DISM meldet ExitCode=$($proc.ExitCode). Updates koennen trotzdem weiterlaufen." 'WARN'
    }
}

function Disable-HibernationForStorage {
    if (-not $DisableHibernate) { return }

    $powercfg = Join-Path $env:windir 'System32\powercfg.exe'
    if (-not (Test-Path -LiteralPath $powercfg)) { return }

    Write-Log 'Deaktiviere Ruhezustand, um hiberfil.sys Speicher freizugeben.'
    try {
        & $powercfg /hibernate off | Out-Host
    }
    catch {
        Write-Log "powercfg /hibernate off fehlgeschlagen: $($_.Exception.Message)" 'WARN'
    }
}

function Enable-CompactOSForStorage {
    if (-not $EnableCompactOS) { return }

    $compact = Join-Path $env:windir 'System32\compact.exe'
    if (-not (Test-Path -LiteralPath $compact)) { return }

    Write-Log 'Aktiviere CompactOS fuer Windows-Systemdateien. Das kann laenger dauern.'
    try {
        & $compact /CompactOS:always | Out-Host
    }
    catch {
        Write-Log "CompactOS konnte nicht aktiviert werden: $($_.Exception.Message)" 'WARN'
    }
}

function Invoke-StorageCleanup {
    param([ValidateSet('Light', 'Deep')][string]$Level)

    Write-Log "Starte Speicherbereinigung: $Level"
    Write-FreeSpace 'Vor Bereinigung'

    Clear-TempAndCrashFiles
    Clear-BrowserCaches
    Clear-RecycleBinSafe

    if ($Level -eq 'Deep') {
        Clear-WindowsUpdateDownloadCache
        Disable-HibernationForStorage
        Enable-CompactOSForStorage
        Invoke-DismComponentCleanup
    }

    Write-FreeSpace 'Nach Bereinigung'
}


# -----------------------------------------------------------------------------
# WinGet-Bootstrap und Firefox-Update
# -----------------------------------------------------------------------------

function Get-WingetPath {
    # 1) Normaler Weg: winget.exe ist ueber PATH/App Execution Alias verfuegbar.
    $cmd = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }

    # 2) Wenn das Skript als SYSTEM laeuft, fehlt oft der Benutzer-PATH.
    #    Deshalb wird der InstallLocation-Pfad des AppX-Pakets gesucht.
    try {
        $pkg = Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        if ($pkg -and $pkg.InstallLocation) {
            $candidate = Join-Path $pkg.InstallLocation 'winget.exe'
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }
    catch {
        Write-Log "Get-AppxPackage konnte WinGet nicht aufloesen: $($_.Exception.Message)" 'WARN'
    }

    # 3) Letzter lokaler Suchpfad. Zugriff auf WindowsApps kann je nach ACL scheitern,
    #    deshalb alles mit SilentlyContinue.
    try {
        $windowsApps = Join-Path $env:ProgramFiles 'WindowsApps'
        $candidate = Get-ChildItem -LiteralPath $windowsApps -Directory -Filter 'Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe' -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending |
            ForEach-Object { Join-Path $_.FullName 'winget.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1

        if ($candidate) {
            return $candidate
        }
    }
    catch {
        Write-Log "WindowsApps-Suche fuer WinGet fehlgeschlagen: $($_.Exception.Message)" 'WARN'
    }

    return $null
}

function Register-ExistingWingetPackage {
    # Microsoft empfiehlt diesen RegisterByFamilyName-Aufruf, wenn WinGet zwar als
    # App Installer vorhanden ist, aber nach dem ersten Login noch nicht registriert wurde.
    try {
        Write-Log 'Pruefe/registriere vorhandenen App Installer fuer WinGet.'
        Add-AppxPackage -RegisterByFamilyName -MainPackage $WingetAppInstallerFamilyName -ErrorAction Stop
        Start-Sleep -Seconds 3
        return $true
    }
    catch {
        Write-Log "App-Installer-Registrierung nicht erfolgreich oder nicht noetig: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Repair-WingetWithMicrosoftModule {
    # Offizieller Microsoft-Weg fuer automatisches Bootstrapping ist das Modul
    # Microsoft.WinGet.Client mit Repair-WinGetPackageManager -AllUsers.
    # Das benoetigt Internetzugriff auf PowerShell Gallery. Falls das nicht geht,
    # folgt danach der direkte App-Installer-Download ueber aka.ms/getwinget.
    try {
        Write-Log 'Versuche WinGet-Reparatur ueber Microsoft.WinGet.Client PowerShell-Modul.'

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        }
        catch { }

        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Write-Log 'Installiere NuGet Package Provider fuer PowerShell Gallery.'
            Install-PackageProvider -Name NuGet -Force -Scope AllUsers -ErrorAction Stop | Out-Null
        }

        if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue)) {
            Write-Log 'Installiere Microsoft.WinGet.Client aus PowerShell Gallery.'
            Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope AllUsers -Force -AllowClobber -Confirm:$false -ErrorAction Stop
        }

        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop

        if (-not (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue)) {
            throw 'Repair-WinGetPackageManager ist nach Modulimport nicht verfuegbar.'
        }

        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 5
        return $true
    }
    catch {
        Write-Log "Microsoft.WinGet.Client-Reparatur fehlgeschlagen: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Install-WingetFromOfficialBundle {
    # Fallback ohne Klick-Installer: aktuelles App-Installer-MSIXBundle direkt von
    # Microsoft herunterladen und per PowerShell registrieren. Auf Windows 11 sind
    # die benoetigten Abhaengigkeiten normalerweise bereits vorhanden.
    $bundlePath = Join-Path $AppRoot 'Microsoft.DesktopAppInstaller.msixbundle'

    try {
        Write-Log "Lade App Installer / WinGet von $WingetBootstrapUrl herunter."
        $oldProgress = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $WingetBootstrapUrl -OutFile $bundlePath -UseBasicParsing -ErrorAction Stop
        }
        finally {
            $global:ProgressPreference = $oldProgress
        }

        try { Unblock-File -LiteralPath $bundlePath -ErrorAction SilentlyContinue } catch { }

        # Provisioning fuer neue/alle Benutzer versuchen. Wenn das nicht klappt,
        # ist das auf einzelnen Windows-Builds nicht ungewoehnlich; Add-AppxPackage
        # wird danach trotzdem versucht.
        try {
            Write-Log 'Versuche App Installer als provisioniertes Paket hinzuzufuegen.'
            Add-AppxProvisionedPackage -Online -PackagePath $bundlePath -SkipLicense -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Log "Provisioning des App Installers fehlgeschlagen: $($_.Exception.Message)" 'WARN'
        }

        Write-Log 'Registriere App Installer fuer den aktuellen Ausfuehrungskontext.'
        Add-AppxPackage -Path $bundlePath -ForceApplicationShutdown -ErrorAction Stop
        Start-Sleep -Seconds 5
        return $true
    }
    catch {
        Write-Log "Direkter WinGet/App-Installer-Download fehlgeschlagen: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Ensure-WingetAvailable {
    # Hauptfunktion fuer den geforderten Ablauf:
    # 1. Pruefen, ob winget schon da ist.
    # 2. Falls nicht: vorhandenen App Installer registrieren.
    # 3. Falls immer noch nicht: offizielles Microsoft-Modul zum Repair nutzen.
    # 4. Falls das fehlschlaegt: offizielles App-Installer-Bundle herunterladen.
    $winget = Get-WingetPath
    if ($winget) {
        Write-Log "WinGet gefunden: $winget"
        return $winget
    }

    Register-ExistingWingetPackage | Out-Null
    $winget = Get-WingetPath
    if ($winget) {
        Write-Log "WinGet nach Registrierung gefunden: $winget"
        return $winget
    }

    Repair-WingetWithMicrosoftModule | Out-Null
    $winget = Get-WingetPath
    if ($winget) {
        Write-Log "WinGet nach Microsoft.WinGet.Client-Reparatur gefunden: $winget"
        return $winget
    }

    Install-WingetFromOfficialBundle | Out-Null
    $winget = Get-WingetPath
    if ($winget) {
        Write-Log "WinGet nach App-Installer-Download gefunden: $winget"
        return $winget
    }

    throw 'WinGet konnte nicht installiert oder gefunden werden.'
}

function Invoke-WingetCommand {
    param(
        [Parameter(Mandatory = $true)][string]$WingetPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int[]]$AcceptedExitCodes = @(0)
    )

    $display = 'winget ' + ($Arguments -join ' ')
    Write-Log "Fuehre aus: $display"

    $output = @()
    try {
        $output = & $WingetPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Log "WinGet-Aufruf konnte nicht gestartet werden: $($_.Exception.Message)" 'WARN'
        return [pscustomobject]@{
            ExitCode = -9999
            Output   = @($_.Exception.Message)
            Success  = $false
        }
    }

    foreach ($line in $output) {
        if ($null -ne $line) {
            Write-Log ('winget: {0}' -f ($line.ToString()))
        }
    }

    $success = $AcceptedExitCodes -contains [int]$exitCode
    if (-not $success) {
        Write-Log "WinGet ExitCode=$exitCode fuer: $display" 'WARN'
    }

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output   = @($output | ForEach-Object { $_.ToString() })
        Success  = [bool]$success
    }
}

function Test-FirefoxInstalledByRegistry {
    # Schneller Fallback, falls winget list unter SYSTEM nicht sauber mappen kann.
    # Es wird nur gelesen, nichts geaendert.
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($root in $uninstallRoots) {
        try {
            $match = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like 'Mozilla Firefox*' } |
                Select-Object -First 1

            if ($match) {
                return $true
            }
        }
        catch { }
    }

    return $false
}

function Test-FirefoxInstalledByWinget {
    param([Parameter(Mandatory = $true)][string]$WingetPath)

    $result = Invoke-WingetCommand -WingetPath $WingetPath -Arguments @(
        'list',
        '--id', $FirefoxPackageId,
        '-e',
        '--accept-source-agreements',
        '--disable-interactivity'
    ) -AcceptedExitCodes @(0, 1)

    $joined = ($result.Output -join "`n")
    if ($joined -match [regex]::Escape($FirefoxPackageId)) {
        return $true
    }

    return $false
}

function Invoke-FirefoxMaintenance {
    if ($FirefoxUpdateMode -eq 'Disabled') {
        Write-Log 'Firefox-Update ist deaktiviert.'
        return
    }

    try {
        Write-Log "Starte Firefox-Maintenance. Mode=$FirefoxUpdateMode PackageId=$FirefoxPackageId Locale=$FirefoxLocale"
        $winget = Ensure-WingetAvailable

        # Quellen aktualisieren, damit neue Firefox-Versionen gefunden werden.
        Invoke-WingetCommand -WingetPath $winget -Arguments @('source', 'update') -AcceptedExitCodes @(0, 1) | Out-Null

        $firefoxInstalled = (Test-FirefoxInstalledByWinget -WingetPath $winget) -or (Test-FirefoxInstalledByRegistry)

        if ($firefoxInstalled) {
            Write-Log 'Firefox ist installiert. Suche/Installiere Firefox-Upgrade ueber WinGet.'

            # Absichtlich NUR Mozilla.Firefox upgraden, kein winget upgrade --all.
            # --silent + --disable-interactivity + Agreements verhindern Klick-Abfragen.
            $upgradeArgs = @(
                'upgrade',
                '--id', $FirefoxPackageId,
                '-e',
                '--source', 'winget',
                '--silent',
                '--scope', 'machine',
                '--locale', $FirefoxLocale,
                '--accept-package-agreements',
                '--accept-source-agreements',
                '--disable-interactivity'
            )

            $result = Invoke-WingetCommand -WingetPath $winget -Arguments $upgradeArgs -AcceptedExitCodes @(0, 1)
            if ($result.Success) {
                Write-Log 'Firefox-Upgrade-Pruefung abgeschlossen.'
            }
            else {
                Write-Log 'Firefox-Upgrade ueber WinGet meldete einen Fehler. Windows Update laeuft trotzdem weiter.' 'WARN'
            }
            return
        }

        if ($FirefoxUpdateMode -eq 'UpgradeOnly') {
            Write-Log 'Firefox ist nicht installiert. UpgradeOnly aktiv, daher keine Neuinstallation.' 'WARN'
            return
        }

        Write-Log 'Firefox ist nicht installiert. InstallIfMissing aktiv, installiere Firefox ueber WinGet.'
        $installArgs = @(
            'install',
            '--id', $FirefoxPackageId,
            '-e',
            '--source', 'winget',
            '--silent',
            '--scope', 'machine',
            '--locale', $FirefoxLocale,
            '--accept-package-agreements',
            '--accept-source-agreements',
            '--disable-interactivity'
        )

        $installResult = Invoke-WingetCommand -WingetPath $winget -Arguments $installArgs -AcceptedExitCodes @(0, 1)
        if ($installResult.Success) {
            Write-Log 'Firefox-Installation abgeschlossen oder war bereits nicht noetig.'
        }
        else {
            Write-Log 'Firefox-Installation ueber WinGet fehlgeschlagen. Windows Update laeuft trotzdem weiter.' 'WARN'
        }
    }
    catch {
        # Firefox darf den Windows-Update-Teil nicht blockieren. Gerade auf 64GB-
        # Geraeten ist es besser, Windows Updates trotzdem auszufuehren.
        Write-Log "Firefox-/WinGet-Teil fehlgeschlagen: $($_.Exception.Message). Windows Update laeuft trotzdem weiter." 'WARN'
    }
}

# -----------------------------------------------------------------------------
# Reboot-Erkennung und Reboot-Handling
# -----------------------------------------------------------------------------

function Test-PendingReboot {
    # Windows hat keinen einzigen perfekten Pending-Reboot-Schalter.
    # Diese bekannten Registry-Orte decken Windows Update und CBS gut ab.
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\Updates\UpdateExeVolatile'
    )

    foreach ($key in $keys) {
        if (Test-Path $key) {
            return $true
        }
    }

    try {
        $sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($null -ne $sessionManager.PendingFileRenameOperations) {
            return $true
        }
    }
    catch { }

    return $false
}

function Request-Restart {
    param([string]$Reason)

    if ($RestartPolicy -eq 'Never') {
        Write-Log "Neustart waere noetig, aber RestartPolicy=Never. Grund: $Reason" 'WARN'
        return
    }

    Write-Log "Plane Neustart in $RestartDelaySeconds Sekunden. Grund: $Reason"
    & shutdown.exe /r /f /t $RestartDelaySeconds /c "SurfaceTabletUpdater: $Reason" | Out-Host
}

# -----------------------------------------------------------------------------
# Windows Update per Windows Update Agent API
# -----------------------------------------------------------------------------

function Convert-WuaResultCode {
    param([int]$Code)

    switch ($Code) {
        0 { return 'NotStarted' }
        1 { return 'InProgress' }
        2 { return 'Succeeded' }
        3 { return 'SucceededWithErrors' }
        4 { return 'Failed' }
        5 { return 'Aborted' }
        default { return "Unknown($Code)" }
    }
}

function New-WuaUpdateCollection {
    return New-Object -ComObject Microsoft.Update.UpdateColl
}

function Add-UpdatesFromCriteria {
    param(
        [Parameter(Mandatory = $true)]$Searcher,
        [Parameter(Mandatory = $true)]$TargetCollection,
        [Parameter(Mandatory = $true)][hashtable]$Seen,
        [Parameter(Mandatory = $true)][string]$Criteria
    )

    Write-Log "Suche Updates mit Kriterien: $Criteria"
    $result = $Searcher.Search($Criteria)
    Write-Log "Gefundene Kandidaten: $($result.Updates.Count)"

    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $update = $result.Updates.Item($i)

        # Eindeutige ID inklusive Revision, damit Dubletten aus Software/Driver-Suchen
        # nicht doppelt installiert werden.
        $identity = '{0}:{1}' -f $update.Identity.UpdateID, $update.Identity.RevisionNumber
        if ($Seen.ContainsKey($identity)) { continue }

        # Beta-Updates nicht installieren.
        try {
            if ($update.IsBeta) {
                Write-Log "Ueberspringe Beta-Update: $($update.Title)" 'WARN'
                continue
            }
        }
        catch { }

        # Hintergrundmodus darf keine Dialoge brauchen.
        try {
            if ($update.InstallationBehavior.CanRequestUserInput) {
                Write-Log "Ueberspringe Update mit moeglicher Benutzerabfrage: $($update.Title)" 'WARN'
                continue
            }
        }
        catch { }

        # EULA automatisch akzeptieren, sonst kann WUA nicht unattended installieren.
        try {
            if (-not $update.EulaAccepted) {
                $update.AcceptEula()
                Write-Log "EULA akzeptiert fuer: $($update.Title)"
            }
        }
        catch {
            Write-Log "EULA konnte nicht akzeptiert werden, ueberspringe: $($update.Title) -- $($_.Exception.Message)" 'WARN'
            continue
        }

        [void]$TargetCollection.Add($update)
        $Seen[$identity] = $true
        Write-Log "Ausgewaehlt: $($update.Title)"
    }
}

function Get-ApplicableUpdates {
    param([bool]$IncludeDrivers)

    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'SurfaceTabletUpdater'

    $searcher = $session.CreateUpdateSearcher()
    $searcher.Online = $true

    $updates = New-WuaUpdateCollection
    $seen = @{}

    # Basiskriterien. RegularOnly ist standardmaessig durch die BAT gesetzt.
    $softwareCriteria = "IsInstalled=0 and IsHidden=0 and Type='Software'"
    $driverCriteria   = "IsInstalled=0 and IsHidden=0 and Type='Driver'"

    if ($RegularOnly) {
        # BrowseOnly=0: keine optionalen Updates.
        # AutoSelectOnWebSites=1: nur Updates, die Windows Update automatisch auswaehlen wuerde.
        $softwareCriteria += ' and BrowseOnly=0 and AutoSelectOnWebSites=1'
        $driverCriteria   += ' and BrowseOnly=0 and AutoSelectOnWebSites=1'
    }

    Add-UpdatesFromCriteria -Searcher $searcher -TargetCollection $updates -Seen $seen -Criteria $softwareCriteria

    if ($IncludeDrivers) {
        Add-UpdatesFromCriteria -Searcher $searcher -TargetCollection $updates -Seen $seen -Criteria $driverCriteria
    }

    return @{
        Session = $session
        Updates = $updates
    }
}

function Invoke-WindowsUpdatePass {
    param([bool]$IncludeDrivers)

    Start-UpdateServices

    $data = Get-ApplicableUpdates -IncludeDrivers:$IncludeDrivers
    $session = $data.Session
    $updates = $data.Updates

    if ($updates.Count -eq 0) {
        Write-Log 'Keine passenden regulaeren Updates gefunden.'
        return [pscustomobject]@{
            SelectedCount   = 0
            InstalledCount  = 0
            RebootRequired  = $false
            ResultCode      = 'NoUpdates'
        }
    }

    Write-Log "Lade $($updates.Count) Update(s) herunter."
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $updates
    $downloadResult = $downloader.Download()
    Write-Log ('Download-Ergebnis: {0}' -f (Convert-WuaResultCode ([int]$downloadResult.ResultCode)))

    $installable = New-WuaUpdateCollection
    for ($i = 0; $i -lt $updates.Count; $i++) {
        $update = $updates.Item($i)
        try {
            if ($update.IsDownloaded) {
                [void]$installable.Add($update)
            }
            else {
                Write-Log "Nicht vollstaendig heruntergeladen, ueberspringe Installation: $($update.Title)" 'WARN'
            }
        }
        catch {
            Write-Log "Downloadstatus konnte nicht gelesen werden: $($update.Title)" 'WARN'
        }
    }

    if ($installable.Count -eq 0) {
        Write-Log 'Keine heruntergeladenen Updates installierbar.' 'WARN'
        return [pscustomobject]@{
            SelectedCount   = $updates.Count
            InstalledCount  = 0
            RebootRequired  = $false
            ResultCode      = 'DownloadIncomplete'
        }
    }

    Write-Log "Installiere $($installable.Count) Update(s)."
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $installable

    # ForceQuiet existiert auf aktuellen Windows-Versionen. Falls nicht, ignorieren.
    try { $installer.ForceQuiet = $true } catch { }

    $installResult = $installer.Install()
    $resultName = Convert-WuaResultCode ([int]$installResult.ResultCode)
    Write-Log "Installations-Ergebnis: $resultName; RebootRequired=$($installResult.RebootRequired)"

    # Details je Update ins Log schreiben.
    for ($i = 0; $i -lt $installable.Count; $i++) {
        try {
            $perUpdate = $installResult.GetUpdateResult($i)
            Write-Log ('UpdateResult: {0} => {1}, HResult={2}' -f $installable.Item($i).Title, (Convert-WuaResultCode ([int]$perUpdate.ResultCode)), $perUpdate.HResult)
        }
        catch {
            Write-Log "Konnte Einzelresultat fuer Update Index $i nicht lesen." 'WARN'
        }
    }

    return [pscustomobject]@{
        SelectedCount   = $updates.Count
        InstalledCount  = $installable.Count
        RebootRequired  = [bool]$installResult.RebootRequired
        ResultCode      = $resultName
    }
}

# -----------------------------------------------------------------------------
# Aufgabenplanung: Auto-Updater und Resume nach Reboot
# -----------------------------------------------------------------------------

function New-PowerShellTaskAction {
    param([string]$Arguments)

    $powershell = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    return New-ScheduledTaskAction -Execute $powershell -Argument $Arguments
}

function Convert-BoolToPsLiteral {
    param([bool]$Value)
    if ($Value) { return '$true' }
    return '$false'
}

function Register-ResumeTask {
    # Wenn ein Update einen Neustart braucht, startet diese Aufgabe nach dem Boot
    # das Skript erneut. Sobald keine Updates mehr ausstehen, loescht das Skript
    # die Aufgabe wieder.
    $scriptPath = Copy-SelfToProgramData

    $driverLiteral     = Convert-BoolToPsLiteral $IncludeAutomaticDrivers
    $hibernateLiteral  = Convert-BoolToPsLiteral $DisableHibernate
    $compactLiteral    = Convert-BoolToPsLiteral $EnableCompactOS

    $args = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode Resume -CleanupLevel Light -RegularOnly -IncludeAutomaticDrivers:{1} -FirefoxUpdateMode {2} -FirefoxPackageId "{3}" -FirefoxLocale "{4}" -DisableHibernate:{5} -EnableCompactOS:{6} -RestartPolicy IfNeeded -MaxPasses {7} -RestartDelaySeconds {8}' -f `
        $scriptPath, $driverLiteral, $FirefoxUpdateMode, $FirefoxPackageId, $FirefoxLocale, $hibernateLiteral, $compactLiteral, $MaxPasses, $RestartDelaySeconds

    $action    = New-PowerShellTaskAction -Arguments $args
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 8) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $task      = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

    Register-ScheduledTask -TaskPath $TaskPath -TaskName $ResumeTaskName -InputObject $task -Force | Out-Null
    Write-Log "Resume-Aufgabe installiert: $TaskPath$ResumeTaskName"
}

function Remove-ResumeTask {
    Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $ResumeTaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Install-AutoUpdaterTask {
    $scriptPath = Copy-SelfToProgramData

    # HH:mm validieren.
    try {
        $time = [TimeSpan]::ParseExact($AutoTime, 'hh\:mm', [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        throw "AutoTime muss im Format HH:mm angegeben werden, z.B. 03:30. Aktuell: $AutoTime"
    }

    $at = [DateTime]::Today.Add($time)

    $driverLiteral     = Convert-BoolToPsLiteral $IncludeAutomaticDrivers
    $hibernateLiteral  = Convert-BoolToPsLiteral $DisableHibernate
    $compactLiteral    = Convert-BoolToPsLiteral $EnableCompactOS

    $args = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode AutoRun -CleanupLevel {1} -RegularOnly -IncludeAutomaticDrivers:{2} -FirefoxUpdateMode {3} -FirefoxPackageId "{4}" -FirefoxLocale "{5}" -DisableHibernate:{6} -EnableCompactOS:{7} -RestartPolicy IfNeeded -MaxPasses {8} -RestartDelaySeconds {9}' -f `
        $scriptPath, $CleanupLevel, $driverLiteral, $FirefoxUpdateMode, $FirefoxPackageId, $FirefoxLocale, $hibernateLiteral, $compactLiteral, $MaxPasses, $RestartDelaySeconds

    $action    = New-PowerShellTaskAction -Arguments $args
    $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $AutoDay -At $at
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 8) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $task      = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

    Register-ScheduledTask -TaskPath $TaskPath -TaskName $AutoTaskName -InputObject $task -Force | Out-Null

    Write-Log "Auto-Updater installiert: $TaskPath$AutoTaskName"
    Write-Log "Zeitplan: Jede Woche $AutoDay um $AutoTime, als SYSTEM, hoechste Rechte."
    Write-Log 'Der Auto-Updater installiert nur normal automatisch angebotene Windows Updates, keine optionalen Extra-Updates.'
    Write-Log "FirefoxUpdateMode=$FirefoxUpdateMode; es wird nur Firefox per WinGet aktualisiert, kein winget upgrade --all."
}

# -----------------------------------------------------------------------------
# Haupt-Workflow
# -----------------------------------------------------------------------------

function Invoke-UpdateWorkflow {
    param(
        [ValidateSet('UpdateNow', 'AutoRun', 'Resume')][string]$RunKind
    )

    # Bei Resume nicht jedes Mal Deep Cleanup wiederholen, sonst dauert die
    # Fortsetzung nach Reboot unnoetig lange.
    if ($RunKind -eq 'Resume') {
        Invoke-StorageCleanup -Level 'Light'
    }
    else {
        Invoke-StorageCleanup -Level $CleanupLevel
    }

    # Nach der Speicherbereinigung, aber vor Windows Update:
    # WinGet pruefen/bei Bedarf installieren und NUR Firefox aktualisieren.
    Invoke-FirefoxMaintenance

    # Warnung, aber nicht abbrechen: Manche 64GB-Geraete schaffen Updates erst nach
    # mehrfacher Bereinigung oder wenn Windows Update selbst Speicher freigibt.
    $disk = Get-SystemDriveInfo
    if ($disk.FreeSpace -lt 8GB) {
        Write-Log ('Sehr wenig Speicher frei: {0}. Feature-Updates koennen daran scheitern.' -f (Format-BytesGB $disk.FreeSpace)) 'WARN'
    }
    elseif ($disk.FreeSpace -lt 15GB) {
        Write-Log ('Wenig Speicher frei: {0}. Kumulative Updates sollten eher klappen; Feature-Updates koennen knapp werden.' -f (Format-BytesGB $disk.FreeSpace)) 'WARN'
    }

    $installedSomething = $false

    for ($pass = 1; $pass -le $MaxPasses; $pass++) {
        Write-Log "Update-Durchlauf $pass von $MaxPasses"

        if (Test-PendingReboot) {
            Write-Log 'Windows meldet bereits vor der Suche einen ausstehenden Neustart.' 'WARN'
            Register-ResumeTask
            Request-Restart 'ausstehender Neustart vor weiterem Update-Durchlauf'
            return
        }

        $result = Invoke-WindowsUpdatePass -IncludeDrivers:$IncludeAutomaticDrivers

        if ($result.InstalledCount -gt 0) {
            $installedSomething = $true
        }

        if ($result.RebootRequired -or (Test-PendingReboot)) {
            Register-ResumeTask
            Request-Restart 'Updates installiert; Neustart erforderlich'
            return
        }

        if ($result.SelectedCount -eq 0) {
            Write-Log 'Keine weiteren Updates in diesem Durchlauf.'
            break
        }

        # Wenn Updates ohne Reboot installiert wurden, direkt noch einmal suchen.
        # Windows findet manchmal erst danach weitere Updates.
    }

    Remove-ResumeTask
    Write-FreeSpace 'Nach Update-Workflow'

    if ($installedSomething -and $RestartPolicy -eq 'AlwaysAfterInstall') {
        Request-Restart 'Update-Workflow abgeschlossen'
    }
    elseif ($installedSomething) {
        Write-Log 'Updates wurden installiert. Kein automatischer Abschluss-Neustart wegen RestartPolicy=IfNeeded.'
    }
    else {
        Write-Log 'Keine Updates installiert. Kein Neustart geplant.'
    }
}

# -----------------------------------------------------------------------------
# Skriptstart mit Mutex, damit nicht zwei Update-Laeufe parallel laufen
# -----------------------------------------------------------------------------

$transcriptStarted = $false
$mutex = $null

try {
    Start-Transcript -Path $LogFile -Append -Force | Out-Null
    $transcriptStarted = $true

    Write-Log "Logfile: $LogFile"
    Write-Log "Mode=$Mode CleanupLevel=$CleanupLevel RegularOnly=$RegularOnly IncludeAutomaticDrivers=$IncludeAutomaticDrivers FirefoxUpdateMode=$FirefoxUpdateMode RestartPolicy=$RestartPolicy"

    Assert-AdminOrSystem

    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($false, $MutexName, [ref]$createdNew)
    if (-not $mutex.WaitOne(0)) {
        Write-Log 'Eine andere Instanz laeuft bereits. Beende diese Instanz.' 'WARN'
        exit 0
    }

    switch ($Mode) {
        'InstallAutoUpdater' {
            Install-AutoUpdaterTask
        }
        'UpdateNow' {
            Copy-SelfToProgramData | Out-Null
            Invoke-UpdateWorkflow -RunKind 'UpdateNow'
        }
        'AutoRun' {
            Invoke-UpdateWorkflow -RunKind 'AutoRun'
        }
        'Resume' {
            Invoke-UpdateWorkflow -RunKind 'Resume'
        }
    }
}
catch {
    Write-Log "FEHLER: $($_.Exception.Message)" 'ERROR'
    Write-Log "Stack: $($_.ScriptStackTrace)" 'ERROR'
    exit 1
}
finally {
    if ($mutex) {
        try { $mutex.ReleaseMutex() | Out-Null } catch { }
        try { $mutex.Dispose() } catch { }
    }

    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}
