# Progress Log

## 2026-01-09

- Added optional persist backup flag for app updates and wired it into script 42.
- Hardened versioned installs by patching Scoop `lib/manifest.ps1` to handle missing bucket in `install.json`.
- Improved old-version cleanup reliability by using the shared robust directory removal helper in script 52.
- Validation: ran the affected scripts in a local test run; confirmed 42_ updates and 52_ cleanup complete without the prior errors.

## 2026-01-22

- Bumped version to 1.0.7.
- Fixed app version sorting to handle non-semver strings without terminating errors in logs.

## 2026-01-10

- Added a persist links database (`config/persist_links.json`) and the shared relink helper module (`modules/PersistLinks.psm1`).
- Introduced script `27_Fix-PersistLinks.ps1` with preview/confirm flow and detailed link checks (exists, link type, target match).
- Wired persist relinks into install/update/import flows (19, 22, 29, 42) to apply per app when installed.
- Validation: manual run of 27_ to verify preview output and link creation behavior.

## 2025-12-31

- Refactored script bootstrapping:
  - Introduced `modules/ScriptBootstrap.psm1` with `Initialize-ScriptEnvironment`.
  - Migrated operational scripts to use the new bootstrap instead of manual path calculations.
- Centralized Scoop command wrappers:
  - Implemented `Invoke-ScoopCommandScript` in `modules/ScoopCommand.psm1`.
  - Updated simple wrapper scripts (help, bucket list/known, cache cleanup, checkup, config, reset) to use the shared wrapper.
- Fixed duplication and path handling:
  - Introduced `modules/PathTools.psm1` and `modules/FileRemoval.psm1`.
  - Standardized safe path resolution and robust directory removal with retries/fallbacks.
- Documentation:
  - Updated `README.md`, `PROJECT_REVIEW.md`, and `REFACTORING_ISSUES.md` to reflect the new bootstrap and command wrapper patterns.
  - Created structured memory-bank files under `memory-bank/` based on the original `docs/.memory-bank.md`.

Validation:
- Manual runs of key scripts (install, list, update, export, backup/uninstall) in a test environment with spaces/hyphens in the path.

Follow-ups:
- Continue to keep `systemPatterns.md` and `decisionLog.md` updated as further structural changes are made.
