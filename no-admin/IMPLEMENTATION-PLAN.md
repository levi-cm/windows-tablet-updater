# No-Admin Tablet Updater Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a separate standard-user updater package under `no-admin/` without changing the original admin package.

**Architecture:** The new package uses user-writable locations, best-effort cleanup, Firefox maintenance via existing WinGet, Windows Update check/reporting, and per-user autorun. Privileged operations are skipped with clear German status messages instead of aborting the workflow.

**Tech Stack:** Windows batch, Windows PowerShell 5.1, shell static contract tests.

---

### Task 1: Static Contract Tests

**Files:**
- Create: `no-admin/tests/static_checks.sh`

- [x] **Step 1: Write a failing test**

The test requires the no-admin PowerShell script, launcher, README, and flowchart to exist. It also checks that the script does not rely on admin-only mechanisms such as SYSTEM scheduled tasks, machine-scope WinGet installs, service stopping, DISM, forced reboot, hibernation changes, or CompactOS.

- [x] **Step 2: Run the test to verify it fails**

Run: `bash no-admin/tests/static_checks.sh`
Expected: FAIL because `no-admin/Windows-Tablet-Updater-NoAdmin.ps1` does not exist yet.

### Task 2: No-Admin Package Files

**Files:**
- Create: `no-admin/Windows-Tablet-Updater-NoAdmin.ps1`
- Create: `no-admin/Tablet-Updater-Starten-NoAdmin.bat`
- Create: `no-admin/readme.md`
- Create: `no-admin/ABLAUF-DIAGRAMM.txt`

- [x] **Step 1: Add the PowerShell script**

The script must:
- use `%LOCALAPPDATA%\SurfaceTabletUpdater-NoAdmin` for logs and installed copies;
- clean only current-user temp/browser/shell caches;
- avoid admin-only cleanup and log skipped operations;
- use existing WinGet if available;
- use `--scope user` for Firefox install/upgrade;
- check Windows Update availability where COM permissions allow it;
- open Windows Update settings for manual installation;
- install per-user autorun through the current user's Startup folder.

- [x] **Step 2: Add the batch launcher**

The launcher must not require elevation and must expose a small German menu for immediate maintenance, weekly user autorun, Windows Update settings, and exit.

- [x] **Step 3: Add German docs**

The docs must explain what still works without admin and what is intentionally skipped.

### Task 3: Verification

**Files:**
- Existing files must remain unchanged:
  - `Windows-Tablet-Updater.ps1`
  - `Tablet-Updater-Starten.bat`
  - `readme.md`
  - `ABLAUF-DIAGRAMM.txt`

- [x] **Step 1: Run static checks**

Run: `bash no-admin/tests/static_checks.sh`
Expected: PASS.

- [x] **Step 2: Verify original file hashes**

Run: `sha256sum Windows-Tablet-Updater.ps1 Tablet-Updater-Starten.bat readme.md ABLAUF-DIAGRAMM.txt`
Expected:
```text
4f36e7f94112cc9f79c50a9900c3a3d1364520044c7c5cc473e6950e5f681770  Windows-Tablet-Updater.ps1
a4684600157853d3cc923d084f34e7939ca8019b5810fff8cbf2bbadfa04e263  Tablet-Updater-Starten.bat
f28f0bdd8cc2553a463c312ab282fe88346298145a7af673d8ab31e2c6d4cf52  readme.md
abc07fe6296fde2be3cee2514f43e76e86b32d5d22deb37e2ee85c698d92deb3  ABLAUF-DIAGRAMM.txt
```
