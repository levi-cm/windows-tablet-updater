$ErrorActionPreference = 'Stop'

BeforeAll {
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        function Get-AuthenticodeSignature { param([string]$FilePath) throw "Test shim was not mocked: $FilePath" }
    }

    $env:SURFACE_UPDATER_TEST_MODE = '1'
    $env:ProgramData = Join-Path $TestDrive 'ProgramData'
    $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppData'
    $env:SystemDrive = $TestDrive
    $env:windir = Join-Path $TestDrive 'Windows'
    $env:TEMP = Join-Path $env:windir 'Temp'
    $env:TMP = $env:TEMP

    . (Join-Path $PSScriptRoot '..\mit-admin\Windows-Tablet-Updater.ps1') -DryRun -RegularOnly
}

AfterAll {
    Remove-Item Env:SURFACE_UPDATER_TEST_MODE -ErrorAction SilentlyContinue
}

Describe 'Admin updater safety contracts' {
    It 'accepts only deletion targets covered by the explicit allowlist' {
        Test-DeletionTargetAllowed -Path 'C:\Windows\Temp' -AllowedPatterns @('C:\Windows\Temp') | Should -BeTrue
        Test-DeletionTargetAllowed -Path 'C:\Users\Ada\AppData\Local\Temp' -AllowedPatterns @('C:\Users\*\AppData\Local\Temp') | Should -BeTrue
        Test-DeletionTargetAllowed -Path 'C:\Users\Ada\Documents' -AllowedPatterns @('C:\Users\*\AppData\Local\Temp') | Should -BeFalse
    }

    It 'fails before deleting a target outside the allowlist' {
        Mock Resolve-Path { [pscustomobject]@{ Path = 'C:\Users\Ada\Documents' } }
        Mock Test-Path { $true }
        Mock Get-ChildItem { @() }
        Mock Remove-Item

        { Remove-DirectoryContentsSafe -Paths @('C:\Users\Ada\Documents') -Reason 'test' } | Should -Throw '*nicht in der Loesch-Allowlist*'
        Should -Invoke Remove-Item -Times 0
    }

    It 'does not delete during dry-run' {
        Mock Resolve-Path { [pscustomobject]@{ Path = $env:TEMP } }
        Mock Test-Path { $true }
        Mock Get-ChildItem { @([pscustomobject]@{ FullName = (Join-Path $env:TEMP 'cache.tmp'); Attributes = [IO.FileAttributes]::Normal }) }
        Mock Remove-Item

        Remove-DirectoryContentsSafe -Paths @($env:TEMP) -Reason 'test'
        Should -Invoke Remove-Item -Times 0
    }

    It 'does not download or install selected Windows updates during dry-run' {
        Mock Get-ApplicableUpdates {
            @{
                Session = [pscustomobject]@{}
                Updates = [pscustomobject]@{ Count = 2 }
            }
        }

        $result = Invoke-WindowsUpdatePass -IncludeDrivers $true
        $result.ResultCode | Should -Be 'DryRun'
        $result.SelectedCount | Should -Be 2
        $result.InstalledCount | Should -Be 0
    }

    It 'does not fetch the App Installer bundle during dry-run' {
        Mock Invoke-WebRequest

        Install-WingetFromOfficialBundle | Should -BeFalse
        Should -Invoke Invoke-WebRequest -Times 0
    }

    It 'requires admin or SYSTEM for the admin mode' {
        Mock Test-IsAdminOrSystem { $false }
        { Assert-AdminOrSystem } | Should -Throw '*Administrator oder als SYSTEM*'
    }

    It 'keeps automatic software and driver update filters separate' {
        $criteria = @(Get-UpdateSearchCriteria -IncludeDrivers $true)
        $criteria | Should -Contain "IsInstalled=0 and IsHidden=0 and Type='Software' and BrowseOnly=0 and AutoSelectOnWebSites=1"
        $criteria | Should -Contain "IsInstalled=0 and IsHidden=0 and Type='Driver' and BrowseOnly=0 and AutoSelectOnWebSites=1"
    }

    It 'omits driver criteria when drivers are disabled' {
        $criteria = @(Get-UpdateSearchCriteria -IncludeDrivers $false)
        $criteria.Count | Should -Be 1
        $criteria[0] | Should -Match "Type='Software'"
    }

    It 'preserves scheduling flags and scopes ExecutionPolicy Bypass to the child process' {
        $args = New-AutoUpdaterArguments -ScriptPath 'C:\ProgramData\SurfaceTabletUpdater\Windows-Tablet-Updater.ps1'
        $args | Should -Match '^-NoProfile -ExecutionPolicy Bypass -File '
        $args | Should -Match '-Mode AutoRun'
        $args | Should -Match '-RegularOnly'
        $args | Should -Match '-IncludeAutomaticDrivers:\$true'
        $args | Should -Match '-DisableHibernate:\$true'
        $args | Should -Match '-EnableCompactOS:\$true'
        $args | Should -Not -Match '-DryRun'
    }

    It 'preserves reboot continuation flags' {
        $args = New-ResumeArguments -ScriptPath 'C:\ProgramData\SurfaceTabletUpdater\Windows-Tablet-Updater.ps1'
        $args | Should -Match '-Mode Resume'
        $args | Should -Match '-CleanupLevel Light'
        $args | Should -Match '-RestartPolicy IfNeeded'
        $args | Should -Match '-MaxPasses 4'
        $args | Should -Not -Match '-DryRun'
    }

    It 'previews SYSTEM scheduling without registering a task' {
        { Install-AutoUpdaterTask } | Should -Not -Throw
    }

    It 'accepts only a valid Microsoft publisher signature' {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status = 'Valid'
                SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' }
            }
        }

        Test-TrustedMicrosoftFile -Path 'C:\Temp\Microsoft.DesktopAppInstaller.msixbundle' | Should -BeTrue
    }

    It 'rejects invalid downloaded package signatures' {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status = 'HashMismatch'
                SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation' }
            }
        }

        { Test-TrustedMicrosoftFile -Path 'C:\Temp\Microsoft.DesktopAppInstaller.msixbundle' } | Should -Throw '*Signaturpruefung fehlgeschlagen*'
    }
}
