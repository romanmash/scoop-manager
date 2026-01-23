# System Patterns

## Architecture and modules

- Scripts:
  - Located under `scripts/`, named with numeric prefixes (`00_`, `21_`, `42_`, etc.) plus a Verb-Noun suffix.
  - Invoked via `Manage-ScoopMenu.ps1`, which builds a simple menu from filenames and associated metadata.
- Modules:
  - Located under `modules/`, each `.psm1` focused on a specific concern:
    - `ScoopEnvironment.psm1` - stealth environment setup, Scoop patching, environment helpers.
    - `ScriptBootstrap.psm1` - `Initialize-ScriptEnvironment` entrypoint for scripts.
    - `ScoopCommand.psm1` - wrappers for running Scoop commands safely (`Invoke-ScoopCommandScript`).
    - `ConsoleUi.psm1` - shared section/subsection header formatting (`Write-SectionHeader`, `Write-SubsectionHeader`).
    - `TextFile.psm1` - UTF-8 (no BOM) file/JSON write helpers (`Write-TextFileUtf8NoBom`, `Write-JsonFileUtf8NoBom`).
    - `ProcessRunner.psm1` - unified external command runner (`Invoke-ExternalCommandLogged`) writing to `.tmp\\process\\process.log`.
    - `ExtendedAppList.psm1`, `UpdatableApps.psm1` - list formatting and update detection.
    - Backup/restore helpers (`BackupConfig`, `BackupPersist`, `BackupArchive`, `BeforeAfterState`, etc.).
    - Path and JSON helpers (`PathTools`, `JsonFile`, `ScoopPathTools`, etc.).
    - `VirusTotalInit.psm1` - best-effort VirusTotal initialization used by multiple scripts.

### High-level architecture (mermaid)

```mermaid
graph TD
    A[scoop_manager.cmd] --> B[Manage-ScoopMenu.ps1]
    B --> C[Numbered script in scripts/]

    C --> D[ScriptBootstrap.psm1<br/>Initialize-ScriptEnvironment]
    D --> E[ScoopEnvironment.psm1<br/>stealth env + patching]

    C --> F[Feature modules in modules/]

    E --> G[scoop.cmd (Scoop CLI)]
    F --> G
```

## Control and data flow

- Entry:
  - `scoop_manager.cmd` launches `Manage-ScoopMenu.ps1`.
  - Menu script resolves available numbered scripts and executes the chosen one.
- Per-script bootstrap:
  - Each operational script imports `ScriptBootstrap.psm1` and calls `Initialize-ScriptEnvironment` to:
    - Derive `ProjectRoot`, `ScoopRoot`, `ScoopShim`.
    - Enter stealth mode.
    - Apply or re-apply Scoop lib patches as needed.
- Workflows:
  - Scripts then import the feature modules they need and call into exposed functions, keeping business logic in modules and scripts as thin orchestration.

## Structural conventions

- Directory layout:
  - `@/` used for metadata/docs, `_/` (and this repo) for executable artifacts.
  - Scripts sorted lexicographically by numeric prefix to form a visual workflow.
- Naming:
  - PowerShell `Verb-Noun` naming for scripts and functions.
  - Script references use full names (e.g., `script 42_Update-Apps.ps1`) in messages.
- Error handling:
  - `$ErrorActionPreference = 'Stop'` in scripts.
  - External commands: run via `Invoke-ExternalCommandLogged` to avoid `NativeCommandError` transcript noise and keep console output consistent with log output.
  - Shared helpers return exit codes (`0` success, `4` controlled failure conditions).
  - `Test-ScoopInstalled` centralizes "is Scoop usable?" checks.
- Visual output:
  - Major sections: use `Write-SectionHeader` (renders `===...` rule blocks) with uppercase titles.
  - Subsections: use `Write-SubsectionHeader` (renders `---...` rule blocks) with title-cased titles.
  - Sub-subsections: avoid rule blocks; print a blank line + a short label (often with `[*]`) and continue output.
  - Status prefixes: `[*]`, `[OK]`, `[SKIP]`, plus `Write-Warning` and `Write-Error`.
  - Warnings: use a single `Write-Warning` line as the summary, and print extended details on subsequent lines with `Write-Host` (no multi-line `Write-Warning` blocks).
