#!/usr/bin/env bash
# shellcheck disable=SC2016 # PowerShell tokens below are intentional literals.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ADMIN_DIR="$ROOT_DIR/mit-admin"
NO_ADMIN_DIR="$ROOT_DIR/ohne-admin"
ROOT_README_FILE="$ROOT_DIR/README.md"
ADMIN_PS1_FILE="$ADMIN_DIR/Windows-Tablet-Updater.ps1"
ADMIN_BAT_FILE="$ADMIN_DIR/Tablet-Updater-Starten.bat"
ADMIN_README_FILE="$ADMIN_DIR/readme.md"
ADMIN_FLOW_FILE="$ADMIN_DIR/ABLAUF-DIAGRAMM.txt"
PS1_FILE="$NO_ADMIN_DIR/Windows-Tablet-Updater-NoAdmin.ps1"
BAT_FILE="$NO_ADMIN_DIR/Tablet-Updater-Starten-NoAdmin.bat"
README_FILE="$NO_ADMIN_DIR/readme.md"
FLOW_FILE="$NO_ADMIN_DIR/ABLAUF-DIAGRAMM.txt"
LICENSE_FILE="$ROOT_DIR/LICENSE"
SECURITY_FILE="$ROOT_DIR/SECURITY.md"
CI_FILE="$ROOT_DIR/.github/workflows/ci.yml"
ADMIN_TEST_FILE="$ROOT_DIR/tests/AdminUpdater.Tests.ps1"
NO_ADMIN_TEST_FILE="$ROOT_DIR/tests/NoAdminUpdater.Tests.ps1"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: ${1#"$ROOT_DIR"/}"
}

assert_dir() {
  [[ -d "$1" ]] || fail "missing directory: ${1#"$ROOT_DIR"/}"
}

assert_missing() {
  [[ ! -e "$1" ]] || fail "unexpected root clutter remains: ${1#"$ROOT_DIR"/}"
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  grep -Fq -- "$pattern" "$file" || fail "${file#"$ROOT_DIR"/} does not contain: $pattern"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Fq -- "$pattern" "$file"; then
    fail "${file#"$ROOT_DIR"/} must not contain: $pattern"
  fi
}

assert_not_regex() {
  local file="$1"
  local pattern="$2"
  if grep -Eq -- "$pattern" "$file"; then
    fail "${file#"$ROOT_DIR"/} matches forbidden pattern: $pattern"
  fi
}

assert_dir "$ADMIN_DIR"
assert_dir "$NO_ADMIN_DIR"

assert_file "$ROOT_README_FILE"
assert_file "$ADMIN_PS1_FILE"
assert_file "$ADMIN_BAT_FILE"
assert_file "$ADMIN_README_FILE"
assert_file "$ADMIN_FLOW_FILE"
assert_file "$PS1_FILE"
assert_file "$BAT_FILE"
assert_file "$README_FILE"
assert_file "$FLOW_FILE"
assert_file "$LICENSE_FILE"
assert_file "$SECURITY_FILE"
assert_file "$CI_FILE"
assert_file "$ADMIN_TEST_FILE"
assert_file "$NO_ADMIN_TEST_FILE"

assert_missing "$ROOT_DIR/Windows-Tablet-Updater.ps1"
assert_missing "$ROOT_DIR/Tablet-Updater-Starten.bat"
assert_missing "$ROOT_DIR/ABLAUF-DIAGRAMM.txt"
assert_missing "$ROOT_DIR/no-admin"
assert_missing "$NO_ADMIN_DIR/IMPLEMENTATION-PLAN.md"

assert_contains "$PS1_FILE" '$env:LOCALAPPDATA'
assert_contains "$PS1_FILE" 'Get-PrivilegeState'
assert_contains "$PS1_FILE" 'Invoke-WindowsUpdateCheckOnly'
assert_contains "$PS1_FILE" 'Install-UserAutoUpdater'
assert_contains "$PS1_FILE" 'ms-settings:windowsupdate'
assert_contains "$PS1_FILE" '--scope'
assert_contains "$PS1_FILE" 'user'
assert_contains "$PS1_FILE" 'SKIP'
assert_contains "$PS1_FILE" '[switch]$DryRun'
assert_contains "$PS1_FILE" 'Test-DeletionTargetAllowed'
assert_contains "$PS1_FILE" 'Test-TrustedMicrosoftFile'
assert_contains "$PS1_FILE" 'Write-PreflightSummary'
assert_not_contains "$PS1_FILE" 'Assert-AdminOrSystem'
assert_not_contains "$PS1_FILE" 'Register-ScheduledTask'
assert_not_contains "$PS1_FILE" "New-ScheduledTaskPrincipal -UserId 'SYSTEM'"
assert_not_contains "$PS1_FILE" '--scope machine'
assert_not_contains "$PS1_FILE" 'Stop-Service'
assert_not_contains "$PS1_FILE" 'Add-AppxProvisionedPackage'
assert_not_contains "$PS1_FILE" 'Repair-WinGetPackageManager -AllUsers'
assert_not_contains "$PS1_FILE" 'Install-Module -Name Microsoft.WinGet.Client'
assert_not_contains "$PS1_FILE" 'powercfg /hibernate off'
assert_not_contains "$PS1_FILE" 'CompactOS:always'
assert_not_contains "$PS1_FILE" 'shutdown.exe /r /f'

assert_contains "$BAT_FILE" 'No-Admin'
assert_contains "$BAT_FILE" 'Windows-Tablet-Updater-NoAdmin.ps1'
assert_not_contains "$BAT_FILE" 'net session'
assert_not_contains "$BAT_FILE" 'Als Administrator'

assert_contains "$README_FILE" 'ohne Administratorrechte'
assert_contains "$README_FILE" 'Was ohne Admin nicht moeglich ist'
assert_contains "$FLOW_FILE" 'No-Admin'
assert_contains "$FLOW_FILE" 'Windows Update Einstellungen'
assert_contains "$ROOT_README_FILE" 'mit-admin/'
assert_contains "$ROOT_README_FILE" 'ohne-admin/'
assert_contains "$ROOT_README_FILE" 'Welche Variante soll ich nutzen?'
assert_contains "$ROOT_README_FILE" 'Tablet-Updater-Starten.bat'
assert_contains "$ROOT_README_FILE" 'Tablet-Updater-Starten-NoAdmin.bat'
assert_contains "$ROOT_README_FILE" 'English summary'
assert_contains "$ROOT_README_FILE" '-DryRun'
assert_contains "$ADMIN_PS1_FILE" '[switch]$DryRun'
assert_contains "$ADMIN_PS1_FILE" 'Test-DeletionTargetAllowed'
assert_contains "$ADMIN_PS1_FILE" 'Test-TrustedMicrosoftFile'
assert_contains "$ADMIN_PS1_FILE" 'Write-PreflightSummary'
assert_contains "$ADMIN_PS1_FILE" 'AutoSelectOnWebSites=1'
assert_contains "$ADMIN_PS1_FILE" 'ExecutionPolicy Bypass'
assert_contains "$ADMIN_PS1_FILE" 'Register-ResumeTask'
assert_contains "$ADMIN_PS1_FILE" 'Install-AutoUpdaterTask'
assert_contains "$ADMIN_PS1_FILE" 'powercfg /hibernate off'
assert_contains "$ADMIN_PS1_FILE" '/CompactOS:always'
assert_contains "$ADMIN_PS1_FILE" 'shutdown.exe /r /f'
assert_contains "$ADMIN_PS1_FILE" "Type='Driver'"
assert_contains "$ADMIN_BAT_FILE" '-DryRun'
assert_contains "$BAT_FILE" '-DryRun'
assert_contains "$PS1_FILE" 'Install-UserAutoUpdater'
assert_not_regex "$ADMIN_PS1_FILE" '^[[:space:]]*Set-ExecutionPolicy([[:space:]]|$)'
assert_not_regex "$PS1_FILE" '^[[:space:]]*Set-ExecutionPolicy([[:space:]]|$)'
assert_contains "$CI_FILE" 'PSScriptAnalyzer'
assert_contains "$CI_FILE" 'Pester'
assert_contains "$CI_FILE" 'static_checks.sh'
assert_contains "$CI_FILE" 'actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5'

printf 'PASS: admin/no-admin structure checks\n'
