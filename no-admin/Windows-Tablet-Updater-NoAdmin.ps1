<#
.SYNOPSIS
    No-Admin Windows-Tablet Wartungswerkzeug fuer kleine 64GB Windows-Geraete.

.DESCRIPTION
    Diese Variante laeuft ohne Administratorrechte. Sie nutzt nur
    benutzerbeschreibbare Ordner, bereinigt aktuelle Benutzer-Caches,
    pflegt Firefox ueber vorhandenes WinGet im Benutzerkontext und oeffnet
    Windows Update fuer die manuelle Installation.

    Windows blockiert ohne Administratorrechte bewusst mehrere alte Funktionen:
    Systemweite Windows Updates installieren, SYSTEM-Aufgaben anlegen,
    Dienste stoppen, DISM-Komponentenbereinigung, Ruhezustand abschalten,
    CompactOS aktivieren und maschinenweite Programminstallationen.
    Diese Aktionen werden hier mit SKIP protokolliert, nicht erzwungen.

.NOTES
    - Ausfuehrung: normaler Benutzer, keine Adminrechte noetig.
    - Logs: %LOCALAPPDATA%\SurfaceTabletUpdater-NoAdmin\Logs
    - Firefox: nur Mozilla Firefox per vorhandenem WinGet, bevorzugt --scope user.
    - Windows Update: Suche/Anzeige soweit erlaubt, Installation manuell ueber Einstellungen.
#>

[CmdletBinding()]
param(
    [ValidateSet('UpdateNow', 'InstallAutoUpdater', 'AutoRun', 'OpenWindowsUpdateSettings')]
    [string]$Mode = 'UpdateNow',

    [ValidateSet('Light', 'Deep')]
    [string]$CleanupLevel = 'Deep',

    [ValidateSet('Disabled', 'UpgradeOnly', 'InstallIfMissing')]
    [string]$FirefoxUpdateMode = 'InstallIfMissing',

    [string]$FirefoxPackageId = 'Mozilla.Firefox',

    [string]$FirefoxLocale = 'de-DE',

    [bool]$OpenWindowsUpdateSettings = $true,

    [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
    [string]$AutoDay = 'Tuesday',

    [string]$AutoTime = '03:30',

    [bool]$IncludeAutomaticDrivers = $true
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$RunScope       = 'CurrentUser'
$AppRoot        = Join-Path $env:LOCALAPPDATA 'SurfaceTabletUpdater-NoAdmin'
$LogDir         = Join-Path $AppRoot 'Logs'
$InstalledPs1   = Join-Path $AppRoot 'Windows-Tablet-Updater-NoAdmin.ps1'
$RunnerBat      = Join-Path $AppRoot 'Run-NoAdmin-Weekly.bat'
$TaskName       = 'SurfaceTabletUpdaterNoAdminWeeklyUserUpdater'
$MutexName      = 'Local\SurfaceTabletUpdaterNoAdminMutex'

New-Item -Path $AppRoot -ItemType Directory -Force | Out-Null
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null

$LogFile = Join-Path $LogDir ('{0}_{1}.log' -f $Mode, (Get-Date -Format 'yyyyMMdd_HHmmss'))

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SKIP')][string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
}

function Get-PrivilegeState {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isSystem = ($identity.User -and $identity.User.Value -eq 'S-1-5-18')
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    return [pscustomobject]@{
        UserName = $identity.Name
        IsSystem = [bool]$isSystem
        IsAdmin = [bool]$isAdmin
        Scope = $RunScope
    }
}

function Write-AdminOnlySkip {
    param([Parameter(Mandatory = $true)][string]$What)
    Write-Log "SKIP (Admin noetig): $What" 'SKIP'
}

function Get-SystemDriveInfo {
    try {
        $filter = "DeviceID='$env:SystemDrive'"
        $disk = Get-CimInstance Win32_LogicalDisk -Filter $filter -ErrorAction Stop
        if ($disk) { return $disk }
    }
    catch {
        Write-Log "CIM-Festplatteninfo nicht verfuegbar: $($_.Exception.Message)" 'WARN'
    }

    $drive = New-Object IO.DriveInfo($env:SystemDrive)
    return [pscustomobject]@{
        DeviceID = $env:SystemDrive
        FreeSpace = $drive.AvailableFreeSpace
        Size = $drive.TotalSize
    }
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

function Copy-SelfToLocalAppData {
    if (-not $PSCommandPath) {
        throw 'PSCommandPath konnte nicht erkannt werden. Bitte Skript als Datei starten.'
    }

    $source = [IO.Path]::GetFullPath($PSCommandPath)
    $dest = [IO.Path]::GetFullPath($InstalledPs1)

    if ($source -ne $dest) {
        Copy-Item -LiteralPath $source -Destination $dest -Force
        Write-Log "PowerShell-Skript nach $dest kopiert."
    }

    return $dest
}

function Remove-DirectoryContentsSafe {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    foreach ($rawPath in $Paths) {
        if ([string]::IsNullOrWhiteSpace($rawPath)) { continue }

        $expanded = [Environment]::ExpandEnvironmentVariables($rawPath)
        $resolvedPaths = @(Resolve-Path -Path $expanded -ErrorAction SilentlyContinue)

        foreach ($resolved in $resolvedPaths) {
            $path = $resolved.Path
            if (-not (Test-Path -LiteralPath $path)) { continue }

            Write-Log "Bereinige: $path ($Reason)"
            $items = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue)

            foreach ($item in $items) {
                try {
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                }
                catch {
                    Write-Log "Konnte nicht loeschen: $($item.FullName) -- $($_.Exception.Message)" 'WARN'
                }
            }
        }
    }
}

function Remove-FilePatternsSafe {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    foreach ($rawPath in $Paths) {
        if ([string]::IsNullOrWhiteSpace($rawPath)) { continue }

        $expanded = [Environment]::ExpandEnvironmentVariables($rawPath)
        $resolvedPaths = @(Resolve-Path -Path $expanded -ErrorAction SilentlyContinue)

        foreach ($resolved in $resolvedPaths) {
            $path = $resolved.Path
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

            try {
                Write-Log "Loesche: $path ($Reason)"
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
            catch {
                Write-Log "Konnte nicht loeschen: $path -- $($_.Exception.Message)" 'WARN'
            }
        }
    }
}

function Clear-UserTempAndCrashFiles {
    $paths = @(
        $env:TEMP,
        $env:TMP,
        (Join-Path $env:LOCALAPPDATA 'Temp'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportQueue'),
        (Join-Path $env:LOCALAPPDATA 'CrashDumps')
    )

    Remove-DirectoryContentsSafe -Reason 'Benutzer-Temp-/Fehlerbericht-Dateien' -Paths $paths
}

function Clear-CurrentUserBrowserCaches {
    $local = $env:LOCALAPPDATA

    $browserDataRoots = @(
        (Join-Path $local 'Microsoft\Edge\User Data'),
        (Join-Path $local 'Microsoft\EdgeWebView\User Data'),
        (Join-Path $local 'Google\Chrome\User Data')
    )

    foreach ($root in $browserDataRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

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

function Clear-CurrentUserShellCaches {
    $explorer = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    $paths = @(
        (Join-Path $explorer 'thumbcache_*.db'),
        (Join-Path $explorer 'iconcache_*.db')
    )

    Remove-FilePatternsSafe -Reason 'Windows Thumbnail-/Icon-Cache des Benutzers' -Paths $paths
}

function Clear-CurrentUserRecycleBin {
    try {
        Write-Log 'Leere Papierkorb fuer den aktuellen Benutzer.'
        Clear-RecycleBin -Force -ErrorAction Stop
        return
    }
    catch {
        Write-Log "Clear-RecycleBin fehlgeschlagen, versuche Benutzer-Fallback: $($_.Exception.Message)" 'WARN'
    }

    try {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $userRecycleBin = Join-Path (Join-Path $env:SystemDrive '$Recycle.Bin') $sid
        Remove-DirectoryContentsSafe -Reason 'Papierkorb-Fallback aktueller Benutzer' -Paths @($userRecycleBin)
    }
    catch {
        Write-Log "Papierkorb-Fallback fehlgeschlagen: $($_.Exception.Message)" 'WARN'
    }
}

function Invoke-StorageCleanup {
    param([ValidateSet('Light', 'Deep')][string]$Level)

    Write-Log "Starte No-Admin Speicherbereinigung: $Level"
    Write-FreeSpace 'Vor Bereinigung'

    Clear-UserTempAndCrashFiles
    Clear-CurrentUserBrowserCaches
    Clear-CurrentUserShellCaches
    Clear-CurrentUserRecycleBin

    if ($Level -eq 'Deep') {
        Write-AdminOnlySkip 'Windows Temp systemweit'
        Write-AdminOnlySkip 'Windows Update Downloadcache und Delivery Optimization Cache'
        Write-AdminOnlySkip 'alte CBS-/DISM-Protokolle systemweit'
        Write-AdminOnlySkip 'DISM Komponentenbereinigung'
        Write-AdminOnlySkip 'Ruhezustand deaktivieren / hiberfil.sys entfernen'
        Write-AdminOnlySkip 'CompactOS fuer Windows-Systemdateien aktivieren'
    }

    Write-FreeSpace 'Nach Bereinigung'
}

function Get-WingetPath {
    $cmd = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }

    try {
        $pkg = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue |
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

    return $null
}

function Invoke-WingetCommand {
    param(
        [Parameter(Mandatory = $true)][string]$WingetPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int[]]$AcceptedExitCodes = @(0)
    )

    $display = 'winget ' + ($Arguments -join ' ')
    Write-Log "Fuehre aus: $display"

    try {
        $output = & $WingetPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Log "WinGet-Aufruf konnte nicht gestartet werden: $($_.Exception.Message)" 'WARN'
        return [pscustomobject]@{
            ExitCode = -9999
            Output = @($_.Exception.Message)
            Success = $false
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
        Output = @($output | ForEach-Object { $_.ToString() })
        Success = [bool]$success
    }
}

function Test-FirefoxInstalledByRegistry {
    $uninstallRoots = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($root in $uninstallRoots) {
        try {
            $match = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like 'Mozilla Firefox*' } |
                Select-Object -First 1

            if ($match) { return $true }
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
    return ($joined -match [regex]::Escape($FirefoxPackageId))
}

function Invoke-FirefoxMaintenance {
    if ($FirefoxUpdateMode -eq 'Disabled') {
        Write-Log 'Firefox-Update ist deaktiviert.'
        return
    }

    $winget = Get-WingetPath
    if (-not $winget) {
        Write-Log 'WinGet wurde nicht gefunden. Ohne Admin wird WinGet nicht repariert oder provisioniert.' 'WARN'
        Write-AdminOnlySkip 'WinGet/App Installer systemweit reparieren oder installieren'
        return
    }

    try {
        Write-Log "Starte Firefox-Maintenance ohne Admin. Mode=$FirefoxUpdateMode PackageId=$FirefoxPackageId Locale=$FirefoxLocale"
        Invoke-WingetCommand -WingetPath $winget -Arguments @('source', 'update') -AcceptedExitCodes @(0, 1) | Out-Null

        $firefoxInstalled = (Test-FirefoxInstalledByWinget -WingetPath $winget) -or (Test-FirefoxInstalledByRegistry)

        if ($firefoxInstalled) {
            Write-Log 'Firefox ist installiert. Versuche Firefox-Upgrade im Benutzerkontext.'
            $upgradeArgs = @(
                'upgrade',
                '--id', $FirefoxPackageId,
                '-e',
                '--source', 'winget',
                '--silent',
                '--scope', 'user',
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
                Write-Log 'Firefox-Upgrade im Benutzerkontext meldete einen Fehler.' 'WARN'
            }
            return
        }

        if ($FirefoxUpdateMode -eq 'UpgradeOnly') {
            Write-Log 'Firefox ist nicht installiert. UpgradeOnly aktiv, daher keine Neuinstallation.' 'WARN'
            return
        }

        Write-Log 'Firefox ist nicht installiert. Versuche Benutzerinstallation ueber WinGet.'
        $installArgs = @(
            'install',
            '--id', $FirefoxPackageId,
            '-e',
            '--source', 'winget',
            '--silent',
            '--scope', 'user',
            '--locale', $FirefoxLocale,
            '--accept-package-agreements',
            '--accept-source-agreements',
            '--disable-interactivity'
        )

        $installResult = Invoke-WingetCommand -WingetPath $winget -Arguments $installArgs -AcceptedExitCodes @(0, 1)
        if ($installResult.Success) {
            Write-Log 'Firefox-Benutzerinstallation abgeschlossen oder war bereits nicht noetig.'
        }
        else {
            Write-Log 'Firefox-Benutzerinstallation ueber WinGet fehlgeschlagen.' 'WARN'
        }
    }
    catch {
        Write-Log "Firefox-/WinGet-Teil fehlgeschlagen: $($_.Exception.Message)" 'WARN'
    }
}

function Test-PendingRebootBestEffort {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\Updates\UpdateExeVolatile'
    )

    foreach ($key in $keys) {
        try {
            if (Test-Path $key) { return $true }
        }
        catch { }
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

function Invoke-WindowsUpdateCheckOnly {
    param([bool]$IncludeDrivers)

    Write-AdminOnlySkip 'Windows Updates automatisch herunterladen/installieren'

    try {
        Write-Log 'Pruefe per Windows Update Agent, ob regulaere Updates angeboten werden.'
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'SurfaceTabletUpdater-NoAdmin'
        $searcher = $session.CreateUpdateSearcher()
        $searcher.Online = $true

        $criteriaList = @("IsInstalled=0 and IsHidden=0 and Type='Software' and BrowseOnly=0 and AutoSelectOnWebSites=1")
        if ($IncludeDrivers) {
            $criteriaList += "IsInstalled=0 and IsHidden=0 and Type='Driver' and BrowseOnly=0 and AutoSelectOnWebSites=1"
        }

        $seen = @{}
        $count = 0
        foreach ($criteria in $criteriaList) {
            Write-Log "Suche Updates mit Kriterien: $criteria"
            $result = $searcher.Search($criteria)
            Write-Log "Gefundene Kandidaten: $($result.Updates.Count)"

            for ($i = 0; $i -lt $result.Updates.Count; $i++) {
                $update = $result.Updates.Item($i)
                $identity = '{0}:{1}' -f $update.Identity.UpdateID, $update.Identity.RevisionNumber
                if ($seen.ContainsKey($identity)) { continue }

                $seen[$identity] = $true
                $count++
                Write-Log "Update angeboten: $($update.Title)"
            }
        }

        if ($count -eq 0) {
            Write-Log 'Keine passenden regulaeren Updates gefunden oder fuer diesen Benutzer sichtbar.'
        }
        else {
            Write-Log "$count Update(s) gefunden. Installation bitte in den Windows Update Einstellungen starten."
        }
    }
    catch {
        Write-Log "Windows-Update-Suche ohne Admin nicht moeglich: $($_.Exception.Message)" 'WARN'
    }
}

function Open-WindowsUpdatePage {
    try {
        Write-Log 'Oeffne Windows Update Einstellungen fuer manuelle Installation.'
        Start-Process 'ms-settings:windowsupdate'
    }
    catch {
        Write-Log "Windows Update Einstellungen konnten nicht geoeffnet werden: $($_.Exception.Message)" 'WARN'
    }
}

function Convert-DayToSchtasksCode {
    param([string]$Day)

    $dayMap = @{
        Monday = 'MON'
        Tuesday = 'TUE'
        Wednesday = 'WED'
        Thursday = 'THU'
        Friday = 'FRI'
        Saturday = 'SAT'
        Sunday = 'SUN'
    }

    return $dayMap[$Day]
}

function Write-StartupStatusWindow {
    param([Parameter(Mandatory = $true)][string]$StartupBat)

    $lines = @(
        '@echo off',
        'title Surface No-Admin Wartungs-Updater',
        ':LOOP',
        'cls',
        'echo ================================================================',
        'echo Surface / Windows-Tablet No-Admin Wartungs-Updater',
        'echo ================================================================',
        'echo.',
        'echo Dieses Fenster zeigt nur den Status fuer den aktuellen Benutzer.',
        'echo Der No-Admin Wochenlauf kann nur laufen, wenn dieser Benutzer angemeldet ist.',
        'echo.',
        "echo Datenordner: $AppRoot",
        "echo Aufgabe: $TaskName",
        'echo.',
        "schtasks /Query /TN ""$TaskName"" >nul 2>&1",
        'if errorlevel 1 (',
        '    echo Wochenaufgabe wurde nicht gefunden. Bitte Option 2 erneut starten.',
        ') else (',
        '    echo Wochenaufgabe ist eingerichtet.',
        ')',
        'echo.',
        'echo Dieses Fenster prueft den Status alle 5 Minuten erneut.',
        'timeout /t 300 /nobreak >nul',
        'goto LOOP'
    )

    Set-Content -LiteralPath $StartupBat -Value $lines -Encoding ASCII
}

function Install-UserAutoUpdater {
    $scriptPath = Copy-SelfToLocalAppData

    try {
        [void][TimeSpan]::ParseExact($AutoTime, 'hh\:mm', [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        throw "AutoTime muss im Format HH:mm angegeben werden, z.B. 03:30. Aktuell: $AutoTime"
    }

    $powershell = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskCommand = '"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" -Mode AutoRun -CleanupLevel {2} -FirefoxUpdateMode {3} -FirefoxPackageId "{4}" -FirefoxLocale "{5}" -IncludeAutomaticDrivers:{6} -OpenWindowsUpdateSettings:$false' -f `
        $powershell, $scriptPath, $CleanupLevel, $FirefoxUpdateMode, $FirefoxPackageId, $FirefoxLocale, ('$' + $IncludeAutomaticDrivers.ToString().ToLowerInvariant())

    $runnerLines = @(
        '@echo off',
        ('"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" -Mode AutoRun -CleanupLevel {2} -FirefoxUpdateMode {3} -FirefoxPackageId "{4}" -FirefoxLocale "{5}" -IncludeAutomaticDrivers:${6} -OpenWindowsUpdateSettings:$false' -f `
            $powershell, $scriptPath, $CleanupLevel, $FirefoxUpdateMode, $FirefoxPackageId, $FirefoxLocale, $IncludeAutomaticDrivers.ToString().ToLowerInvariant())
    )
    Set-Content -LiteralPath $RunnerBat -Value $runnerLines -Encoding ASCII

    $taskDay = Convert-DayToSchtasksCode -Day $AutoDay
    $schtasksArgs = @(
        '/Create',
        '/TN', $TaskName,
        '/SC', 'WEEKLY',
        '/D', $taskDay,
        '/ST', $AutoTime,
        '/TR', $taskCommand,
        '/RL', 'LIMITED',
        '/F'
    )

    try {
        Write-Log "Richte Benutzer-Wochenaufgabe ein: $TaskName, $AutoDay $AutoTime"
        $output = & schtasks.exe @schtasksArgs 2>&1
        $exitCode = $LASTEXITCODE
        foreach ($line in $output) {
            if ($null -ne $line) { Write-Log ('schtasks: {0}' -f $line.ToString()) }
        }

        if ($exitCode -eq 0) {
            Write-Log 'Benutzer-Wochenaufgabe eingerichtet. Sie laeuft nur, wenn der Benutzer angemeldet ist.'
        }
        else {
            Write-Log "Benutzer-Wochenaufgabe konnte nicht eingerichtet werden. ExitCode=$exitCode" 'WARN'
        }
    }
    catch {
        Write-Log "schtasks konnte nicht gestartet werden: $($_.Exception.Message)" 'WARN'
    }

    $startupDir = [Environment]::GetFolderPath('Startup')
    if ([string]::IsNullOrWhiteSpace($startupDir)) {
        Write-Log 'Startup-Ordner des Benutzers konnte nicht erkannt werden.' 'WARN'
        return
    }

    New-Item -Path $startupDir -ItemType Directory -Force | Out-Null
    $startupBat = Join-Path $startupDir 'Tablet-Updater-NoAdmin-Autostart.bat'
    Write-StartupStatusWindow -StartupBat $startupBat
    Write-Log "Autostart-Statusfenster erstellt: $startupBat"
}

function Invoke-NoAdminWorkflow {
    $privilege = Get-PrivilegeState
    Write-Log "Ausfuehrung als $($privilege.UserName); Scope=$($privilege.Scope); IsAdmin=$($privilege.IsAdmin); IsSystem=$($privilege.IsSystem)"
    if ($privilege.IsAdmin -or $privilege.IsSystem) {
        Write-Log 'Hinweis: Diese No-Admin-Variante nutzt absichtlich nur Standardbenutzer-Aktionen.' 'WARN'
    }

    Copy-SelfToLocalAppData | Out-Null
    Invoke-StorageCleanup -Level $CleanupLevel
    Invoke-FirefoxMaintenance

    $disk = Get-SystemDriveInfo
    if ($disk.FreeSpace -lt 8GB) {
        Write-Log ('Sehr wenig Speicher frei: {0}. Windows Updates koennen weiter scheitern.' -f (Format-BytesGB $disk.FreeSpace)) 'WARN'
    }
    elseif ($disk.FreeSpace -lt 15GB) {
        Write-Log ('Wenig Speicher frei: {0}. Kumulative Updates koennen knapp werden.' -f (Format-BytesGB $disk.FreeSpace)) 'WARN'
    }

    Invoke-WindowsUpdateCheckOnly -IncludeDrivers:$IncludeAutomaticDrivers

    if (Test-PendingRebootBestEffort) {
        Write-Log 'Windows meldet einen ausstehenden Neustart. Bitte manuell neu starten, wenn es zeitlich passt.' 'WARN'
    }

    if ($OpenWindowsUpdateSettings) {
        Open-WindowsUpdatePage
    }
}

$transcriptStarted = $false
$mutex = $null

try {
    Start-Transcript -Path $LogFile -Append -Force | Out-Null
    $transcriptStarted = $true

    Write-Log "Logfile: $LogFile"
    Write-Log "Mode=$Mode CleanupLevel=$CleanupLevel FirefoxUpdateMode=$FirefoxUpdateMode IncludeAutomaticDrivers=$IncludeAutomaticDrivers OpenWindowsUpdateSettings=$OpenWindowsUpdateSettings"

    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($false, $MutexName, [ref]$createdNew)
    if (-not $mutex.WaitOne(0)) {
        Write-Log 'Eine andere No-Admin-Instanz laeuft bereits. Beende diese Instanz.' 'WARN'
        exit 0
    }

    switch ($Mode) {
        'InstallAutoUpdater' {
            Install-UserAutoUpdater
        }
        'UpdateNow' {
            Invoke-NoAdminWorkflow
        }
        'AutoRun' {
            Invoke-NoAdminWorkflow
        }
        'OpenWindowsUpdateSettings' {
            Open-WindowsUpdatePage
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
