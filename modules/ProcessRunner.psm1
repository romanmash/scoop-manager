<#
.SYNOPSIS
Shared helper for running external processes with consistent logging.

.DESCRIPTION
Runs an external process via `cmd.exe` and appends *all* stdout/stderr output into a single
stable file: `.tmp\process\process.log`.

The menu resets `process.log` once per script run. This module then appends per command and
optionally streams new output to the console so transcript/log output stays consistent and
PowerShell `NativeCommandError` records are avoided.
#>

function Invoke-ExternalCommandLogged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @(),

        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = $null,

        # If $true, stream output while the process runs (best-effort progress).
        [Parameter(Mandatory = $false)]
        [bool]$Stream = $true,

        # If set, do not write to the host (still captures into process.log and returns text).
        [Parameter(Mandatory = $false)]
        [switch]$NoHostOutput = $false
    )

    function Get-ProcessRunnerReadEncoding {
        try { return [Console]::OutputEncoding } catch { return [System.Text.Encoding]::Default }
    }

    function Ensure-ProcessLogFile {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            try { New-Item -ItemType Directory -Path $dir -Force | Out-Null } catch { }
        }

        if (-not (Test-Path -LiteralPath $Path)) {
            try {
                if (Get-Command Write-TextFileUtf8NoBom -ErrorAction SilentlyContinue) {
                    Write-TextFileUtf8NoBom -Path $Path -Content ''
                } else {
                    $enc = New-Object System.Text.UTF8Encoding $false
                    [System.IO.File]::WriteAllText($Path, '', $enc)
                }
            } catch {
                try { [System.IO.File]::WriteAllText($Path, '') } catch { }
            }
        }
    }

    function Quote-CmdArgument {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Argument
        )

        if ($Argument.Length -eq 0) {
            return '""'
        }

        if ($Argument -notmatch '[\s"]') {
            return $Argument
        }

        $escaped = $Argument.Replace('"', '""')
        return '"' + $escaped + '"'
    }

    function Read-NewText {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter(Mandatory = $true)]
            [ref]$Offset,

            [Parameter(Mandatory = $true)]
            [System.Text.Encoding]$Encoding
        )

        if (-not (Test-Path -LiteralPath $Path)) {
            return ''
        }

        $fs = $null
        try {
            $fs = New-Object System.IO.FileStream(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )

            if ($Offset.Value -gt $fs.Length) {
                $Offset.Value = $fs.Length
            }

            $fs.Seek($Offset.Value, [System.IO.SeekOrigin]::Begin) | Out-Null
            $remaining = $fs.Length - $Offset.Value
            if ($remaining -le 0) {
                return ''
            }

            $buf = New-Object byte[] $remaining
            $read = $fs.Read($buf, 0, $buf.Length)
            $Offset.Value = $Offset.Value + $read

            if ($read -le 0) { return '' }
            return $Encoding.GetString($buf, 0, $read)
        } catch {
            return ''
        } finally {
            if ($fs) { try { $fs.Dispose() } catch { } }
        }
    }

    function Emit-ChunkLines {
        param(
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Chunk = '',

            [Parameter(Mandatory = $true)]
            [ref]$Buffer,

            # Use [ref] to keep this robust across language modes / type restrictions.
            [Parameter(Mandatory = $true)]
            [ref]$CapturedLines,

            # Skip known ConstrainedLanguage noise blocks coming from child PowerShell processes.
            # State machine: 'none' -> 'clm' -> 'clm_after_id' -> 'none'
            [Parameter(Mandatory = $true)]
            [ref]$SkipState,

            [Parameter(Mandatory = $true)]
            [ref]$SkipCount,

            [Parameter(Mandatory = $true)]
            [bool]$WriteToHost
        )

        if ([string]::IsNullOrEmpty($Chunk)) { return }
        $Buffer.Value = [string]$Buffer.Value + $Chunk

        $parts = $Buffer.Value -split "`r?`n", -1
        if ($parts.Count -le 1) {
            return
        }

        $endsWithNewline = ($Buffer.Value -match "(`r?`n)$")
        $completeCount = $parts.Count - 1
        $remaining = if ($endsWithNewline) { '' } else { $parts[-1] }

        for ($i = 0; $i -lt $completeCount; $i++) {
            $line = $parts[$i]

            # Filter out this known noisy error record (keeps console == transcript/log clean):
            # "Cannot set property... PropertySetterNotSupportedInConstrainedLanguage" from child PowerShell.
            if ($SkipState.Value -eq 'none') {
                if ($line -like 'Cannot set property. Property setting is supported only on core types in this language mode.*') {
                    $SkipState.Value = 'clm'
                    $SkipCount.Value = 0
                    continue
                }
            } elseif ($SkipState.Value -eq 'clm') {
                $SkipCount.Value++
                if ($line -match '^\s*FullyQualifiedErrorId\s*:\s*PropertySetterNotSupportedInConstrainedLanguage\s*$') {
                    $SkipState.Value = 'clm_after_id'
                }
                if ($SkipCount.Value -gt 40) { $SkipState.Value = 'none' }
                continue
            } elseif ($SkipState.Value -eq 'clm_after_id') {
                $SkipCount.Value++
                if ([string]::IsNullOrWhiteSpace($line)) {
                    $SkipState.Value = 'none'
                } elseif ($SkipCount.Value -gt 40) {
                    $SkipState.Value = 'none'
                }
                continue
            }

            $CapturedLines.Value += $line
            if ($WriteToHost -and -not $NoHostOutput) {
                Write-Host $line
            }
        }

        $Buffer.Value = $remaining
    }

    function Emit-RemainingBuffer {
        param(
            [Parameter(Mandatory = $true)]
            [ref]$Buffer,

            [Parameter(Mandatory = $true)]
            [ref]$CapturedLines,

            [Parameter(Mandatory = $true)]
            [ref]$SkipState,

            [Parameter(Mandatory = $true)]
            [ref]$SkipCount,

            [Parameter(Mandatory = $true)]
            [bool]$WriteToHost
        )

        if ([string]::IsNullOrEmpty($Buffer.Value)) { return }
        $line = [string]$Buffer.Value

        if ($SkipState.Value -ne 'none') {
            $SkipCount.Value++
            if ($SkipState.Value -eq 'clm_after_id' -and [string]::IsNullOrWhiteSpace($line)) {
                $SkipState.Value = 'none'
            } elseif ($line -match '^\s*FullyQualifiedErrorId\s*:\s*PropertySetterNotSupportedInConstrainedLanguage\s*$') {
                $SkipState.Value = 'clm_after_id'
            } elseif ($SkipCount.Value -gt 40) {
                $SkipState.Value = 'none'
            }

            if ($SkipState.Value -ne 'none') {
                $Buffer.Value = ''
                return
            }
        } elseif ($line -like 'Cannot set property. Property setting is supported only on core types in this language mode.*') {
            $SkipState.Value = 'clm'
            $SkipCount.Value = 0
            $Buffer.Value = ''
            return
        }

        $CapturedLines.Value += $line
        if ($WriteToHost -and -not $NoHostOutput) {
            Write-Host $line
        }
        $Buffer.Value = ''
    }

    $processDir = Join-Path $ProjectRoot '.tmp\process'
    try { New-Item -ItemType Directory -Path $processDir -Force | Out-Null } catch { }

    $combinedLogPath = Join-Path $processDir 'process.log'
    Ensure-ProcessLogFile -Path $combinedLogPath

    $readEncoding = Get-ProcessRunnerReadEncoding
    $capturedLines = @()
    $exitCode = 1
    $skipState = 'none'
    $skipCount = 0

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $argsDisplay = ''
    if ($ArgumentList -and $ArgumentList.Count -gt 0) {
        $argsDisplay = ($ArgumentList | ForEach-Object { [string]$_ }) -join ' '
    }

    $comspec = $env:ComSpec
    if (-not $comspec) { $comspec = 'cmd.exe' }

    $cmdParts = @()
    $cmdParts += (Quote-CmdArgument -Argument $FilePath)
    foreach ($a in $ArgumentList) {
        $cmdParts += (Quote-CmdArgument -Argument ([string]$a))
    }
    $cmdLine = ($cmdParts -join ' ')

    $logRedir = Quote-CmdArgument -Argument $combinedLogPath
    $cmdScript = "$cmdLine 1>>$logRedir 2>>&1"
    $cmdArgs = '/d /s /c "' + $cmdScript + '"'

    # Write a small header (ASCII-safe) that does not affect returned Output.
    try {
        $header = "`r`n----- $timestamp -----`r`n$FilePath $argsDisplay`r`n[cmd] $comspec $cmdArgs`r`n`r`n"
        [System.IO.File]::AppendAllText($combinedLogPath, $header, [System.Text.Encoding]::ASCII)
    } catch { }

    $offset = 0L
    try { $offset = (Get-Item -LiteralPath $combinedLogPath -ErrorAction SilentlyContinue).Length } catch { $offset = 0L }

    $buffer = ''
    $writeToHost = $Stream -or (-not $NoHostOutput)

    $proc = $null
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.FileName = $comspec
        $startInfo.Arguments = $cmdArgs
        if ($WorkingDirectory) {
            $startInfo.WorkingDirectory = $WorkingDirectory
        }

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $startInfo
        if (-not $proc.Start()) {
            throw "Failed to start process: $FilePath"
        }

        if ($Stream) {
            while (-not $proc.HasExited) {
                $chunk = Read-NewText -Path $combinedLogPath -Offset ([ref]$offset) -Encoding $readEncoding
                Emit-ChunkLines -Chunk $chunk -Buffer ([ref]$buffer) -CapturedLines ([ref]$capturedLines) -SkipState ([ref]$skipState) -SkipCount ([ref]$skipCount) -WriteToHost $true
                Start-Sleep -Milliseconds 250
            }
        }

        $proc.WaitForExit()
        $exitCode = $proc.ExitCode

        $chunk = Read-NewText -Path $combinedLogPath -Offset ([ref]$offset) -Encoding $readEncoding
        Emit-ChunkLines -Chunk $chunk -Buffer ([ref]$buffer) -CapturedLines ([ref]$capturedLines) -SkipState ([ref]$skipState) -SkipCount ([ref]$skipCount) -WriteToHost $writeToHost
        Emit-RemainingBuffer -Buffer ([ref]$buffer) -CapturedLines ([ref]$capturedLines) -SkipState ([ref]$skipState) -SkipCount ([ref]$skipCount) -WriteToHost $writeToHost
    } catch {
        $exitCode = 1
        $msg = $_.Exception.Message
        try {
            [System.IO.File]::AppendAllText($combinedLogPath, ($msg + "`r`n"), [System.Text.Encoding]::ASCII)
        } catch { }
        if (-not $NoHostOutput) {
            Write-Host $msg
        }
    } finally {
        if ($proc) { try { $proc.Dispose() } catch { } }
    }

    $combinedText = ($capturedLines -join "`r`n")

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $combinedText
        LogPath  = $combinedLogPath
    }
}

function Assert-ExternalCommandRunner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Caller
    )

    if (-not (Get-Command Invoke-ExternalCommandLogged -ErrorAction SilentlyContinue)) {
        throw "${Caller}: external command runner is not available (import modules/ProcessRunner.psm1; Manage-ScoopMenu.ps1 does this automatically)."
    }
}

Export-ModuleMember -Function @(
    'Invoke-ExternalCommandLogged',
    'Assert-ExternalCommandRunner'
)
