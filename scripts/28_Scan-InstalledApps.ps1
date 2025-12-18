<#
.SYNOPSIS
Scans installed apps using VirusTotal (and optional local Antivirus)

.CMD
scoop virustotal
#>

$ErrorActionPreference = 'Stop'

# Remember when this script run started so we can show
# only threats detected during the active scan session.
$ScriptStartTime = Get-Date

# Load bootstrap module
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx         = Initialize-ScriptEnvironment
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot   = $ctx.ScoopRoot
$ScoopShim   = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

Write-SectionHeader -Title 'VIRUS SCAN - INSTALLED APPS'

Write-Host "[*] Using Scoop shim: $ScoopShim"
Write-Host ""

# Load VirusTotal scan helper (VirusTotal integration)
$VirusTotalScanPath = Join-Path $ProjectRoot 'modules\VirusTotalScan.psm1'
if (-not (Test-Path $VirusTotalScanPath)) {
    Write-Warning "VirusTotalScan module not found at: $VirusTotalScanPath"
    Write-Host ""
    exit 4
}

$vtSettings = $null
$VirusTotalInitPath = Join-Path $ProjectRoot 'modules\VirusTotalInit.psm1'
if (Test-Path -LiteralPath $VirusTotalInitPath) {
    Import-Module $VirusTotalInitPath -Force -ErrorAction SilentlyContinue
    if (Get-Command -Name Initialize-VirusTotalIntegration -ErrorAction SilentlyContinue) {
        $vtSettings = Initialize-VirusTotalIntegration -ProjectRoot $ProjectRoot
    }
}

function Write-AvSummaryForLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Scan
    )

    if (-not $Scan) {
        return
    }

    if (-not $Scan.AvAvailable) {
        if ($Scan.Notes) {
            Write-Host ("[*] Antivirus (Windows Defender) scan: NotAvailable ({0})" -f $Scan.Notes)
        } else {
            Write-Host "[*] Antivirus (Windows Defender) scan: NotAvailable"
        }
        Write-Host ""
        return
    }

    $status = $Scan.AvStatus
    $pathForDisplay = if ($Scan.Path) { $Scan.Path } else { $Label }

    Write-Host ("[*] Antivirus (Windows Defender) scan: {0}" -f $pathForDisplay)

    $resultText = switch ($status) {
        'CleanOrRemediated' { "Clean/Remediated (ExitCode=$($Scan.ExitCode))" }
        'ThreatRemediated'  { "Threats detected and remediated (ExitCode=$($Scan.ExitCode))" }
        'ThreatDetected'    { "Threats detected (ExitCode=$($Scan.ExitCode))" }
        'ThreatOrError'     { "Threat or error reported (ExitCode=$($Scan.ExitCode))" }
        'Error'             { "Error during scan (ExitCode=$($Scan.ExitCode))." }
        default             { "Status=$status (ExitCode=$($Scan.ExitCode))" }
    }

    Write-Host ("[*] Result: {0}" -f $resultText)

    if ($Scan.Threats -and $Scan.Threats.Count -gt 0) {
        Write-Host ("[*] Antivirus threats for {0}: {1}" -f $Label, ($Scan.Threats -join ', '))
    }

    if ($Scan.RawOutput -and $Scan.RawOutput.Count -gt 0) {
        Write-Host "[*] Output:"
        $Scan.RawOutput | ForEach-Object {
            if ($_ -is [string]) {
                ($_ -split "(`r`n|`n|`r)") | ForEach-Object {
                    $line = $_.Trim()
                    if ($line -ne '') {
                        Write-Host ("    {0}" -f $line)
                    }
                }
            }
        }
    }
}

function Write-DefenderThreatHistoryForPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $threatCmd = Get-Command -Name Get-MpThreatDetection -ErrorAction SilentlyContinue
    if (-not $threatCmd) {
        return
    }

    $resolvedPath = $Path
    try {
        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
    }

    $pattern = "*$resolvedPath*"

    # Use the script-level start time (captured at the top of this script)
    # to limit detections and events to the current run.
    $sinceTime = $ScriptStartTime
    if (-not $sinceTime) {
        $sinceTime = Get-Date
    }

    try {
        $detections = Get-MpThreatDetection -ErrorAction SilentlyContinue |
            Where-Object {
                $_.InitialDetectionTime -ge $sinceTime -and
                ($_.Resources -join ';') -like $pattern
            } |
            Sort-Object InitialDetectionTime -Descending
    } catch {
        $detections = @()
    }

    # Enrich with Defender operational event details (if available). This is the primary
    # source for per-file threat info; fall back to Get-MpThreatDetection only if needed.
    try {
        if (Get-Command Get-DefenderThreatEventForPath -ErrorAction SilentlyContinue) {
            $eventDetails = Get-DefenderThreatEventForPath -Path $Path -Since $sinceTime
            if ($eventDetails) {
                # Parse per-file items from the event details
                $baseThreat = if ($eventDetails.PSObject.Properties['Name']) { $eventDetails.Name } else { '(unknown threat)' }
                $threatId   = $null
                if ($eventDetails.PSObject.Properties['ID']) {
                    $threatId = $eventDetails.ID
                }
                $severity   = if ($eventDetails.PSObject.Properties['Severity']) { $eventDetails.Severity } else { $null }
                $category   = if ($eventDetails.PSObject.Properties['Category']) { $eventDetails.Category } else { $null }
                $time       = if ($eventDetails.PSObject.Properties['TimeCreated']) { $eventDetails.TimeCreated } else { $null }
                $actionText = $null
                if ($eventDetails.PSObject.Properties['Action']) {
                    $actionText = $eventDetails.Action
                    if ($eventDetails.PSObject.Properties['Action Status']) {
                        $actionText = "{0} ({1})" -f $actionText, $eventDetails.'Action Status'
                    }
                }

                if ($eventDetails.PSObject.Properties['Path'] -and $eventDetails.Path) {
                    $paths = @()
                    if ($eventDetails.Path -is [string]) {
                        $paths = $eventDetails.Path -split ';'
                    } elseif ($eventDetails.Path -is [System.Collections.IEnumerable]) {
                        foreach ($p in $eventDetails.Path) {
                            $paths += ($p -split ';')
                        }
                    }

                    $cleanPaths = @()
                    foreach ($p in $paths) {
                        $pp = $p.Trim()
                        if ($pp) {
                            if ($pp -like 'file:*') {
                                $pp = $pp -replace '^file:_?', ''
                            }
                            $pp = $pp -replace '^\\\\\?\\', ''
                            if ($pp) { $cleanPaths += $pp }
                        }
                    }

                    if ($cleanPaths.Count -gt 0) {
                        foreach ($cp in $cleanPaths) {
                            Write-Host "[*] Report:"
                            Write-Host ("    File: {0}" -f $cp)
                            Write-Host ("    Threat: {0}" -f $baseThreat)
                            if ($threatId) { Write-Host ("    ID: {0}" -f $threatId) }
                            if ($severity) { Write-Host ("    Severity: {0}" -f $severity) }
                            if ($category) { Write-Host ("    Category: {0}" -f $category) }
                            if ($actionText) { Write-Host ("    Action: {0}" -f $actionText) }
                            if ($time) { Write-Host ("    Time: {0}" -f $time) }
                        }

                        return
                    }
                }
            }
        }
    } catch {
        # ignore event parsing errors
    }

    # Fallback: if no Defender event was found, show detections from Get-MpThreatDetection
    if ($detections -and $detections.Count -gt 0) {
        Write-Host ("[*] Antivirus threats detected for {0} in this run:" -f $Label)

        foreach ($d in $detections) {
            $threatName = if ($d.ThreatName) { $d.ThreatName } else { '(unknown threat)' }
            Write-Host ("    - {0} @ {1}" -f $threatName, $d.InitialDetectionTime)

            if ($d.Resources) {
                foreach ($r in $d.Resources) {
                    if ($r -is [string]) {
                        $p = $r
                        if ($p -like 'file:*') {
                            $p = $p -replace '^file:_?', ''
                        }
                        $p = $p -replace '^\\\\\?\\', ''
                        if ($p) {
                            Write-Host ("        -> {0}" -f $p)
                        }
                    }
                }
            }
        }
    }
}

# Build list of installed apps/versions by scanning the apps folder directly
$appsDir = Join-Path $ScoopRoot 'apps'
if (-not (Test-Path $appsDir)) {
    Write-Host "No apps installed (nothing to scan)."
    Write-Host ""
    exit 0
}

$installedEntries = @()

Get-ChildItem -Path $appsDir -Directory | Where-Object { $_.Name -ne 'scoop' } | ForEach-Object {
    $appName = $_.Name
    $currentVersion = $null
    $currentLink = Join-Path $_.FullName 'current'
    if (Test-Path $currentLink) {
        try {
            $target = (Get-Item $currentLink).Target
            if ($target) {
                $currentVersion = Split-Path -Leaf $target
            }
        } catch { }
    }

    $versionDirs = Get-ChildItem -Path $_.FullName -Directory | Where-Object { $_.Name -ne 'current' }
    $versionCount = 0

    foreach ($verDir in $versionDirs) {
        $versionCount++
        $version = $verDir.Name
        $isCurrent = ($version -eq $currentVersion)
        $installedEntries += [pscustomobject]@{
            Name      = $appName
            Version   = $version
            IsCurrent = $isCurrent
            Path      = $verDir.FullName
        }
    }

    # Fallback for apps like 'scoop' that only have a 'current' directory link
    if ($versionCount -eq 0 -and (Test-Path $currentLink)) {
        $installedEntries += [pscustomobject]@{
            Name      = $appName
            Version   = $null
            IsCurrent = $true
            Path      = $currentLink
        }
    }
}

# Load DefenderScan helper (MpCmdRun.exe integration)
$DefenderScanModule = Join-Path $ProjectRoot 'modules\DefenderScan.psm1'
$avAvailable = $false
if (Test-Path $DefenderScanModule) {
    try {
        Import-Module $DefenderScanModule -Force
        if (Get-Command Invoke-DefenderScanFolder -ErrorAction SilentlyContinue) {
            $avAvailable = $true
        }
    } catch {
        Write-Warning "Failed to load DefenderScan module; Antivirus checks will be skipped. $($_.Exception.Message)"
        Write-Host ""
        $avAvailable = $false
    }
}

$results = @()

# Cache per-app persist scans so we only scan each persist\<app>
# folder once, even if multiple versions are installed.
$persistScanCache = @{}  # appName -> scan object

# Optional dedicated Antivirus-only scan for Scoop manager (no VirusTotal for scoop itself)
$scoopCurrentPath = Join-Path $appsDir 'scoop\current'
if (Test-Path $scoopCurrentPath) {
    Write-SubsectionHeader -Title 'Scanning: Scoop'

    if ($avAvailable) {
        # Detect-only scan (no remediation); user can review and clean manually.
        $scoopScan = Invoke-DefenderScanFolder -Path $scoopCurrentPath -DisableRemediation
        $scoopAvStatus = $scoopScan.AvStatus
        Write-AvSummaryForLabel -Label 'scoop' -Scan $scoopScan
        if ($scoopScan.AvStatus -in @('ThreatRemediated', 'ThreatDetected')) {
            Write-DefenderThreatHistoryForPath -Label 'scoop' -Path $scoopCurrentPath
        }
        if ($scoopScan.AvStatus -eq 'ThreatRemediated') {
            Write-Warning ("Antivirus (Windows Defender) scan: Threats detected and remediated (ExitCode={0})" -f $scoopScan.ExitCode)
        } elseif ($scoopScan.AvStatus -eq 'ThreatDetected') {
            Write-Warning ("Antivirus (Windows Defender) scan: Threats detected (ExitCode={0})" -f $scoopScan.ExitCode)
        } elseif ($scoopScan.AvStatus -eq 'ThreatOrError') {
            Write-Warning ("Antivirus (Windows Defender) scan: Threat or error reported (ExitCode={0}); please review Windows Security." -f $scoopScan.ExitCode)
        } elseif ($scoopScan.AvStatus -eq 'Error') {
            Write-Warning ("Antivirus (Windows Defender) scan: Error during scan (ExitCode={0})." -f $scoopScan.ExitCode)
        }
    } else {
        $scoopAvStatus = 'NotAvailable'
        Write-Host "[*] Antivirus for scoop: NotAvailable (DefenderScan module not loaded or MpCmdRun.exe not found)"
        Write-Host ""
    }

    $results += [pscustomobject]@{
        AppName      = 'scoop'
        Version      = $null
        AppSpec      = 'scoop'
        Detections   = $null
        TotalEngines = $null
        HasReport    = $false
        Url          = $null
        ExitCode     = $null
        Status       = 'Skipped'  # VirusTotal not run for scoop (no manifest/hash available).
        Message      = 'VirusTotal not run for scoop (no manifest/hash available).'
        AvStatus     = $scoopAvStatus
    }

    Write-Host ""
}

if (-not $installedEntries -or $installedEntries.Count -eq 0) {
    Write-Host "No apps installed (nothing to scan)."
    Write-Host ""
    exit 0
}

# Group installed entries by app name so we can show
# a dedicated "Scanning: <app>" block for each.
$entriesByApp = $installedEntries | Sort-Object Name, Version | Group-Object Name

foreach ($appGroup in $entriesByApp) {
    $appName = $appGroup.Name

    Write-SubsectionHeader -Title ("Scanning: {0}" -f $appName)

    # First, scan the shared persist folder for this app (once per app)
    if ($avAvailable) {
        $persistPath = Join-Path $ScoopRoot "persist\$appName"
        if ((Test-Path $persistPath -PathType Container) -and -not $persistScanCache.ContainsKey($appName)) {
            # Detect-only scan (no remediation); user can review and clean manually.
            $persistScan = Invoke-DefenderScanFolder -Path $persistPath -DisableRemediation
            $persistScanCache[$appName] = $persistScan

            Write-AvSummaryForLabel -Label "$appName (persist)" -Scan $persistScan
            if ($persistScan.AvStatus -in @('ThreatRemediated', 'ThreatDetected')) {
                Write-DefenderThreatHistoryForPath -Label "$appName (persist)" -Path $persistPath
            }
            if ($persistScan.AvStatus -eq 'ThreatRemediated') {
                Write-Warning ("Antivirus (Windows Defender) scan: Threats detected and remediated (ExitCode={0})" -f $persistScan.ExitCode)
            } elseif ($persistScan.AvStatus -eq 'ThreatDetected') {
                Write-Warning ("Antivirus (Windows Defender) scan: Threats detected (ExitCode={0})" -f $persistScan.ExitCode)
            } elseif ($persistScan.AvStatus -eq 'ThreatOrError') {
                Write-Warning ("Antivirus (Windows Defender) scan: Threat or error reported (ExitCode={0}); please review Windows Security." -f $persistScan.ExitCode)
            } elseif ($persistScan.AvStatus -eq 'Error') {
                Write-Warning ("Antivirus (Windows Defender) scan: Error during scan (ExitCode={0})." -f $persistScan.ExitCode)
            }

            Write-Host ""
        }
    }

    foreach ($entry in $appGroup.Group) {
        $version = $entry.Version
        $label = if ($version) { "$appName@$version" } else { $appName }

        # Prefer version-specific manifest.json if available (deep check)
        $manifestPath = $null
        if ($version -and $entry.Path) {
            $candidate = Join-Path $entry.Path 'manifest.json'
            if (Test-Path $candidate) {
                $manifestPath = $candidate
            }
        }

        $appSpec = if ($manifestPath) { $manifestPath } else { $label }
        $vtResult = $null

        if ($vtSettings) {
            # Delegate all configuration and API-key gating to the VirusTotalScan module.
            $vtResult = Invoke-VirusTotalCheckForApp -AppName $label -AppSpec $appSpec -ScoopShim $ScoopShim -Settings $vtSettings -Mode 'Audit'
        } else {
            # VirusTotal integration not available (module or settings failed to initialize).
            $vtResult = [pscustomobject]@{
                AppName      = $label
                Detections   = $null
                TotalEngines = $null
                HasReport    = $false
                Url          = $null
                ExitCode     = $null
                Status       = 'Skipped'
                Message      = 'VirusTotal integration not available.'
            }
        }

        # Optional Antivirus scan using Windows Defender (per version folder)
        $avStatus = 'NotAvailable'
        if ($avAvailable) {
            $appPath = if ($entry.Path) { $entry.Path } else { Join-Path $ScoopRoot "apps\$appName\$version" }
            if (Test-Path $appPath) {
                # Detect-only scan (no remediation); user can review and clean manually.
                $scan = Invoke-DefenderScanFolder -Path $appPath -DisableRemediation
                $avStatus = $scan.AvStatus
                Write-AvSummaryForLabel -Label $label -Scan $scan
                if ($scan.AvStatus -in @('ThreatRemediated', 'ThreatDetected')) {
                    Write-DefenderThreatHistoryForPath -Label $label -Path $appPath
                }
                if ($scan.AvStatus -eq 'ThreatRemediated') {
                    Write-Warning ("Antivirus (Windows Defender) scan: Threats detected and remediated (ExitCode={0})" -f $scan.ExitCode)
                } elseif ($scan.AvStatus -eq 'ThreatDetected') {
                    Write-Warning ("Antivirus (Windows Defender) scan: Threats detected (ExitCode={0})" -f $scan.ExitCode)
                } elseif ($scan.AvStatus -eq 'ThreatOrError') {
                    Write-Warning ("Antivirus (Windows Defender) scan: Threat or error reported (ExitCode={0}); please review Windows Security." -f $scan.ExitCode)
                } elseif ($scan.AvStatus -eq 'Error') {
                    Write-Warning ("Antivirus (Windows Defender) scan: Error during scan (ExitCode={0})." -f $scan.ExitCode)
                }
            } else {
                $avStatus = 'Skipped'
                Write-Host ("[*] Antivirus (Windows Defender) scan: Skipped (folder not found: {0})" -f $appPath)
                Write-Host ""
            }
        }

        $results += [pscustomobject]@{
            AppName      = $appName
            Version      = $version
            AppSpec      = $label
            Detections   = $vtResult.Detections
            TotalEngines = $vtResult.TotalEngines
            HasReport    = $vtResult.HasReport
            Url          = $vtResult.Url
            ExitCode     = $vtResult.ExitCode
            Status       = $vtResult.Status
            Message      = $vtResult.Message
            AvStatus     = $avStatus
        }

        # Visual separation between versions in the log
        Write-Host ""
        Write-Host ""
    }
}

Write-SubsectionHeader -Title 'Summary'

Write-Host ("{0,-24}{1,-12}{2,-12}" -f "App", "VirusTotal", "Antivirus")
Write-Host ("{0,-24}{1,-12}{2,-12}" -f "---", "--", "--")

$cleanCount = 0
$riskyCount = 0
$errorCount = 0
$skippedCount = 0

$sortedResults = $results | Sort-Object `
    @{ Expression = { if ($_.Detections -ne $null) { -1 * [int]$_.Detections } else { [int]::MinValue } } }, `
    @{ Expression = { $_.Status } }, `
    @{ Expression = { $_.AppSpec } }

foreach ($r in $sortedResults) {
    $label = if ($r.Version) { "$($r.AppName)@$($r.Version)" } else { $r.AppName }
    $resultCol = if ($r.Detections -ne $null -and $r.TotalEngines -ne $null) { "$($r.Detections)/$($r.TotalEngines)" } else { "-" }
    $avCol = switch ($r.AvStatus) {
        'CleanOrRemediated' { 'Clean' }
        'ThreatRemediated'  { 'Threat+cleaned' }
        'ThreatDetected'    { 'Threat' }
        'ThreatOrError'     { 'Thr/Error' }
        'NotAvailable'      { 'N/A' }
        default             { if ($r.AvStatus) { $r.AvStatus } else { '-' } }
    }

    switch ($r.Status) {
        'Clean'   { $cleanCount++ }
        'Risky'   { $riskyCount++ }
        'Error'   { $errorCount++ }
        'Skipped' { $skippedCount++ }
    }

    Write-Host ("{0,-24}{1,-12}{2,-12}" -f $label, $resultCol, $avCol)
}

Write-Host ""

# Compute statistics excluding scoop (manager) entry
$statsResults = $results | Where-Object { $_.AppName -ne 'scoop' }
$cleanCount = 0
$riskyCount = 0
$errorCount = 0
$skippedCount = 0

foreach ($r in $statsResults) {
    switch ($r.Status) {
        'Clean'   { $cleanCount++ }
        'Risky'   { $riskyCount++ }
        'Error'   { $errorCount++ }
        'Skipped' { $skippedCount++ }
    }
}

Write-Host "[*] Apps scanned: $($statsResults.Count)"
Write-Host "[OK] Clean: $cleanCount"
Write-Host "[!] Risky: $riskyCount"
Write-Host "[!] Errors: $errorCount"
Write-Host "[*] Skipped: $skippedCount"
Write-Host ""

exit 0
