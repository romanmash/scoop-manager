# Scripts and Modules Reference

Full catalogue of the numbered PowerShell scripts and shared modules that make up Scoop Manager.
For the high-level pitch and architecture, see the main [README](../README.md).

## Scripts (high level)

```text
scripts\
  Manage-ScoopMenu.ps1                  # Main menu manager

  00@Docs.ps1                           # Section: Docs
  01_Show-ProjectDoc.ps1                # Show this README
  02_Show-UsedCmd.ps1                   # List native Scoop commands used by scripts

  10@Init.ps1                           # Section: Init
  11_Open-TerminalSettings.ps1          # Open Settings for classic console host
  12_Check-StartupPolicy.ps1            # Show execution policy / language mode diagnostics
  18_Fetch-ScoopInstaller.ps1           # Download Scoop installer
  19_Install-PortableScoop.ps1          # Install Scoop in portable_scoop\

  20@Apps.ps1                           # Section: Apps
  21_List-InstalledApps.ps1
  22_Install-InitApps.ps1
  23_Import-Apps.ps1
  24_Restore-Persist.ps1
  26_Restore-MigrationPack.ps1
  27_Fix-PersistLinks.ps1
  28_Scan-InstalledApps.ps1
  29_Import-Scoop.ps1

  31_List-InstalledBuckets.ps1          # Section: Buckets
  32_Show-KnownBuckets.ps1

  41_Check-Updates.ps1                  # Section: Update
  42_Update-Apps.ps1
  49_Update-Scoop.ps1

  51_Cleanup-Cache.ps1                  # Section: Cleanup
  52_Cleanup-OldVersions.ps1
  53_Cleanup-PersistOrph.ps1
  54_Cleanup-PersistAll.ps1
  55_Reset-Apps.ps1
  56_Close-Apps.ps1

  61_Invoke-Checkup.ps1                 # Section: Config / Diagnostics
  62_Show-Config.ps1
  63_Edit-Config.ps1
  64_Run-Interactive.ps1

  71_Export-Apps.ps1                    # Section: Export
  79_Export-Scoop.ps1
  81_Backup-Persist.ps1                 # Section: Backup
  88_Backup-MigrationPack.ps1
  89_Backup-PortableScoop.ps1

  91_Uninstall-Apps.ps1                 # Section: Uninstall
  99_Uninstall-Scoop.ps1
```

## Modules (high level)

```text
modules\
  ScriptBootstrap.psm1                  # Initialize-ScriptEnvironment (standard bootstrap)
  ScoopEnvironment.psm1                 # Stealth env + Scoop patching + env helpers
  ScoopCommand.psm1                     # Invoke-ScoopCommand / Invoke-ScoopCommandScript
  ConsoleUi.psm1                        # Section/subsection console headers
  TextFile.psm1                         # UTF-8 (no BOM) text/JSON writes
  ProcessRunner.psm1                    # Unified external command runner (single .tmp\\process\\process.log)

  ExtendedAppList.psm1                  # App list formatting and display
  UpdatableApps.psm1                    # Detect updatable apps
  VirusTotalInit.psm1                   # Shared VirusTotal gate bootstrap for managed flows
  RunningScoopApps.psm1                 # Detect/close running Scoop apps
  FileRemoval.psm1                      # Robust directory removal with retries/fallbacks
  PersistLinks.psm1                     # Persist relink helper for apps with non-standard data paths
  PathTools.psm1                        # Safe path resolution helpers
  ScoopPathTools.psm1                   # Path migration helpers
  JsonFile.psm1, BackupConfig.psm1,     # And other focused helper modules
  BackupPersist.psm1, BackupArchive.psm1
  ...
```

---

## Script Descriptions (by Section)

### Section 0 - Docs

| Script | Description |
|--------|-------------|
| **01** | Opens this README / project doc in default application. |
| **02** | Displays a table of scripts and the native Scoop commands they use. |
| **08** | Shows Scoop help output (`scoop help`). |
| **09** | Opens the Scoop wiki in the default browser. |

### Section 1 - Init

| Script | Description |
|--------|-------------|
| **11** | Opens Windows settings to set "Default terminal application" to Windows Console Host (classic console). |
| **12** | Displays startup diagnostics: execution policy per scope and current PowerShell language mode, plus notes for corporate/locked-down environments. |
| **18** | Downloads installer from `get.scoop.sh`, validates against cached copy. |
| **19** | Installs Scoop into `../portable_scoop` with stealth mode (process-level env vars only), then installs core apps from `core.apps` (e.g., Git) for bucket/update workflows. Sets `SCOOP`, `SCOOP_CACHE`, `SCOOP_GLOBAL`, `XDG_CONFIG_HOME`, and PATH (process-level). |

### Section 2 - Apps

| Script | Description |
|--------|-------------|
| **21** | Lists installed apps (canonical + extended views: versions, shims, held/pinned status, updates). |
| **22** | Installs apps and buckets from `config/apps/init_apps.json` on **fresh** installations only. Validates Scoop, checks for existing apps, then installs according to JSON (supports multiple versions, holds, pins, skip flags). |
| **23** | Imports apps from the latest `export_apps_*.json` in `config/apps/` (produced by script 71). Uses the same JSON format as `init_apps.json`. Runs only on fresh installations. |
| **24** | Restores `portable_scoop\persist` from the latest backup in `backup/persist\`. Skips restore if `persist\` is not empty (you must run `54` first). |
| **26** | Restores a migration pack (apps + config + persist) from a ZIP archive in `backup/migration\`. Validates fresh installation, updates paths using `ScoopPathTools`. |
| **27** | Fixes persist relinks defined in `config/persist_links.json` (preview + confirmation). Runs automatically after installs, updates, and imports; can also be run manually. |
| **28** | Scans installed apps using VirusTotal (and optional Windows Defender) and prints a summary table of results plus per-app details (including shared `persist\<app>` folders). |
| **29** | Imports apps from canonical `export_scoop_*.json` in `config/scoop\` (native `scoop import`). Runs only on fresh installations. |

### Section 3 - Buckets

| Script | Description |
|--------|-------------|
| **31** | Lists installed buckets (`scoop bucket list`). |
| **32** | Shows all known/official buckets (`scoop bucket known`). |

### Section 4 - Update

| Script | Description |
|--------|-------------|
| **41** | Checks for available updates. If multiple versions are installed, treats the app as up-to-date when the latest bucket version is already present. If `scoop update` fails (git/GitHub), prompts whether to continue with stale bucket metadata. |
| **42** | Updates only the apps flagged as updatable by script 41 (keeps explicit `scoop install app@version`). If `scoop update` fails (git/GitHub), prompts whether to continue with stale bucket metadata. Shows Before/After app tables. |
| **49** | Updates Scoop itself and buckets (`scoop update`). If the update reports git/network errors, prompts whether to continue with stale bucket metadata. Shows status before/after when an update is available. |

### Section 5 - Cleanup

| Script | Description |
|--------|-------------|
| **51** | Clears download cache (`scoop cache rm *`) with before/after `cache show`. |
| **52** | Removes old versions of all apps (preserves current, pinned, and held apps). Uses `InstalledAppVersions` module and `FileRemoval` helper. Shows Before/After state. |
| **53** | Removes orphaned `persist\` folders for apps that are no longer installed. |
| **54** | Purges **all** `persist\` data and the workspace folder (destructive but preserves app metadata such as pin/hold/current). |
| **55** | Resets all apps (`scoop reset *`) using the shared command wrapper. |
| **56** | Closes all running Scoop-installed apps. Lists them, prompts once, then attempts graceful/forced close. |

### Section 6 - Config / Diagnostics

| Script | Description |
|--------|-------------|
| **61** | Runs `scoop checkup` via the command wrapper to detect issues. |
| **62** | Displays current Scoop configuration (`scoop config`). |
| **63** | Edits Scoop configuration (set/remove values) interactively via `scoop config`. |
| **64** | Opens a new CMD window with the stealth Scoop environment for interactive use. |

### Section 7 - Export

| Script | Description |
|--------|-------------|
| **71** | Exports all explicitly installed apps to `config/apps/export_apps_*.json` in internal JSON format (same schema as `init_apps.json`). |
| **79** | Exports canonical Scoop JSON (`scoop export`) to `config/scoop/export_scoop_*.json`. |

### Section 8 - Backup

| Script | Description |
|--------|-------------|
| **81** | Creates a backup of `persist\` plus an apps export. Stores ZIPs in `backup/persist\` and JSON in `config/apps\`. Both share a timestamp. |
| **88** | Creates a "migration pack" ZIP (apps JSON + config + persist) suitable for moving Scoop to a new PC or path. |
| **89** | Creates a full backup of `portable_scoop\` into `backup/full\` (ZIP). |

### Section 9 - Uninstall

| Script | Description |
|--------|-------------|
| **91** | Uninstalls user apps via native `scoop uninstall`, with better error handling (batch + per-app fallback). Keeps core apps from `core.apps` and persist data. |
| **99** | Completely removes Scoop, its apps, buckets, and `portable_scoop\` folder using robust directory removal logic. Stealth mode means no persistent env cleanup is required. |
