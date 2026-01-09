# Changelog

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
