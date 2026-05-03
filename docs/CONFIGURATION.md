# Configuration Reference

Scoop Manager's behaviour is driven by three JSON files under `config/`:

| File | Purpose |
|---|---|
| `config/manager_config.json` | Manager-level behaviour (logging, updates, VirusTotal, stealth, core apps). |
| `config/apps/init_apps.json` | Target app + bucket set installed by script 22 on a fresh installation. |
| `config/persist_links.json` | Relinks for apps that store data outside Scoop's `persist` folder. |

A second manager config — `config/manager_config.local.json` (gitignored) — can override committed values for local secrets such as the VirusTotal API key. See [`config/manager_config.local.example.json`](../config/manager_config.local.example.json) for the template.

For VirusTotal-specific behaviour (gate flow, statuses, per-app prompts, Defender integration), see [SECURITY_GATES.md](SECURITY_GATES.md).

---

## `config/apps/init_apps.json`

Defines the buckets and apps that script **22_Install-InitApps** installs on a fresh setup.

```json
{
  "buckets": [
    { "name": "main" },
    { "name": "extras" },
    { "name": "nirsoft" }
  ],
  "apps": [
    { "name": "notepadplusplus" },
    { "name": "ipnetinfo", "version": "1.85", "hold": true },
    { "name": "some-app", "skip": true }
  ]
}
```

> Core apps are installed automatically by script **19** from `core.apps`, so they typically should not be listed in `init_apps.json`.

### Key fields

- `buckets[].name` - bucket name (Scoop will resolve official buckets).
- `apps[].name` - app name.
- `apps[].version` - optional explicit version.
- `apps[].hold` - prevent updates for this app (Scoop `hold`).
- `apps[].pin` - pin a specific version (version-level protection).
- `apps[].skip` - skip installing this app while keeping it in config.

A more comprehensive example showing multi-version installs, holds, pins, and `current` selection lives in [`config/apps/init_apps_examples.json`](../config/apps/init_apps_examples.json).

---

## `config/manager_config.json`

Controls manager behaviour:

- `manager.version` - Scoop Manager version displayed on the main menu header (intended to match releases).
- `backup.compression_level` - compression level for backup archives used by scripts 81/89.
- `core.apps` - list of "core" apps that are allowed in a fresh installation and are not removed by script 91.
- `exports.add_version_to_unlocked_apps` - when `true`, `export_apps_*.json` includes explicit `version` even for unlocked apps (not held/pinned); when `false`, unlocked apps omit `version` so imports install the latest.
- `logging.enabled` - enables or disables per-script transcript logging to `.logs/<script>_<name>.log`.
- `updates.backup_persist_before_update` - when `true`, script **42_Update-Apps** creates a persist backup before updating; when `false`, it skips the persist archive step.
- `updates.remove_old_versions` - when `true`, script **42_Update-Apps** removes obsolete, non-current, non-pinned versions after updating apps; when `false`, old versions are kept.
- `updates.freeze_scoop_core_updates` - emergency switch that suppresses Scoop's internal "is_scoop_outdated" self-check by periodically updating `last_update`, reducing surprise self-updates while leaving explicit `scoop update` calls unchanged.
- `stealth.exclude_paths` - optional list of substrings for the stealth watchdog to ignore when scanning PATH entries containing `portable_scoop`.
- `virustotal.lookup` - enables/disables VirusTotal lookups (full flow in [SECURITY_GATES.md](SECURITY_GATES.md)).
- `virustotal.api_key` - VirusTotal API key used by managed install/update/import gates and script 28 when lookups are enabled.

External command output (Scoop/git/robocopy/etc.) is captured in `.tmp/process/process.log`. When you run scripts through `Manage-ScoopMenu.ps1`, this file is truncated before each script run so it contains output only for the latest run.

---

## `config/persist_links.json`

Some apps store data outside Scoop's `persist` folder. Use this file to define relinks that pull that data back under `portable_scoop\persist` so backup, migration, and uninstall flows cover it.

### Rules

- Each top-level key is an app name, and its value is an array of link pairs.
- `target` always starts with `persist\` (relative to `portable_scoop\persist`).
- Trailing `\` in `target` means a folder link; otherwise it is a file link.
- `link` is absolute (supports env vars) or starts with `apps\` for `portable_scoop\apps\...`.
- Folder links are created as junctions. File links are created as hard links when possible; if link/target are on different drives, a symbolic link is used instead.
- Links are applied only if the app is installed.
- `notes` is optional and ignored by the tool (for human context).

### Example

```json
{
  "brave": [
    {
      "link": "%LOCALAPPDATA%\\BraveSoftware\\Brave-Browser\\User Data\\",
      "target": "persist\\brave\\User Data\\"
    }
  ]
}
```

The relinker is invoked automatically after installs, updates, and imports, and can be run manually via script **27_Fix-PersistLinks** (preview + confirmation).
