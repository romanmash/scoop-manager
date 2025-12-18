# Project Brief

Portable Scoop Installation Manager is a PowerShell toolkit to install, manage,
back up, and remove a fully portable Scoop environment on Windows without
persistent system changes.

The project's primary goals are:

- Provide a predictable, repeatable way to install Scoop in a portable folder
  (no admin, no registry writes).
- Manage apps, buckets, backups, and migration packs through a consistent
  script/menu workflow.
- Keep the implementation simple, DRY, and friendly for both automation and
  interactive use.

Scope:

- Managing a single `portable_scoop` installation tree and its apps/buckets.
- Backup/restore of apps, persist data, and migration packs.
- Stealth-mode environment and Scoop patching to avoid permanent system
  changes.

Out of scope:

- Managing arbitrary non-Scoop software.
- Acting as a general-purpose Windows package manager.

Target users:

- Developers and power users who need Scoop in restrictive or portable
  environments (no admin, no permanent changes).

Constraints:

- Windows / PowerShell environment.
- No persistent registry or global PATH modifications (process-level env only).
- Scripts must work from any folder path, including those with spaces and
  leading hyphens.

