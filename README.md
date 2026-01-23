# Portable Scoop Installation Manager

A production-ready toolkit for managing portable [Scoop](https://scoop.sh/) installations on Windows.  
Designed for cloning between personal and enterprise PCs **without admin rights** and **without persistent system changes** (stealth mode).

---

## Purpose

This project enables you to:
- Install Scoop into a **portable, relocatable** directory.
- Define and version your app configuration via JSON.
- Export and import your entire Scoop setup between machines.
- Back up and restore apps, persist data, and migration packs.
- Run everything from a simple menu (`scoop_manager.cmd`), including in paths with spaces and leading hyphens.

Long‑term architecture and design docs live in `memory-bank/*.md`.

---

## Folder Structure (Top Level)

```text
D:\_\install_scoop\                     # This project (portable Scoop manager)
  scoop_manager.cmd                     # Interactive menu launcher

  scripts\                              # PowerShell scripts (organized 00-99)
  modules\                              # Shared PowerShell modules (.psm1)
  config\                               # Configuration and exports
  backup\                               # Optional extra backup location (if used)
  patch\                                # Scoop installer + lib patches
  @\                                    # Metadata and utilities
  memory-bank\                          # Long-term design docs (humans + AI)

  portable_scoop\                       # Scoop installation (created by script 19)
    apps\                               # Installed applications
    shims\                              # Scoop shims added to PATH (process-level)
```

### Scripts (high level)

```text
scripts\
  Manage-ScoopMenu.ps1                  # Main menu manager

  00@Docs.ps1                           # Section: Docs
  01_Show-ProjectDoc.ps1                # Show this README / docs
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

### Modules (high level)

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
  VirusTotalInit.psm1                   # Best-effort VirusTotal integration init
  RunningScoopApps.psm1                 # Detect/close running Scoop apps
  FileRemoval.psm1                      # Robust directory removal with retries/fallbacks
  PersistLinks.psm1                     # Persist relink helper for apps with non-standard data paths
  PathTools.psm1                        # Safe path resolution helpers
  ScoopPathTools.psm1                   # Path migration helpers
  JsonFile.psm1, BackupConfig.psm1,     # And other focused helper modules
  BackupPersist.psm1, BackupArchive.psm1
  ...
```

For deeper architecture and design patterns, see:
- `memory-bank/systemPatterns.md`
- `memory-bank/techContext.md`
- `memory-bank/technicalDetails.md`

---

## Quick Start

### Fresh Installation

For a new PC or first-time setup:

1. **Run the menu launcher**
   ```cmd
   scoop_manager.cmd
   ```

2. **Execute scripts in sequence**
   - Type `11` - Open Settings (set classic console host, optional).
   - Type `18` - Fetch Scoop installer.
   - Type `19` - Install Scoop into `portable_scoop\` (stealth mode).
   - Type `22` - Install predefined apps from `config/apps/init_apps.json`.

### Clone Existing Setup

To replicate an existing Scoop configuration:

1. **Copy this folder** (`install_scoop`) to the new PC at the same location.
2. **Run the menu launcher**
   ```cmd
   scoop_manager.cmd
   ```
3. **Execute import workflow**
   - Type `11` - Open Settings (set classic console host, optional).
   - Type `18` - Fetch Scoop installer.
   - Type `19` - Install Scoop.
   - Type `23` - Import apps from the latest export JSON (script 71 output).

### Interactive Menu

The menu (driven by `Manage-ScoopMenu.ps1`) shows all available scripts grouped by section (Docs, Init, Apps, Buckets, Update, Cleanup, Config, Export, Backup, Uninstall).  
You select by number; **menu selection is the confirmation** (no extra “TYPE YES” prompts in scripts).

---

## Workflows (Overview)

- **Workflow 1 - Fresh install**
  - 18 → 19 → 22
- **Workflow 2 - Clone / import**
  - 18 → 19 → 23 or 29 → 24 / 26 (restore persist/migration pack if needed)
- **Workflow 3 - Maintenance**
  - 41 (check updates) → 42 (update apps) → 49 (update Scoop) → 52/51 (cleanup)
- **Workflow 4 - Backup / restore**
  - 81 / 88 / 89 (create backups) → 24 / 26 / 29 (restore)
- **Workflow 5 - Uninstall**
  - 91 (remove user apps) → 99 (remove Scoop + portable_scoop)

Details for each script are in the “Script Descriptions” section below.

---

## Script Descriptions (by Section)

### Section 0 – Docs

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

### Section 3 – Buckets

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

### Section 5 – Cleanup

| Script | Description |
|--------|-------------|
| **51** | Clears download cache (`scoop cache rm *`) with before/after `cache show`. |
| **52** | Removes old versions of all apps (preserves current, pinned, and held apps). Uses `InstalledAppVersions` module and `FileRemoval` helper. Shows Before/After state. |
| **53** | Removes orphaned `persist\` folders for apps that are no longer installed. |
| **54** | Purges **all** `persist\` data and the workspace folder (destructive but preserves app metadata such as pin/hold/current). |
| **55** | Resets all apps (`scoop reset *`) using the shared command wrapper. |
| **56** | Closes all running Scoop-installed apps. Lists them, prompts once, then attempts graceful/forced close. |

### Section 6 – Config / Diagnostics

| Script | Description |
|--------|-------------|
| **61** | Runs `scoop checkup` via the command wrapper to detect issues. |
| **62** | Displays current Scoop configuration (`scoop config`). |
| **63** | Edits Scoop configuration (set/remove values) interactively via `scoop config`. |
| **64** | Opens a new CMD window with the stealth Scoop environment for interactive use. |

### Section 7 – Export

| Script | Description |
|--------|-------------|
| **71** | Exports all explicitly installed apps to `config/apps/export_apps_*.json` in internal JSON format (same schema as `init_apps.json`). |
| **79** | Exports canonical Scoop JSON (`scoop export`) to `config/scoop/export_scoop_*.json`. |

### Section 8 – Backup

| Script | Description |
|--------|-------------|
| **81** | Creates a backup of `persist\` plus an apps export. Stores ZIPs in `backup/persist\` and JSON in `config/apps\`. Both share a timestamp. |
| **88** | Creates a “migration pack” ZIP (apps JSON + config + persist) suitable for moving Scoop to a new PC or path. |
| **89** | Creates a full backup of `portable_scoop\` into `backup/full\` (ZIP). |

### Section 9 – Uninstall

| Script | Description |
|--------|-------------|
| **91** | Uninstalls user apps via native `scoop uninstall`, with better error handling (batch + per-app fallback). Keeps core apps from `core.apps` and persist data. |
| **99** | Completely removes Scoop, its apps, buckets, and `portable_scoop\` folder using robust directory removal logic. Stealth mode means no persistent env cleanup is required. |

---

## Customization: `config/apps/init_apps.json`

Example:

```json
{
  "buckets": [
    { "name": "main" },
    { "name": "extras" },
    { "name": "nirsoft" }
  ],
  "apps": [
    { "name": "notepadplusplus" },
    { "name": "ipnetinfo", "version": "1.85", "hold": true },
    { "name": "some-app", "skip": true }
  ]
}
```

Note: core apps are installed automatically by script **19** from `core.apps`, so they typically should not be listed in `init_apps.json`.

Key fields:
- `buckets[].name` - bucket name (Scoop will resolve official buckets).
- `apps[].name` - app name.
- `apps[].version` - optional explicit version.
- `apps[].hold` - prevent updates for this app (Scoop `hold`).
- `apps[].pin` - pin a specific version (version-level protection).
- `apps[].skip` - skip installing this app while keeping it in config.

See `memory-bank/productContext.md` and `memory-bank/technicalDetails.md` for more patterns and behavior notes.

---

## Manager configuration

The file `config/manager_config.json` controls several behaviours of the manager:

- `manager.version` - Scoop Manager version displayed on the main menu header (intended to match releases).
- `backup.compression_level` - compression level for backup archives used by scripts 81/89 (see Technical Details for the level table).
- `core.apps` - list of "core" apps that are allowed in a fresh installation and are not removed by script 91.
- `exports.add_version_to_unlocked_apps` - when `true`, `export_apps_*.json` includes explicit `version` even for unlocked apps (not held/pinned); when `false`, unlocked apps omit `version` so imports install the latest.
- `logging.enabled` - enables or disables per-script transcript logging to `.logs/<script>_<name>.log`.
- `updates.backup_persist_before_update` - when `true`, script **42_Update-Apps** creates a persist backup before updating; when `false`, it skips the persist archive step.
- `updates.remove_old_versions` - when `true`, script **42_Update-Apps** removes obsolete, non-current, non-pinned versions after updating apps; when `false`, old versions are kept.
- `updates.freeze_scoop_core_updates` - emergency switch that suppresses Scoop's internal "is_scoop_outdated" self-check by periodically updating `last_update`, reducing surprise self-updates while leaving explicit `scoop update` calls unchanged.
- `stealth.exclude_paths` - optional list of substrings for the stealth watchdog to ignore when scanning PATH entries containing `portable_scoop` (see Technical Details for examples).
- `virustotal.api_key`, `virustotal.lookup` - configuration for VirusTotal integration; see the next section for details.

External command output (Scoop/git/robocopy/etc.) is captured in `.tmp/process/process.log`. When you run scripts through `Manage-ScoopMenu.ps1`, this file is truncated before each script run so it contains output only for the latest run.

## Persist links database

Some apps store data outside Scoop's `persist` folder. Use `config/persist_links.json` to define relinks for those apps.

Key rules:
- Each top-level key is an app name, and its value is an array of link pairs.
- `target` always starts with `persist\` (relative to `portable_scoop\persist`).
- Trailing `\` in `target` means a folder link; otherwise it is a file link.
- `link` is absolute (supports env vars) or starts with `apps\` for `portable_scoop\apps\...`.
- Links are applied only if the app is installed.
- `notes` is optional and ignored by the tool (for human context).

Example:
```json
{
  "brave": [
    {
      "link": "%LOCALAPPDATA%\\BraveSoftware\\Brave-Browser\\User Data\\",
      "target": "persist\\brave\\User Data\\"
    }
  ]
}
```

## VirusTotal integration (optional)

If you want to use Scoop's built-in VirusTotal checks (for example `scoop virustotal 7zip`) as part of this manager:

- Get a free API key from:  
  `https://www.virustotal.com/gui/my-apikey`
- Prefer putting it into `config/manager_config.local.json` (gitignored) to avoid committing secrets:

  ```jsonc
  {
    "virustotal": {
      "api_key": "YOUR_API_KEY_HERE"
    }
  }
  ```

- Or put it into `config/manager_config.json`:

  ```jsonc
  {
    "virustotal": {
      "api_key": "YOUR_API_KEY_HERE",
      "lookup": true
    }
  }
  ```

- When you run `19_Install-PortableScoop.ps1`, the manager will automatically apply it via:

  ```powershell
  scoop config virustotal_api_key <API key>
  ```

### How it is used

- When `virustotal.lookup` is `true`:
  - Script **19_Install-PortableScoop** runs a VirusTotal check before installing each core app from `core.apps` (it skips `scoop` itself because Scoop is already installed).
  - Script **22_Install-InitApps** runs VirusTotal checks before installing each app from `init_apps.json`:
    - For pinned/explicit versions (e.g. `ipnetinfo@1.90`, `rclone@1.68.0`), it first lets Scoop generate a version-specific manifest via `scoop download app@version --no-update-scoop`, then calls `scoop virustotal` on that manifest so VirusTotal sees the correct hash for that exact file.
    - For non-versioned entries (latest only), it runs `scoop virustotal <app> --no-update-scoop` directly.
    - If detections are found, you can choose to continue, skip that app, or abort the whole run.
  - Script **42_Update-Apps** does a VirusTotal check before updating each app to its latest version.
  - Script **29_Import-Scoop** performs VirusTotal checks for apps listed in the canonical export before calling `scoop import` (it currently only supports abort/continue; skipping requires editing the export file).
- Script **28_Scan-InstalledApps** lets you manually scan all installed apps using `scoop virustotal` and shows a summary table of clean/risky/error/skipped when lookups are enabled.

Example of the native Scoop behaviour (when VirusTotal is not yet configured):

```text
scoop virustotal 7zip
VirusTotal API key is not configured
You could get one from https://www.virustotal.com/gui/my-apikey and set with
    scoop config virustotal_api_key <API key>
```

### Local Antivirus integration (Windows Defender)

- Script **28_Scan-InstalledApps** can also run **Windows Defender** against each installed app (custom scans per shared `persist\<app>` folder and each `apps\<app>\<version>` folder, plus the Scoop manager itself), in Detect-only mode by default so you can clean up manually.
- For each app/version it shows:
  - VirusTotal result and report URL (if VirusTotal checks are enabled as above).
  - Antivirus (Windows Defender) scan result for that folder.
  - Raw Defender CLI output, including the `LIST OF DETECTED THREATS` block from `MpCmdRun.exe` for this run.
  - If Defender writes a detection event for this run, a per-file "Report" block with threat name, ID, severity, category, action taken, time, and the affected file path(s) (only events from the current scan session are used; older history entries are ignored).
- The Defender integration is **best effort** and depends on Microsoft Defender being active on the machine; if Defender is disabled or replaced by another antivirus, the script reports antivirus status as "NotAvailable" but still runs VirusTotal checks when configured.

---

## Troubleshooting

### Windows Terminal vs classic console

Scoop Manager is designed for Windows Console Host (classic console) so it can control the window icon and related UI behavior.
If you want the Scoop icon, set `Default terminal application` to `Windows Console Host` (you can run script `11_Open-TerminalSettings.ps1` to open the right Settings page).

### PowerShell Execution Policy

If scripts fail to load (`running scripts is disabled`):

- Prefer launching via `scoop_manager.cmd` (it uses process-scoped `-ExecutionPolicy Bypass`).
- If you still see policy errors on a corporate PC, policy may be enforced by WDAC/AppLocker/CLM or Group Policy.

On personal machines you can also set a user-scoped policy:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

The `scoop_manager.cmd` launcher uses `-ExecutionPolicy Bypass` for its own session (process-scoped only), but corporate controls (WDAC/AppLocker/CLM) can still block scripts in some environments.

### PATH / “Scoop not found”

- Ensure `portable_scoop\` exists next to `install_scoop\`.
- Ensure `portable_scoop\shims\scoop.cmd` exists.
- Rerun script `19_Install-PortableScoop.ps1` if installation failed.

### Mark of the Web (downloaded ZIPs)

If you unzip this project from a downloaded ZIP, Windows may mark extracted files as "from the internet".
If you see script blocking prompts/errors, unblock the ZIP before extracting or re-extract after unblocking.

---

## Architecture Overview (Mermaid)

```mermaid
graph TD
    A[scoop_manager.cmd] --> B[Manage-ScoopMenu.ps1]
    B --> C[Numbered script (00-99)]

    C --> D[ScriptBootstrap.psm1<br/>Initialize-ScriptEnvironment]
    D --> E[ScoopEnvironment.psm1<br/>stealth env + patching]

    C --> F[Feature modules<br/>(ExtendedAppList, UpdatableApps,<br/>Backup*, Export*, etc.)]

    E --> G[scoop.cmd]
    F --> G
```

For more detailed diagrams and patterns, see:
- `memory-bank/systemPatterns.md`
- `memory-bank/techContext.md`

---

## Contributing

This is a personal project, but feel free to adapt it for your own setups.  
The folder methodology, stealth mode, and script patterns can be reused in other portable app scenarios.

## License

This project is provided as-is for personal and enterprise use.

---

**Note**: Scoop itself is an open-source project maintained by the Scoop community.  
See [scoop.sh](https://scoop.sh/) for more information.
