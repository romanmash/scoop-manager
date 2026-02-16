# Decision Log

## 2026-02-16 - Make VirusTotal gate app-scoped and deterministic

Context:

- VirusTotal checks are executed through `scoop virustotal`, which may include
  dependency checks unless explicitly disabled.
- Scoop may emit multiple summary lines for a single invocation (for example
  manifests with multiple URLs), and first-line parsing can under-report risk.

Decision:

- Run managed VirusTotal checks with `--no-depends` in
  `Invoke-VirusTotalCheckForApp`.
- Aggregate all parsed summary lines from Scoop output and keep the worst
  detection count for final status.

Reasoning:

- Gate decisions must be tied to the requested app, not mixed dependency
  outcomes from the same command.
- Security posture should be pessimistic when multiple results are present.

Impact:

- Lower and more predictable VirusTotal API consumption per managed app check.
- Reduced risk of false-clean statuses in install/update/import gating and
  audit output.

---

## 2026-02-15 - Enforce VirusTotal gate across managed app flows

Context:

- VirusTotal checks were previously treated as optional by config (`lookup`) and
  script-specific logic diverged over time.
- Import flow (`29`) could prompt skip but still imported the original full app
  list.

Decision:

- Centralize install/update/import enforcement in
  `Invoke-VirusTotalGateForApp` and use it from scripts `19`, `22`, `29`, `42`.
- Treat `Risky`, `Skipped` (unknown/no summary), and `Error` as blocking
  statuses with a unified `Continue / Skip / Abort` decision prompt.
- Keep `virustotal.lookup` as the explicit enable/disable gate for managed VirusTotal checks.
- For canonical import (`29`), implement real skip by writing a filtered
  temporary import JSON and importing that file.

Reasoning:

- One central gate removes duplicated branching and keeps security policy
  consistent in every managed app-processing path.
- Real skip in import makes user decisions effective, not cosmetic.

Impact:

- Managed install/update/import scripts now share one VirusTotal decision path.
- Missing API key now surfaces as a blocking decision in managed flows instead
  of silent bypass.
- Script `28` remains audit/reporting focused (no gate prompt).

---

## 2025-01-27 – Centralize script bootstrap

Context:

- Many scripts duplicated manual path resolution and environment initialization
  logic.

Decision:

- Create `modules/ScriptBootstrap.psm1` with `Initialize-ScriptEnvironment` and
  migrate scripts to use it.

Reasoning:

- Eliminates a large amount of duplicated code.
- Reduces risk of inconsistent path handling.
- Makes it easier to adjust bootstrap behavior (for example stealth mode) in
  one place.

Impact:

- All operational scripts under `scripts/` that need the Scoop context now
  import `ScriptBootstrap.psm1` and call `Initialize-ScriptEnvironment`.

---

## 2025-01-27 – Use shared Scoop command wrapper

Context:

- Several small scripts wrapped simple Scoop commands with nearly identical
  patterns.

Decision:

- Implement `Invoke-ScoopCommandScript` in `modules/ScoopCommand.psm1` and
  migrate the wrappers to use it.

Reasoning:

- Reduces duplication and keeps UX consistent for simple commands (help, bucket
  list/known, cache, checkup, config, reset).

Impact:

- Scripts `08`, `31`, `32`, `51`, `55`, `61`, `62` now call the shared helper
  instead of re-implementing view/wrap logic.

---

## 2025-01-27 – Stealth mode via file-based patches

Context:

- Scoop's default behavior writes to the registry and persistent environment,
  which conflicts with the project's portability goals.

Decision:

- Maintain patched copies of Scoop's installer and core lib files under
  `patch/`, and apply them via `ScoopPatching.psm1` and
  `ScoopEnvironment.psm1`.

Reasoning:

- Ensures Scoop behaves in a process-only manner without modifying the user's
  system.
- Keeps behavior consistent across updates by re-applying patches after Scoop
  updates.

Impact:

- Stealth mode is a core invariant: scripts must rely on
  `Initialize-ScriptEnvironment` and not attempt persistent env modifications
  themselves.

---

## 2025-12-16 – Support local manager config overrides

Context:

- `config/manager_config.json` is tracked in Git, but some settings (for
  example VirusTotal API key) are secrets or machine-specific.

Decision:

- Allow an optional `config/manager_config.local.json` to override
  `config/manager_config.json`, and gitignore the local file.

Reasoning:

- Keeps repo defaults version-controlled while reducing risk of committing
  secrets.
- Supports per-machine customization without forking tracked config.

Impact:

- Scripts and modules that call `Get-ManagerConfigJson` automatically see merged
  configuration.

---

## 2025-12-16 – Centralize VirusTotal initialization

Context:

- Multiple scripts duplicated the same best-effort VirusTotal module import and
  settings retrieval logic.

Decision:

- Add `modules/VirusTotalInit.psm1` with `Initialize-VirusTotalIntegration` and
  reuse it across scripts.

Reasoning:

- Reduces copy/paste and keeps warning behavior consistent.
- Avoids module scoping pitfalls by ensuring `Invoke-VirusTotalCheckForApp` is
  available to scripts after initialization.

Impact:

- Scripts `19`, `22`, `28`, `29`, `42` initialize VirusTotal through the shared
  helper.

---

## 2025-12-16 – Centralize UTF-8 (no BOM) file writes

Context:

- Many scripts and modules duplicated UTF-8-no-BOM boilerplate for writing
  files.

Decision:

- Add `modules/TextFile.psm1` with `Write-TextFileUtf8NoBom` and
  `Write-JsonFileUtf8NoBom` and use them from bootstrap/environment.

Reasoning:

- Keeps encoding behavior consistent and reduces repeated low-level plumbing.

Impact:

- All previous direct `UTF8Encoding $false` call sites now write through the
  shared helpers.

---

## 2025-12-16 – Centralize console header formatting

Context:

- Many scripts manually printed identical section/subsection headers with
  repeated `Write-Host "===="` / `"----"` blocks.

Decision:

- Add `modules/ConsoleUi.psm1` with `Write-SectionHeader` and
  `Write-SubsectionHeader` and load it from bootstrap/environment.

Reasoning:

- Keeps console UX consistent and reduces copy/paste blocks across scripts.

Impact:

- Most scripts and modules now call the shared helpers instead of duplicating
  header blocks. The main exception is `scripts/Manage-ScoopMenu.ps1`, which
  intentionally preserves its fixed separators for transcript readability.

---

## 2026-01-22 - Unified external command logging

Context:

- Native commands (notably `scoop.cmd`) may write transient/network errors to stderr.
- When executed directly via `& ... 2>&1`, PowerShell can emit `NativeCommandError` records (with `At ... char ...`) into transcript/log files, causing console output to differ from log output.

Decision:

- Introduce `modules/ProcessRunner.psm1` with `Invoke-ExternalCommandLogged` and route external process calls (Scoop, git, etc.) through it.
- Use a single stable tmp file: `.tmp\\process\\process.log` per command run.
- When running scripts from the menu, truncate `.tmp\\process\\process.log` before each script run so it contains only the latest run.

Reasoning:

- Keeps console output and transcript/log output consistent.
- Avoids confusing PowerShell error records caused by native stderr.
- Provides “live-ish” progress while commands run.

Impact:

- Scripts/modules should avoid `& scoop.cmd ... 2>&1` and use `Invoke-ExternalCommandLogged` for external commands.
