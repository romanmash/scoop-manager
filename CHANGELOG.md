# Changelog

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
