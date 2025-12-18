# Active Context

## Current focus

- Finalizing refactors and documentation for production readiness:
  - Centralized bootstrap and environment initialization.
  - Centralized Scoop command wrappers.
  - Cleanup of duplicated logic (directory removal, path handling).
  - Migration of memory-bank content into the `memory-bank/` directory.

## Relevant areas

- `modules/ScriptBootstrap.psm1`, `modules/ScoopEnvironment.psm1`, `modules/ScoopCommand.psm1`.
- Backup and migration scripts/modules (`scripts/81/88/89`, `modules/Backup*`, `modules/ExportApps.psm1`).
- `memory-bank/*.md` and `docs/.memory-bank.md` (being retired).

## Immediate next steps

- Ensure all scripts import required modules for the helpers they use.
- Keep memory-bank docs in sync with future architectural changes and decisions.
- After user review, commit the refactor and documentation changes.

