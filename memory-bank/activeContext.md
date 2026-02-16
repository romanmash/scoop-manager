# Active Context

## Current focus

- Keep managed app flows (`19`, `22`, `29`, `42`) consistent and reliable:
  - Central VirusTotal gating with one shared decision path.
  - Consistent external command logging through `ProcessRunner`.
  - Stable post-install/update/import persist relink execution via `PersistLinks`.

## Relevant areas

- `modules/VirusTotalScan.psm1`, `modules/VirusTotalInit.psm1`, `modules/VirusTotalConfig.psm1`.
- `scripts/19_Install-PortableScoop.ps1`, `scripts/22_Install-InitApps.ps1`, `scripts/29_Import-Scoop.ps1`, `scripts/42_Update-Apps.ps1`.
- `modules/ProcessRunner.psm1` and menu logging flow (`scripts/Manage-ScoopMenu.ps1`).
- `memory-bank/*.md` and `README.md` for behavior/documentation sync.

## Immediate next steps

- Keep security and UX policy centralized (no per-script VT branching drift).
- Document behavior changes in README/changelog/memory-bank for every release.
- Preserve pinned/held semantics while iterating update/import/install flows.
