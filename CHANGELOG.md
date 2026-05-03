# Changelog

## 1.2.3 (2026-05-03)

### Changed
- Finalized product naming as **Scoop Manager** and clarified portable installation model (sibling `portable_scoop\` next to `install_scoop\`) in README.
- Reworked project documentation for public release: trimmed README to a single seamless top-to-bottom narrative (Purpose, How It Works, Tech Stack, Quick Start, Workflows, Folder Structure, Portable Installation Model, Configuration, Security Gates, Architecture Overview, Troubleshooting, Reference Docs).
- Split deep reference material out of the README into dedicated docs: `docs/SCRIPTS.md` (script catalogue + modules), `docs/CONFIGURATION.md` (JSON config reference), `docs/SECURITY_GATES.md` (VirusTotal gate + Defender flow).
- Added portfolio-grade README assets: badge banner, centered logo (`docs/assets/logo.png`), CLI screenshot embedded inside How It Works (`docs/assets/repo-card.png`), and a box-drawing folder-structure tree.
- Fixed Architecture Overview diagram so it renders on GitHub (quoted Mermaid labels, removed parser-breaking parentheses, replaced `<br/>` with `<br>`).
- Renamed `config/apps/init_apps_test.json` to `config/apps/init_apps_examples.json` to better describe its role as a comprehensive parameter-set reference.
- Moved `config/scoop.ico` to `docs/assets/logo.ico` and updated the two consoles-icon call sites in `scripts/Manage-ScoopMenu.ps1` and `modules/ScriptBootstrap.psm1`.
- Added repository baseline artifacts: `LICENSE` (MIT), `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md`, `.editorconfig`, `.github/PULL_REQUEST_TEMPLATE.md`, and `config/manager_config.local.example.json`.
- Refined `.gitignore` layout to clearly separate local secrets, runtime data, and machine-specific artifacts.

## 1.2.1 (2026-02-16)

### Changed
- VirusTotal checks now call `scoop virustotal` with `--no-depends` so each managed app decision is based on the requested app only (no dependency fan-out in the same check).

### Fixed
- VirusTotal result parsing now aggregates multiple summary lines from Scoop output and keeps the worst detection count, avoiding false-clean outcomes when manifests include multiple URLs.

## 1.2.0 (2026-02-15)

### Changed
- VirusTotal enforcement is now centralized via `Invoke-VirusTotalGateForApp` and applied consistently across install/update/import flows (`19`, `22`, `29`, `42`).
- Install/update/import now treat VirusTotal `Risky`, `Skipped` (lookup disabled, key missing, or no summary), and `Error` as blocking states with a unified `Continue / Skip / Abort` prompt.
- Manager VirusTotal config now uses `virustotal.lookup` as the explicit enable/disable switch and `virustotal.api_key` for authenticated requests.

### Fixed
- Canonical import (`29`) now supports real per-app skip: skipped apps are removed from the actual import set via a filtered temporary JSON file.
- Canonical import VirusTotal checks now preserve bucket context when available (`bucket/app@version`) to avoid ambiguous app resolution.
- Import completion messaging now reflects reality when all apps are skipped (`Import skipped`) instead of always reporting completion.
- VirusTotal initialization and gate-availability bootstrap is now unified for managed flows to avoid per-script duplication and drift.
- Managed flows now print a one-time root-cause hint when VirusTotal settings are unavailable, instead of leaving users without context.
- Removed duplicate VirusTotal `Error` warnings in install/update/import flows while keeping warning severity in audit mode (`28`).

## 1.1.3 (2026-01-29)

### Fixed
- Persist links: file relinks now use a symbolic link when link/target are on different drives (hard links require same drive).

## 1.1.2 (2026-01-27)

### Added
- Colorized persist link results in 27_ preview output (CREATE/SKIP/WARN) for faster scanning.

### Changed
- Updated `config/persist_links.json` with additional app relink entries/notes.

## 1.1.1 (2026-01-23)

### Fixed
- Improved app tables readability: Version/Update columns are wider and long versions are truncated with `~` to keep columns aligned (e.g. inkscape).

## 1.1.0 (2026-01-22)

### Fixed
- Fixed update detection for multi-version installs: if the latest bucket version is already installed for an app, scripts 41/42 no longer report it as needing an update.
- Made bucket metadata updates more resilient: on `scoop update` errors (non-zero exit or git error output), prompt to continue with local (potentially stale) buckets (41/42 via bootstrap, and 49).
- Unified external command execution (Scoop/git/etc.) via `modules/ProcessRunner.psm1` and a single `.tmp\\process\\process.log` to avoid `NativeCommandError` noise and keep console output consistent with transcript/log files.
- Improved menu logging stability: `.tmp\\process\\process.log` is reset before each menu script run, and log file writes no longer fail if `TextFile.psm1` isn't available in-session.

## 1.0.7 (2026-01-22)

### Fixed
- Avoided version sort errors when installed app versions contain non-semver strings in app lists/exports.

## 1.0.6 (2026-01-09)

### Added
- Added `config/persist_links.json` and script `27_Fix-PersistLinks.ps1` for optional relinks, plus automatic hooks after install/update/import flows.

## 1.0.5 (2026-01-09)

### Fixed
- Made `52_Cleanup-OldVersions.ps1` use the shared robust directory removal helper to handle locked/permission edge cases.

## 1.0.4 (2026-01-09)

### Added
- Added `updates.backup_persist_before_update` to optionally skip the persist archive in `42_Update-Apps.ps1`.

## 1.0.3 (2026-01-09)

### Fixed
- Fixed `scoop install app@version` failing with `You cannot call a method on a null-valued expression` by hardening the patched Scoop `lib/manifest.ps1` (infer bucket from `install.json` URL / fall back to URL when bucket is missing).

## 1.0.2 (2026-01-08)

### Fixed
- Updated the bundled Scoop installer patches (`patch/install_orig.ps1`, `patch/install.ps1`) to match upstream installer changes while preserving stealth mode (no persistent PATH writes).

## 1.0.1 (2025-12-18)

### Fixed
- Fixed the `scoop install app@version` flow in script `42_Update-Apps.ps1` and hardened the Scoop core patch so managers can update non-current versions without errors.
- Cleaned up `64_Run-Interactive.ps1` so the interactive window no longer prints the “The syntax of the command is incorrect.” banner when it starts.

## 1.0.0 (2025-12-17)

Initial Scoop Manager project implementation.
