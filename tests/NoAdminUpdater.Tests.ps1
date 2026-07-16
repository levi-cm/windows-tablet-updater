$ErrorActionPreference = 'Stop'

BeforeAll {
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        function Get-AuthenticodeSignature { param([string]$FilePath) throw "Test shim was not mocked: $FilePath" }
    }

    $env:SURFACE_UPDATER_TEST_MODE = '1'
    $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppData'
    $env:SystemDrive = $TestDrive
    $env:windir = Join-Path $TestDrive 'Windows'
    $env:TEMP = Join-Path $env:LOCALAPPDATA 'Temp'
    $env:TMP = $env:TEMP

    . (Join-Path $PSScriptRoot '..\ohne-admin\Windows-Tablet-Updater-NoAdmin.ps1') -DryRun
}

AfterAll {
    Remove-Item Env:SURFACE_UPDATER_TEST_MODE -ErrorAction SilentlyContinue
}

Describe 'No-admin updater safety contracts' {
    It 'rejects deletion outside current-user cache roots' {
        Test-DeletionTargetAllowed -Path 'C:\Users\Ada\AppData\Local\Temp' -AllowedPatterns @('C:\Users\Ada\AppData\Local\Temp') | Should -BeTrue
        Test-DeletionTargetAllowed -Path 'C:\Windows\Temp' -AllowedPatterns @('C:\Users\Ada\AppData\Local\Temp') | Should -BeFalse
    }

    It 'does not delete during dry-run' {
        Mock Resolve-Path { [pscustomobject]@{ Path = $env:TEMP } }
        Mock Test-Path { $true }
        Mock Get-ChildItem { @([pscustomobject]@{ FullName = (Join-Path $env:TEMP 'cache.tmp'); Attributes = [IO.FileAttributes]::Normal }) }
        Mock Remove-Item

        Remove-DirectoryContentsSafe -Paths @($env:TEMP) -Reason 'test'
        Should -Invoke Remove-Item -Times 0
    }

    It 'does not open Windows Update settings during dry-run' {
        Mock Start-Process

        Open-WindowsUpdatePage
        Should -Invoke Start-Process -Times 0
    }

    It 'builds a limited current-user scheduled command' {
        $args = New-UserAutoUpdaterArguments -ScriptPath 'C:\Users\Ada\AppData\Local\SurfaceTabletUpdater-NoAdmin\Windows-Tablet-Updater-NoAdmin.ps1'
        $args | Should -Match '^-NoProfile -ExecutionPolicy Bypass -File '
        $args | Should -Match '-Mode AutoRun'
        $args | Should -Match '-OpenWindowsUpdateSettings:\$false'
        $args | Should -Match '-IncludeAutomaticDrivers:\$true'
        $args | Should -Not -Match '-DryRun'
        $args | Should -Not -Match 'SYSTEM|RunLevel Highest'
    }

    It 'keeps update discovery read-only and driver-aware' {
        $criteria = @(Get-UpdateSearchCriteria -IncludeDrivers $true)
        $criteria | Should -Contain "IsInstalled=0 and IsHidden=0 and Type='Software' and BrowseOnly=0 and AutoSelectOnWebSites=1"
        $criteria | Should -Contain "IsInstalled=0 and IsHidden=0 and Type='Driver' and BrowseOnly=0 and AutoSelectOnWebSites=1"
    }

    It 'rejects winget when Microsoft publisher verification fails' {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status = 'NotSigned'
                SignerCertificate = $null
            }
        }

        { Test-TrustedMicrosoftFile -Path 'C:\WindowsApps\winget.exe' } | Should -Throw '*Signaturpruefung fehlgeschlagen*'
    }

    It 'contains no privileged admin assertion' {
        Get-Content (Join-Path $PSScriptRoot '..\ohne-admin\Windows-Tablet-Updater-NoAdmin.ps1') -Raw | Should -Not -Match 'function Assert-AdminOrSystem'
    }
}
