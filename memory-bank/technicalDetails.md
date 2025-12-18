## Technical Details

### Design principles

- **Stealth mode** – all environment variables are process-level only (no
  registry writes, no persistent system changes). Works without admin rights
  and leaves no traces when PowerShell closes.
- **Relative paths only** – scripts work from any folder path, including those
  with spaces and leading hyphens.
- **No admin required** – pure user-space installation, no registry
  modifications.
- **Portable** – copy the entire folder structure between PCs and keep the same
  Scoop environment.
- **Version-control friendly** – JSON configuration and scripts can be tracked
  in Git; local overrides go into `manager_config.local.json`.
- **Idempotent flows** – scripts are designed so they can be run multiple times
  safely.
- **No extra confirmations** – scripts execute immediately; menu selection is
  the confirmation (no "type YES" prompts), except where native Scoop prompts
  remain.
- **Consistent UX** – uniform visual hierarchy across scripts (section and
  subsection headers, status prefixes like `[*]`, `[OK]`, `[SKIP]`).
- **PowerShell naming conventions** – scripts and functions follow Verb-Noun
  format.
- **Shared modules** – reusable helpers in `modules/` remove duplication (for
  example `ScriptBootstrap`, `ScoopEnvironment`, `ScoopCommand`,
  `ConsoleUi`, `TextFile`).

### Stealth mode and environment

All operational scripts rely on `Initialize-ScriptEnvironment` and
`Initialize-ScoopEnvironment` to:

- Set process-level env vars:
  - `SCOOP` – root of the portable installation.
  - `SCOOP_CACHE`, `SCOOP_GLOBAL`.
  - `XDG_CONFIG_HOME` – pointed at the portable tree to avoid user profile
    pollution.
  - `PATH` – includes `portable_scoop\shims` for the current session.
- Patch Scoop's lib scripts so they:
  - Stop writing persistent env/registry entries.
  - Handle MSI paths with spaces and hyphens correctly.

When PowerShell closes, all env vars disappear; only patched Scoop files remain
on disk inside the portable folder.

### PowerShell versions

- Prefer `pwsh.exe` (PowerShell 7+) when available.
- Fall back to `powershell.exe` (Windows PowerShell 5.1) when needed.
- `scoop_manager.cmd` chooses the host and applies `-ExecutionPolicy Bypass`
  for the current process.

### Export and import formats

Script `71_Export-Apps.ps1`:

- Produces `export_apps_*.json` in `config/apps/` (internal format).
- Attempts to export only explicitly installed apps (dependencies filtered by
  reading `install.json`).
- Encodes:
  - Single-version apps.
  - Held apps.
  - Multi-version apps with pinned versions, current version, and other
    installed versions.
- Respects `exports.add_version_to_unlocked_apps` from `manager_config.json` so
  you can choose whether unlocked apps carry explicit versions or install
  "latest" on import.

Script `22_Install-InitApps.ps1` and `23_Import-Apps.ps1`:

- Consume the same format as `init_apps.json` / `export_apps_*.json`.
- Support multiple versions, `pin`, `hold`, and skip flags.

Script `79_Export-Scoop.ps1` and `29_Import-Scoop.ps1`:

- Use native `scoop export` and `scoop import` with `export_scoop_*.json` for
  canonical Scoop state.

### Backup and migration

Persist backup:

- `81_Backup-Persist.ps1`:
  - Creates a ZIP archive of `portable_scoop\persist` under `backup\persist\`.
  - Includes hidden files and empty directories.
  - Compression level is configurable via `manager_config.json`.
- `24_Restore-Persist.ps1`:
  - Restores from the latest persist backup.
  - Skips restore if `persist\` is not empty (requires cleanup via script 54).

Migration packs:

- `88_Backup-MigrationPack.ps1`:
  - Creates an archive that combines apps configuration and persist data for
    moving to another PC or path.
- `26_Restore-MigrationPack.ps1`:
  - Restores a migration pack onto a fresh installation.
  - Uses path helpers to adjust any embedded paths.

Full portable backup:

- `89_Backup-PortableScoop.ps1`:
  - Creates an archive of the entire `portable_scoop` folder (apps, shims,
    cache, persist).

### VirusTotal and antivirus integration

VirusTotal:

- `modules/VirusTotalInit.psm1`:
  - Handles best-effort initialization of VirusTotal integration.
  - Reads API key from Scoop config (same mechanism as `scoop virustotal`).
- Scripts:
  - `19_Install-PortableScoop.ps1` and `22_Install-InitApps.ps1` ensure
    VirusTotal integration is usable quickly after install if the key is set.
  - `28_Scan-InstalledApps.ps1` uses VirusTotal to scan installed apps and
    renders a summary (Clean / Risky / Error / Skipped) plus details.

Local antivirus (Windows Defender):

- Dedicated module encapsulates:
  - Locating `MpCmdRun.exe`.
  - Running folder scans.
  - Correlating scan results with event log entries for threat details.
- Script `28_Scan-InstalledApps.ps1`:
  - Optionally runs Defender custom scans for each app/version folder.
  - Prints threat names, IDs, severity, categories, actions, and timestamps
    when available.
  - Treats Defender integration as best-effort; if Defender is unavailable,
    VirusTotal output still works when configured.

These details are kept here to avoid cluttering the README while preserving a
single, coherent view of how the system behaves in depth.

