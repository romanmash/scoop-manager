<#
.SYNOPSIS
Helper functions for integrating Microsoft Defender (MpCmdRun.exe).

.DESCRIPTION
Provides a folder-level scan helper that runs MpCmdRun.exe synchronously,
captures its output and exit code, and correlates new detections (if any)
from Get-MpThreatDetection to the scanned path.

Used by script 28_Scan-InstalledApps.ps1 to optionally add local Antivirus
signal alongside VirusTotal checks, including per-threat names and paths.
#>

function Get-MpCmdRunPath {
    [CmdletBinding()]
    param()

    # Preferred location: ProgramData\Microsoft\Windows Defender\Platform\<version>\MpCmdRun.exe
    $programData = $env:ProgramData
    if ($programData) {
        $platformRoot = Join-Path $programData 'Microsoft\Windows Defender\Platform'
        if (Test-Path $platformRoot) {
            $candidates = Get-ChildItem -Path $platformRoot -Directory -ErrorAction SilentlyContinue |
                          Sort-Object Name -Descending
            foreach ($dir in $candidates) {
                $mpPath = Join-Path $dir.FullName 'MpCmdRun.exe'
                if (Test-Path $mpPath) {
                    return $mpPath
                }
            }
        }
    }

    # Fallback: Program Files\Windows Defender\MpCmdRun.exe
    $programFiles = $env:ProgramFiles
    if ($programFiles) {
        $fallback = Join-Path $programFiles 'Windows Defender\MpCmdRun.exe'
        if (Test-Path $fallback) {
            return $fallback
        }
    }

    return $null
}

function Get-DefenderThreatsForPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [datetime]$Since
    )

    $resolved = $null
    try {
        $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        return @()
    }

    $pattern = "*$resolved*"

    $detections = @()
    $threatCmd = Get-Command -Name Get-MpThreatDetection -ErrorAction SilentlyContinue
    if ($threatCmd) {
        try {
            $detections = Get-MpThreatDetection -ErrorAction SilentlyContinue
        } catch {
            $detections = @()
        }
    } else {
        try {
            $detections = Get-CimInstance -Namespace 'root/Microsoft/Windows/Defender' `
                                          -ClassName 'MSFT_MpThreatDetection' `
                                          -ErrorAction SilentlyContinue
        } catch {
            $detections = @()
        }
    }

    if (-not $detections) { return @() }

    $allDetections = $detections

    if ($Since) {
        $detections = $allDetections |
            Where-Object { $_.InitialDetectionTime -ge $Since }
    }

    $detections = $detections |
        Where-Object { ($_.Resources -join ';') -like $pattern }

    $result = @()
    foreach ($d in $detections) {
        $paths = @()
        if ($d.Resources) {
            foreach ($r in $d.Resources) {
                if ($r -is [string]) {
                    $p = $r
                    if ($p -like 'file:*') {
                        $p = $p -replace '^file:_?', ''
                    }
                    $p = $p -replace '^\\\\\?\\', ''
                    if ($p) {
                        $paths += $p
                    }
                }
            }
        }

        $result += [pscustomobject]@{
            ThreatName    = $d.ThreatName
            DetectionTime = $d.InitialDetectionTime
            Paths         = $paths
            DetectionID   = $d.DetectionID
            ThreatID      = $d.ThreatID
        }
    }

    return $result
}

function Get-DefenderThreatEventForPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [datetime]$Since
    )

    $resolved = $null
    try {
        $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        return $null
    }

    $pattern = "*$resolved*"

    try {
        $filter = @{
            LogName = 'Microsoft-Windows-Windows Defender/Operational'
            Id      = 1117
        }
        $evt = Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -like $pattern } |
            Sort-Object TimeCreated -Descending |
            Select-Object -First 1
    } catch {
        $evt = $null
    }

    if (-not $evt) {
        return $null
    }

    # If the caller provides a lower bound (e.g. script start time),
    # only consider events from this run to avoid showing stale
    # detections from previous scans.
    if ($Since -and ($evt.TimeCreated -lt $Since)) {
        return $null
    }

    $lines = $evt.Message -split "`r?`n"
    $kv = [ordered]@{}

    foreach ($line in $lines) {
        if ($line -match '^\s*(?<key>[^:]+):\s*(?<value>.*)$') {
            $key   = $matches['key'].Trim()
            $value = $matches['value'].Trim()
            if ($key -and $value) {
                if ($kv.Contains($key)) {
                    if ($kv[$key] -is [System.Collections.IList]) {
                        $kv[$key] += $value
                    } else {
                        $kv[$key] = @($kv[$key], $value)
                    }
                } else {
                    $kv[$key] = $value
                }
            }
        }
    }

    $kv['EventId']      = $evt.Id
    $kv['TimeCreated']  = $evt.TimeCreated
    $kv['ProviderName'] = $evt.ProviderName

    return [pscustomobject]$kv
}

function Invoke-DefenderScanFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$DisableRemediation
    )

    $resultPath = $null
    try {
        $resultPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        return [pscustomobject]@{
            Path         = $Path
            AvAvailable  = $false
            AvStatus     = 'NotAvailable'
            ExitCode     = $null
            Threats      = @()
            RawOutput    = @()
            Notes        = "Scan path does not exist or could not be resolved."
        }
    }

    $mpCmd = Get-MpCmdRunPath
    if (-not $mpCmd) {
        return [pscustomobject]@{
            Path          = $resultPath
            AvAvailable   = $false
            AvStatus      = 'NotAvailable'
            ExitCode      = $null
            Threats       = @()
            ThreatDetails = @()
            RawOutput     = @()
            Notes         = "MpCmdRun.exe not found - Defender antivirus CLI unavailable."
        }
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # 1) Remember when this scan started
    $scanStart = Get-Date

    # 2) Build arguments and run MpCmdRun.exe synchronously
    $argString = "-Scan -ScanType 3 -File `"$resultPath`""
    if ($DisableRemediation) {
        $argString += " -DisableRemediation"
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $mpCmd
    $psi.Arguments = $argString
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    [void]$proc.Start()
    $stdOut = $proc.StandardOutput.ReadToEnd()
    $stdErr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $exitCode = $proc.ExitCode

    $rawOutput = @()
    if ($stdOut) { $rawOutput += $stdOut.TrimEnd("`r","`n") }
    if ($stdErr) { $rawOutput += $stdErr.TrimEnd("`r","`n") }

    # 3) Query Defender for threats for this path since scanStart
    $threatDetails = Get-DefenderThreatsForPath -Path $resultPath -Since $scanStart

    $threatNames = @()
    if ($threatDetails) {
        $threatNames = $threatDetails |
                       Select-Object -ExpandProperty ThreatName -Unique -ErrorAction SilentlyContinue
    }

    # 4) Classify antivirus status
    $status =
        if ($exitCode -eq 0 -and $threatDetails) { 'ThreatRemediated' }
        elseif ($exitCode -eq 0)                 { 'CleanOrRemediated' }
        elseif ($exitCode -eq 2 -and ($threatDetails -or $DisableRemediation)) { 'ThreatDetected' }
        elseif ($exitCode -eq 2)                 { 'ThreatOrError' }
        else                                     { 'Error' }

    $notes = "MpCmdRun.exe scan completed. ExitCode=$exitCode."

    [pscustomobject]@{
        Path          = $resultPath
        AvAvailable   = $true
        AvStatus      = $status
        ExitCode      = $exitCode
        Threats       = $threatNames
        ThreatDetails = $threatDetails
        RawOutput     = $rawOutput
        Notes         = $notes
    }
}

Export-ModuleMember -Function @(
    'Get-MpCmdRunPath',
    'Get-DefenderThreatsForPath',
    'Get-DefenderThreatEventForPath',
    'Invoke-DefenderScanFolder'
)
