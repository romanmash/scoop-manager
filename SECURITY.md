# Security Policy

## Supported Releases

This repository is currently maintained as a rolling release. Security fixes are applied to the latest main branch state.

## Reporting a Vulnerability

- Do not open a public issue for sensitive vulnerabilities.
- Prefer private disclosure using GitHub Security Advisories for this repository.
- If private advisory submission is unavailable, contact the repository owner through GitHub profile contact channels and include:
  - affected script/module path
  - reproduction steps
  - impact assessment
  - proposed mitigation (if available)

## Scope Notes

Security-sensitive areas include:

- Configuration and secret handling (`config/manager_config*.json`)
- Download/install/update execution paths
- Backup/export archives containing local data
- Any path/command execution handling in scripts and modules
