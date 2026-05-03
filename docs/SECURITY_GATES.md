# Security Gates: VirusTotal and Windows Defender

Scoop Manager runs a centralised VirusTotal gate before every managed app action and offers an optional Windows Defender pass for installed apps. This document covers setup, gate flow, and the audit-only Defender integration.

For configuration keys (`virustotal.lookup`, `virustotal.api_key`), see [CONFIGURATION.md](CONFIGURATION.md).

---

## VirusTotal gate (install / update / import)

Scoop Manager uses Scoop's built-in VirusTotal checks (for example `scoop virustotal 7zip`) in all managed app-processing flows.

### Setup

- Get a free API key from <https://www.virustotal.com/gui/my-apikey>.
- Prefer putting it into `config/manager_config.local.json` (gitignored) to avoid committing secrets:

  ```jsonc
  {
    "virustotal": {
      "lookup": true,
      "api_key": "YOUR_API_KEY_HERE"
    }
  }
  ```

- Or put it into `config/manager_config.json`:

  ```jsonc
  {
    "virustotal": {
      "lookup": true,
      "api_key": "YOUR_API_KEY_HERE"
    }
  }
  ```

- When you run `19_Install-PortableScoop.ps1`, the manager will automatically apply it via:

  ```powershell
  scoop config virustotal_api_key <API key>
  ```

### How the gate is used

- Scripts **19_Install-PortableScoop**, **22_Install-InitApps**, **29_Import-Scoop**, and **42_Update-Apps** always run a central VirusTotal gate before each app action.
- The gate blocks on statuses `Risky` (detections), `Skipped` (lookup disabled, key missing, or no VT summary/hash), and `Error` (request/execution failure), and prompts:
  - `C` - continue with this app
  - `S` - skip this app
  - `A` - abort the whole script
- Script **29_Import-Scoop** supports real per-app skip: skipped apps are removed from a temporary filtered import JSON before `scoop import` runs.
- For versioned specs (`app@version`), the gate first runs `scoop download app@version --no-update-scoop` to generate a version-specific manifest, then checks that manifest with `scoop virustotal --no-depends --no-update-scoop`.
- If Scoop emits multiple VirusTotal summary lines for one check, the manager keeps the worst detection result for gating.
- Script **28_Scan-InstalledApps** is audit-only: it reports VirusTotal status per app and does not use Continue/Skip/Abort enforcement prompts.

### Native Scoop behaviour when not configured

```text
scoop virustotal 7zip
VirusTotal API key is not configured
You could get one from https://www.virustotal.com/gui/my-apikey and set with
    scoop config virustotal_api_key <API key>
```

---

## Windows Defender integration (audit-only, script 28)

Script **28_Scan-InstalledApps** can also run **Windows Defender** against each installed app — custom scans per shared `persist\<app>` folder and each `apps\<app>\<version>` folder, plus the Scoop manager itself — in Detect-only mode by default so you can clean up manually.

For each app/version it shows:

- VirusTotal result and report URL (when Scoop provides one).
- Antivirus (Windows Defender) scan result for that folder.
- Raw Defender CLI output, including the `LIST OF DETECTED THREATS` block from `MpCmdRun.exe` for this run.
- If Defender writes a detection event for this run, a per-file "Report" block with threat name, ID, severity, category, action taken, time, and the affected file path(s) (only events from the current scan session are used; older history entries are ignored).

The Defender integration is **best effort** and depends on Microsoft Defender being active on the machine. If Defender is disabled or replaced by another antivirus, the script reports antivirus status as `NotAvailable` and still reports VirusTotal status.
