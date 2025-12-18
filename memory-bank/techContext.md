# Tech Context

## Stack

- PowerShell (Windows) scripts and modules.
- Scoop (Windows package manager) as the underlying tool being managed.

## Key modules and responsibilities

- `ScoopEnvironment.psm1`:
  - Initializes process-level environment variables for Scoop (stealth mode).
  - Validates Scoop installation, shim availability, and environment.
  - Applies and re-applies file-based patches to Scoop's lib scripts
    (`system.ps1`, `core.ps1`, `decompress.ps1`, `install.ps1`) to:
    - Remove persistent registry/env writes.
    - Fix MSI path handling and error 1639 for paths with spaces/hyphens.
- `ScriptBootstrap.psm1`:
  - `Initialize-ScriptEnvironment` helper; standard entrypoint for scripts.
  - Computes script path and project root, imports `ScoopEnvironment`, returns a
    context object.
- `ScoopCommand.psm1`:
  - `Invoke-ScoopCommand` and `Invoke-ScoopCommandScript` wrappers.
  - Uses the environment context and `Test-ScoopInstalled` to safely run Scoop
    CLI calls.
- Other helpers:
  - `PathTools.psm1` for safe path resolution.
  - `JsonFile.psm1` for JSON file loading/writing.
  - Backup/restore modules for packaging persist data or migration packs.
  - `ConsoleUi.psm1` and `TextFile.psm1` for shared console/IO behavior.

## Build, run, test

- There is no compiler build; the project is executed directly via PowerShell
  and Scoop.
- Primary entry:
  - Double-click or run `scoop_manager.cmd` to launch the menu.
- Validation patterns:
  - Scripts rely on Scoop exit codes and error handling.
  - Manual flows:
    - Fresh install via `19_Install-PortableScoop.ps1`.
    - App install via `22_Install-InitApps.ps1`.
    - Update flows via `41_Check-Updates.ps1`, `42_Update-Apps.ps1`,
      `49_Update-Scoop.ps1`.
  - Refactor verification is done by running affected scripts and confirming
    behavior.

## Constraints

- Must run without admin rights.
- Must avoid persistent changes (no registry writes, no global PATH
  modifications).
- Must handle Windows paths with spaces and leading hyphens.

