# Product Context

## Users and roles

- Individual developers needing a portable Scoop toolchain on shared or locked-down machines.
- Power users maintaining multiple Scoop-based environments on removable or synced drives.

## Main use cases

- Install a fresh portable Scoop into a dedicated folder without admin rights.
- Install a curated set of "init apps" via `config/apps/init_apps.json`.
- List, update, and uninstall apps and buckets through numbered menu scripts.
- Export/import app lists and Scoop state for backup or migration.
- Create and restore migration packs and persist backups.
- Completely remove the portable Scoop installation and its data when no longer needed.

## Behavioral expectations

- Scripts are invoked via a menu (`scoop_manager.cmd` -> `scripts/Manage-ScoopMenu.ps1`) and run without extra "are you sure?" prompts (menu selection is the confirmation), with rare exceptions where native Scoop prompts remain.
- Output is clear and structured, with consistent headings and status markers so users can understand what's happening at a glance.
- Native Scoop commands are preferred wherever possible; custom logic is used only when Scoop lacks needed behavior (e.g., stealth mode, migration helpers).

## Important rules and edge cases

- All paths must be handled robustly, including spaces and leading hyphens in directory names; helper functions (`Resolve-LiteralPathSafe`, `PathTools`) are used to avoid PowerShell treating segments as switches.
- Stealth mode must be preserved: no scripts may write persistent environment variables or registry settings.
- Refactors that change script names must preserve the numeric ordering and menu semantics to avoid confusing users.
