<#
.SYNOPSIS
Sectioned, two-digit input manager. Displays only x0 scripts as section entries.
Accepts immediate two-digit input without Enter to execute any script directly.
#>

$ErrorActionPreference = 'Stop'

# Maximize console window height and position at top-left
try {
    if ($host.Name -eq 'ConsoleHost') {
        $host.UI.RawUI.WindowTitle = "Scoop Manager"
        $maxHeight = $host.UI.RawUI.MaxPhysicalWindowSize.Height
        $maxWidth = $host.UI.RawUI.MaxPhysicalWindowSize.Width
        
        # Use Windows API to position window at top-left
        try {
            Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class Win32 {
            [DllImport("user32.dll")]
            public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
            [DllImport("kernel32.dll")]
            public static extern IntPtr GetConsoleWindow();
            public static readonly IntPtr HWND_TOP = new IntPtr(0);
            public const uint SWP_NOSIZE = 0x0001;
            public const uint SWP_NOMOVE = 0x0002;
            public const uint SWP_SHOWWINDOW = 0x0040;
        }
"@ -ErrorAction SilentlyContinue
        } catch {
            # Type might already be defined, continue
        }
        
        $consoleHandle = $null
        try {
            $consoleHandle = [Win32]::GetConsoleWindow()
            if ($consoleHandle -ne [IntPtr]::Zero) {
                # Position at top-left (0, 0)
                [Win32]::SetWindowPos($consoleHandle, [Win32]::HWND_TOP, 0, 0, 0, 0, [Win32]::SWP_NOSIZE -bor [Win32]::SWP_SHOWWINDOW) | Out-Null
            }
        } catch {
            # Win32 API not available, continue with PowerShell methods
        }
        
        # Set buffer to allow full height scrolling
        $currentBuffer = $host.UI.RawUI.BufferSize
        if ($currentBuffer.Height -lt $maxHeight) {
            $host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size($maxWidth, $maxHeight)
        }
        
        # Set window to full height (keep current width)
        $window = $host.UI.RawUI.WindowSize
        $host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($window.Width, $maxHeight)
        
        # Re-position after resize using Windows API
        Start-Sleep -Milliseconds 100
        try {
            if ($null -ne $consoleHandle -and $consoleHandle -ne [IntPtr]::Zero) {
                [Win32]::SetWindowPos($consoleHandle, [Win32]::HWND_TOP, 0, 0, 0, 0, [Win32]::SWP_NOSIZE -bor [Win32]::SWP_SHOWWINDOW) | Out-Null
            }
        } catch {
            # Win32 API not available, try PowerShell method as fallback
            try {
                $host.UI.RawUI.WindowPosition = New-Object System.Management.Automation.Host.Coordinates(0, 0)
            } catch { }
        }
    }
} catch {
    # Silently fail if console resize is not supported
}

# Resolve paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Load shared helper modules into the menu session.
# This ensures scripts run from the menu can rely on these exported functions consistently.
try { Import-Module (Join-Path $ProjectRoot 'modules\TextFile.psm1') -Force | Out-Null } catch { }
try { Import-Module (Join-Path $ProjectRoot 'modules\ConsoleUi.psm1') -Force | Out-Null } catch { }
try { Import-Module (Join-Path $ProjectRoot 'modules\ProcessRunner.psm1') -Force | Out-Null } catch { }

# Set custom console icon (best-effort, ignore failures)
try {
    Import-Module (Join-Path $ProjectRoot 'modules\ScriptBootstrap.psm1') -Force
    Set-ConsoleWindowIcon -IconPath (Join-Path $ProjectRoot 'docs\assets\logo.ico')
} catch {
    # Non-fatal: continue without changing icon
}

# Load manager config module
$LoggingConfigPath = Join-Path $ProjectRoot 'modules\LoggingConfig.psm1'
if (Test-Path $LoggingConfigPath) {
    Import-Module $LoggingConfigPath -Force
}

$script:ScoopManagerVersionLabel = $null
try {
    Import-Module (Join-Path $ProjectRoot 'modules\ManagerConfig.psm1') -Force
    $script:ScoopManagerVersionLabel = Get-ManagerVersionLabel -ProjectRoot $ProjectRoot
} catch { }

function Get-Scripts {
    Get-ChildItem -Path $ScriptDir -Filter '*.ps1' -File |
        Where-Object { $_.Name -notlike 'Manage-ScoopMenu.ps1' } |
        Sort-Object Name
}

function Get-SectionTitle([string]$series, [array]$seriesScripts) {
    # Try to find the x0@ section script and get its .SYNOPSIS
    $sectionScript = $seriesScripts | Where-Object { 
        $_.Code -eq ("{0}0" -f $series.Substring(0,1)) -and $_.File.BaseName -like "*@*"
    } | Select-Object -First 1
    
    if ($sectionScript) {
        # Get the .SYNOPSIS from the script and convert to uppercase
        $synopsis = Get-Purpose $sectionScript.File.FullName
        if ($synopsis) {
            # Remove " section" suffix and convert to uppercase
            $title = $synopsis -replace '\s+section$', ''
            return $title.ToUpper()
        }
        
        # Fallback: extract from filename if no .SYNOPSIS (handles title case like "Docs")
        $name = $sectionScript.File.BaseName -replace '^\d{2}@', ''
        return $name.ToUpper()
    }
    
    # Fallback
    return "SECTION $series"
}

function Read-TwoDigits {
    Write-Host -NoNewline 'Enter two digits (or "x" to exit): '
    $first = [Console]::ReadKey($true)
    if ($first.KeyChar -in 'x','X') { return 'x' }
    if ($first.KeyChar -notmatch '[0-9]') { return '' }
    Write-Host -NoNewline $first.KeyChar
    $second = [Console]::ReadKey($true)
    if ($second.KeyChar -notmatch '[0-9]') { return '' }
    Write-Host $second.KeyChar
    return ($first.KeyChar.ToString() + $second.KeyChar.ToString())
}

function Get-Purpose([string]$filePath) {
    # Try new comment-based help format first
    $content = Get-Content -Path $filePath -Raw -ErrorAction SilentlyContinue
    if ($content) {
        # Pattern handles optional blank lines between .SYNOPSIS and next section
        # Matches text after .SYNOPSIS until next .KEYWORD or #>
        if ($content -match '(?s)<#.*?\.SYNOPSIS\s+([^\r\n]+(?:\r?\n[^\r\n\.#]+)*?)(?:\r?\n\s*\.|\r?\n\s*#>)') {
            return $Matches[1].Trim()
        }
        # Fallback: simpler pattern for single-line SYNOPSIS
        if ($content -match '(?s)\.SYNOPSIS\s+([^\r\n]+)') {
            return $Matches[1].Trim()
        }
    }
    # Fallback to old format
    $line = Get-Content -Path $filePath -TotalCount 10 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*#\s*Purpose\s*:\s*(.+)$' } | Select-Object -First 1
    if ($line) {
        return ($line -replace '^\s*#\s*Purpose\s*:\s*','').Trim()
    }
    return ''
}

function Get-ScriptLabel([string]$baseName) {
    # Extract label from script base name (removes XX_ or XX@ prefix)
    # Handles both Verb-Noun format (01_Show-ProjectDoc) and section format (00@Docs)
    $label = $baseName.Substring(3)
    
    # Replace @ with space (for section scripts, though they're excluded from menu)
    $label = $label -replace '@', ' '
    
    # Replace - with space (for Verb-Noun format)
    $label = $label -replace '-', ' '
    
    # Split PascalCase words (e.g., "InstalledApps" -> "Installed Apps")
    # Insert space before capital letters that follow lowercase letters or other capitals
    $label = $label -creplace '([a-z])([A-Z])', '$1 $2'
    $label = $label -creplace '([A-Z]+)([A-Z][a-z])', '$1 $2'
    
    # Convert to lowercase for display
    return $label.ToLower()
}

function Get-Commands([string]$filePath) {
    $cmds = @()
    $content = Get-Content -Path $filePath -Raw -ErrorAction SilentlyContinue
    if ($content) {
        # Try new comment-based help format first
        if ($content -match '(?s)\.CMD\s+(.+?)(?:\r?\n\.|#>)') {
            $cmdSection = $Matches[1].Trim()
            $cmdLines = $cmdSection -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
            foreach ($line in $cmdLines) {
                $cmd = $line.Trim()
                if ($cmd -and $cmd -notmatch '^\.') { $cmds += $cmd }
            }
            if ($cmds.Count -gt 0) { return $cmds }
        }
    }
    # Fallback to old format
    $lines = Get-Content -Path $filePath -TotalCount 15 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*#\s*Cmd\s*:\s*(.+)$' }
    foreach ($line in $lines) {
        $cmd = ($line -replace '^\s*#\s*Cmd\s*:\s*','').Trim()
        if ($cmd) { $cmds += $cmd }
    }
    return $cmds
}

function Show-Menu {
    Clear-Host

    $scripts = Get-Scripts
    $bySeries = @{}
    foreach ($s in $scripts) {
        if ($s.BaseName -match '^(\d{2})') {
            $code = $Matches[1]
            $series = "{0}0" -f ($code.Substring(0,1))
            if (-not $bySeries.ContainsKey($series)) { $bySeries[$series] = @() }
            $bySeries[$series] += [pscustomobject]@{
                Code = $code
                File = $s
            }
        }
    }

    # Calculate global max name width for alignment across ALL scripts
    # Increased by 6 characters to make second column wider
    $maxNameWidth = 6
    foreach ($series in $bySeries.Keys) {
        foreach ($entry in $bySeries[$series]) {
            $secondDigit = $entry.Code.Substring(1,1)
            $isSection = $entry.File.BaseName -like ("{0}@*" -f $entry.Code)
            $shouldExclude = ($secondDigit -eq '0' -and $isSection)
            if (-not $shouldExclude) {
                $label = Get-ScriptLabel $entry.File.BaseName
                if ($label.Length -gt $maxNameWidth) { $maxNameWidth = $label.Length }
            }
        }
    }

    # Calculate max section title width for alignment
    $maxSectionWidth = 0
    foreach ($series in ($bySeries.Keys | Sort-Object)) {
        $title = Get-SectionTitle $series $bySeries[$series]
        $sectionHeader = "[$($series.Substring(0,1))] $title"
        if ($sectionHeader.Length -gt $maxSectionWidth) { $maxSectionWidth = $sectionHeader.Length }
    }
    # Add padding for spacing between section title and first script
    # Increased spacing for better readability
    $sectionTitleWidth = $maxSectionWidth + 4
    
    # Build all menu lines first to calculate max width for header
    $menuLines = @()
    $maxLineWidth = 0
    
    foreach ($series in ($bySeries.Keys | Sort-Object)) {
        $title = Get-SectionTitle $series $bySeries[$series]
        $sectionHeader = "[$($series.Substring(0,1))] $title"
        
        # Show all scripts EXCEPT x0@ (section listers are hidden from main menu)
        $sectionItems = @($bySeries[$series] | Where-Object {
            $secondDigit = $_.Code.Substring(1,1)
            $isSection = $_.File.BaseName -like ("{0}@*" -f $_.Code)
            $shouldExclude = ($secondDigit -eq '0' -and $isSection)
            -not $shouldExclude
        })
        
        if ($sectionItems.Count -gt 0) {
            # First script: on same line as section title
            $firstEntry = $sectionItems[0]
            $file = $firstEntry.File
            $purpose = Get-Purpose $file.FullName
            $label = Get-ScriptLabel $file.BaseName
            
            # Build the line with section title
            $line = $sectionHeader.PadRight($sectionTitleWidth) + "{0}) {1}" -f $firstEntry.Code, $label.PadRight($maxNameWidth)
            
            # Add purpose if available (with spacing - 4 spaces for wider second column)
            if ($purpose) {
                $line += "    {0}" -f $purpose
            }
            
            $menuLines += $line
            if ($line.Length -gt $maxLineWidth) { $maxLineWidth = $line.Length }
            
            # Subsequent scripts: indented to align with first script
            if ($sectionItems.Count -gt 1) {
                for ($i = 1; $i -lt $sectionItems.Count; $i++) {
                    $entry = $sectionItems[$i]
                    $file = $entry.File
                    $purpose = Get-Purpose $file.FullName
                    $label = Get-ScriptLabel $file.BaseName
                    
                    # Build the line with indentation matching section title width
                    $line = "".PadRight($sectionTitleWidth) + "{0}) {1}" -f $entry.Code, $label.PadRight($maxNameWidth)
                    
                    # Add purpose if available (with spacing - 4 spaces for wider second column)
                    if ($purpose) {
                        $line += "    {0}" -f $purpose
                    }
                    
                    $menuLines += $line
                    if ($line.Length -gt $maxLineWidth) { $maxLineWidth = $line.Length }
                }
            }
        } else {
            # No scripts in section, just show section title
            $menuLines += $sectionHeader
            if ($sectionHeader.Length -gt $maxLineWidth) { $maxLineWidth = $sectionHeader.Length }
        }
        $menuLines += ""  # Blank line between sections
    }
    
    $title = "Scoop Manager"
    # Display header with width matching longest line
    $maxLineWidth = [Math]::Max($maxLineWidth, $title.Length)
    if ($script:ScoopManagerVersionLabel) {
        $maxLineWidth = [Math]::Max($maxLineWidth, $script:ScoopManagerVersionLabel.Length + 1)
    }
    $headerSeparator = "=" * $maxLineWidth

    # Align console window width to header width (and keep buffer in sync to avoid horizontal scroll)
    try {
        $rawUI = $host.UI.RawUI
        $targetWidth = [Math]::Min($maxLineWidth, $rawUI.MaxPhysicalWindowSize.Width)

        $windowSize = $rawUI.WindowSize
        if ($windowSize.Width -ne $targetWidth) {
            $windowSize.Width = $targetWidth
            $rawUI.WindowSize = $windowSize
        }

        $buffer = $rawUI.BufferSize
        if ($buffer.Width -ne $targetWidth) {
            $buffer.Width = $targetWidth
            $rawUI.BufferSize = $buffer
        }
    } catch { }

    # Single-line header: centered title, right-aligned version (if present)
    $titleStart = [Math]::Floor((($maxLineWidth - $title.Length) / 2))
    $headerLine = " " * $maxLineWidth
    $headerLine = $headerLine.Remove($titleStart, $title.Length).Insert($titleStart, $title)

    if ($script:ScoopManagerVersionLabel) {
        $version = $script:ScoopManagerVersionLabel + " "
        if ($version.Length -gt $maxLineWidth) { $version = $version.Substring(0, $maxLineWidth) }
        $versionStart = $maxLineWidth - $version.Length
        $headerLine = $headerLine.Remove($versionStart, $version.Length).Insert($versionStart, $version)
    }
    Write-Host $headerSeparator
    Write-Host $headerLine
    Write-Host $headerSeparator
    Write-Host ""
    
    # Display all menu lines
    foreach ($line in $menuLines) {
        Write-Host $line
    }
    Write-Host ""
}

function Show-Section([string]$twoDigits) {
    # Determine series from first digit
    $seriesDigit = $twoDigits.Substring(0,1)
    $series = "{0}0" -f $seriesDigit
    
    # Get all scripts in this series
    $scripts = Get-Scripts
    $seriesScripts = @()
    foreach ($s in $scripts) {
        if ($s.BaseName -match '^(\d{2})') {
            $code = $Matches[1]
            if ($code.Substring(0,1) -eq $seriesDigit -and $code.Substring(1,1) -ne '0') {
                # Exclude section scripts themselves
                $seriesScripts += [pscustomobject]@{
                    Code = $code
                    File = $s
                }
            }
        }
    }
    
    if ($seriesScripts.Count -eq 0) {
        Write-Host "[*] No scripts found in this section."
        Write-Host ""
        Write-Host "Press any key to return to menu..."
        $null = [Console]::ReadKey($true)
        return
    }
    
    # Get section title
    $sectionScript = Get-ChildItem -Path $ScriptDir -Filter "${seriesDigit}0@*.ps1" -File | Select-Object -First 1
    $title = "Section $series"
    if ($sectionScript) {
        $name = $sectionScript.BaseName -replace '^\d{2}@', ''
        $title = $name.ToUpper()
    }
    
    Clear-Host
    Write-Host "=========================================="
    Write-Host "  $title"
    Write-Host "=========================================="
    Write-Host ""
    
    # Calculate max name width for alignment
    $maxNameWidth = 0
    foreach ($entry in $seriesScripts) {
        $label = Get-ScriptLabel $entry.File.BaseName
        if ($label.Length -gt $maxNameWidth) { $maxNameWidth = $label.Length }
    }
    
    # Display each script
    foreach ($entry in ($seriesScripts | Sort-Object Code)) {
        $file = $entry.File
        $purpose = Get-Purpose $file.FullName
        $cmds = Get-Commands $file.FullName
        $label = Get-ScriptLabel $file.BaseName
        
        # Build the line
        $line = "  {0}) {1}" -f $entry.Code, $label.PadRight($maxNameWidth)
        
        # Add purpose if available
        if ($purpose) {
            $line += " {0}" -f $purpose
        }
        
        # Add commands if available
        if ($cmds.Count -gt 0) {
            $cmdList = $cmds -join ', '
            $line += " | {0}" -f $cmdList
        }
        
        Write-Host $line
    }
    
    Write-Host ""
    Write-Host "Press any key to return to menu..."
    $null = [Console]::ReadKey($true)
}

function Show-ScriptCompletionStatus {
    <#
    .SYNOPSIS
    Displays script completion status with duration and exit code.

    .PARAMETER ScriptName
    Name of the script that completed.

    .PARAMETER ExitCode
    Exit code returned by the script.

    .PARAMETER StartTime
    Script start timestamp.

    .PARAMETER EndTime
    Script end timestamp.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptName,
        
        [Parameter(Mandatory=$true)]
        [int]$ExitCode,
        
        [Parameter(Mandatory=$true)]
        [DateTime]$StartTime,
        
        [Parameter(Mandatory=$true)]
        [DateTime]$EndTime
    )
    
    $duration = $EndTime - $StartTime
    $durationStr = "{0:D2}:{1:D2}:{2:D2}" -f $duration.Hours, $duration.Minutes, $duration.Seconds
    $endTimestamp = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "Script: $ScriptName"
    Write-Host "Completed with exit code: $ExitCode"
    Write-Host "Ended: $endTimestamp"
    Write-Host "Duration: $durationStr"
    Write-Host "=========================================="
    Write-Host ""
}

function Reset-ProcessLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $processDir = Join-Path $ProjectRoot '.tmp\process'
    $processLog = Join-Path $processDir 'process.log'

    try { New-Item -ItemType Directory -Path $processDir -Force | Out-Null } catch { }

    # Hard truncate (best-effort, but warn if it fails). This log is intended to contain output
    # for a single menu run only, so it must be cleared before running each script.
    try {
        $comspec = $env:ComSpec
        if (-not $comspec) { $comspec = 'cmd.exe' }

        # Use cmd redirection for a true truncate without emitting output.
        $quotedPath = '"' + $processLog.Replace('"', '""') + '"'
        & $comspec /d /c "type nul > $quotedPath" | Out-Null
    } catch {
        Write-Warning "Failed to reset process log: $processLog ($($_.Exception.Message))"
    }
}

function Write-MenuTextFileUtf8NoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    try {
        $writer = Get-Command Write-TextFileUtf8NoBom -ErrorAction SilentlyContinue
        if ($writer) {
            Write-TextFileUtf8NoBom -Path $Path -Content $Content
            return
        }
    } catch { }

    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    } catch {
        # Fallback: always produce a file even if UTF-8 no-BOM write fails for any reason.
        Set-Content -Path $Path -Value $Content -Encoding UTF8 -Force
    }
}

function Invoke-Script([string]$twoDigits) {
    $match = Get-ChildItem -Path $ScriptDir -Filter "$twoDigits*.ps1" -File |
             Where-Object { $_.BaseName -like "$twoDigits*" } |
             Sort-Object Name |
             Select-Object -First 1
    if (-not $match) {
        Write-Host ""
        Write-Host "=========================================="
        Write-Host ("No script is defined for code: {0}" -f $twoDigits)
        Write-Host "Please enter one of the codes shown in the menu."
        Write-Host "=========================================="
        Write-Host ""
        Write-Host "Press any key to return to menu..."
        $null = [Console]::ReadKey($true)
        return
    }
    
    # Check if this is a section script (x0@)
    if ($match.BaseName -match '^(\d)(0)@') {
        # It's a section script - show the section instead
        Show-Section $twoDigits
        return
    }
    
    $displayName = Get-ScriptLabel $match.BaseName
    $scriptName = $match.Name
    
    # Check if logging is enabled
    $loggingEnabled = Get-LoggingConfig -ProjectRoot $ProjectRoot
    
    # Prepare per-script log file path
    $logFilePath = $null
    $logStartTime = Get-Date
    if ($loggingEnabled) {
        $logDir = Join-Path $ProjectRoot '.logs'
        # Resolve path to handle spaces correctly
        try {
            $logDir = [System.IO.Path]::GetFullPath($logDir)
        } catch {
            # If GetFullPath fails, use as-is (New-Item will handle it)
        }
        if (-not (Test-Path $logDir)) {
            $null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
        }
        # Generate per-script log file name
        $sanitizedName = $displayName -replace '\s+', '_'
        $logFileName = "${twoDigits}_${sanitizedName}.log"
        $logFilePath = Join-Path $logDir $logFileName
        # Resolve log file path as well
        try {
            $logFilePath = [System.IO.Path]::GetFullPath($logFilePath)
        } catch {
            # If GetFullPath fails, use as-is (file operations will handle it)
        }
    }
    
    # Run script in the same PowerShell process and capture ALL output streams
    $scriptFile = $match.FullName
    $code = 0
    $transcriptPath = $null
    $startTimestamp = $logStartTime.ToString("yyyy-MM-dd HH:mm:ss")
    
    if ($loggingEnabled -and $logFilePath) {
        # Use Start-Transcript to capture ALL output including Out-Host (which bypasses normal redirection)
        # Create a temporary transcript file
        $transcriptDir = Split-Path -Parent $logFilePath
        $transcriptPath = Join-Path $transcriptDir "transcript_$([System.IO.Path]::GetRandomFileName()).txt"
        
        try {
            # Start transcript BEFORE displaying header so it captures everything
            # This captures ALL console output, even from Out-Host which bypasses the pipeline
            Start-Transcript -Path $transcriptPath -Force | Out-Null
            
            # Display header (now captured by transcript)
            # Calculate relative log path for display (always .logs relative to project root)
            $relativeLogPath = ".logs\$logFileName"
            
            Write-Host ""
            Write-Host "=========================================="
            Write-Host ("Running: {0}) {1}" -f $twoDigits, $displayName)
            Write-Host ("Script: {0}" -f $scriptName)
            Write-Host ("Log: {0}" -f $relativeLogPath)
            Write-Host "Started: $startTimestamp"
            Write-Host "=========================================="
            Write-Host ""

            # Reset the unified external-process log for this run (ProcessRunner appends per command).
            Reset-ProcessLog -ProjectRoot $ProjectRoot

            # Run the script - transcript will capture ALL output (pipeline + Write-Host)
            # Start-Transcript already captures everything that goes to the console, including:
            # - Success output (stdout)
            # - Error output (stderr) 
            # - Warning, Verbose, Debug streams
            # - Information stream (Write-Host output)
            # So we don't need *>&1 which would cause duplication by redirecting streams
            & $scriptFile
            $code = $LASTEXITCODE
            
            # Display final status BEFORE stopping transcript so it gets captured
            $logEndTime = Get-Date
            Show-ScriptCompletionStatus -ScriptName $scriptName -ExitCode $code -StartTime $logStartTime -EndTime $logEndTime
        } finally {
            # Stop transcript and merge its content into the log file
            Stop-Transcript | Out-Null
            
            if (Test-Path $transcriptPath) {
                # Read transcript content and append to log file (skip transcript header/footer)
                $transcriptContent = Get-Content -Path $transcriptPath -Raw -Encoding UTF8
                if ($transcriptContent) {
                    # Extract content between header pattern and footer separator
                    # Transcript format: Header with metadata, then actual content starting with "==========================================", then footer with "**********************"
                    
                    # Find start marker (our header pattern)
                    $startPattern = '=========================================='
                    $startIndex = $transcriptContent.IndexOf($startPattern)
                    
                    if ($startIndex -ge 0) {
                        # Find end marker (separator line with asterisks that precedes footer)
                        $endPattern = "`r`n**********************`r`n"
                        $endIndex = $transcriptContent.IndexOf($endPattern, $startIndex)
                        
                        if ($endIndex -lt 0) {
                            # Try with just newline (in case of LF-only)
                            $endPattern = "`n**********************`n"
                            $endIndex = $transcriptContent.IndexOf($endPattern, $startIndex)
                        }
                        
                        if ($endIndex -ge 0) {
                            # Extract content between markers
                            $extractedContent = $transcriptContent.Substring($startIndex, $endIndex - $startIndex)
                            
                            # Remove ANSI color codes from extracted content
                            $cleanedContent = $extractedContent -replace '\x1b\[[0-9;]*m', ''
                            
                            # Remove PowerShell prompts (lines starting with PS > or >)
                            $cleanedLines = $cleanedContent -split "`r?`n" | Where-Object { $_ -notmatch '^PS .*>' -and $_ -notmatch '^>' }
                            $cleanedContent = $cleanedLines -join "`r`n"
                            
                            # Normalize trailing newlines BEFORE footer section: ensure at most 2 newlines before footer
                            # The footer section starts with newlines followed by "==========================================" and "Script:"
                            # Find where the footer section starts
                            $footerStartPattern = "(`r?`n)+==========================================`r?`nScript:"
                            $footerMatch = [regex]::Match($cleanedContent, $footerStartPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                            if ($footerMatch.Success) {
                                # Split into script output and footer
                                $scriptOutput = $cleanedContent.Substring(0, $footerMatch.Index)
                                $footerWithNewlines = $cleanedContent.Substring($footerMatch.Index)
                                
                                # Extract the leading newlines from footer and the footer content
                                $footerNewlinesMatch = [regex]::Match($footerWithNewlines, '^(`r?`n)+')
                                $footerContent = $footerWithNewlines
                                if ($footerNewlinesMatch.Success) {
                                    $footerContent = $footerWithNewlines.Substring($footerNewlinesMatch.Length)
                                }
                                
                                # Normalize script output trailing newlines to at most 2
                                $scriptOutput = $scriptOutput -replace '[\r\n]+$', ''
                                $scriptOutput = $scriptOutput + "`r`n`r`n"
                                
                                # Recombine (footer content starts with the separator line)
                                $cleanedContent = $scriptOutput + $footerContent
                            } else {
                                # No footer found, just normalize end
                                $cleanedContent = $cleanedContent -replace '[\r\n]+$', ''
                                $cleanedContent = $cleanedContent + "`r`n`r`n"
                            }
                            
                            # Write cleaned transcript content to log file (rolling log - overwrite previous content)
                            Write-MenuTextFileUtf8NoBom -Path $logFilePath -Content $cleanedContent
                        } else {
                            # End marker not found, write warning
                            $debugMsg = "[WARNING] Could not find transcript footer marker. Transcript saved for debugging: $transcriptPath`r`n"
                            Write-MenuTextFileUtf8NoBom -Path $logFilePath -Content $debugMsg
                        }
                    } else {
                        # Start marker not found, write warning
                        $debugMsg = "[WARNING] Could not find transcript content start marker. Transcript saved for debugging: $transcriptPath`r`n"
                        Write-MenuTextFileUtf8NoBom -Path $logFilePath -Content $debugMsg
                    }
                } else {
                    # Transcript file exists but is empty or couldn't be read
                    $debugMsg = "[WARNING] Transcript file exists but is empty or unreadable: $transcriptPath`r`n"
                    Write-MenuTextFileUtf8NoBom -Path $logFilePath -Content $debugMsg
                }
                
                # Only clean up transcript file if we successfully extracted content
                # Check if log file was written (not a warning message)
                if ((Test-Path $logFilePath) -and 
                    (Get-Content $logFilePath -Raw -ErrorAction SilentlyContinue) -notmatch '^\[WARNING\]') {
                    Remove-Item -Path $transcriptPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } else {
        # Logging disabled: display header and run the script normally
        Write-Host "Started: $startTimestamp"
        Write-Host ""
        Write-Host "=========================================="
        Write-Host ("Running: {0}) {1}" -f $twoDigits, $displayName)
        Write-Host ("Script: {0}" -f $scriptName)
        Write-Host "=========================================="
        Write-Host ""

        Reset-ProcessLog -ProjectRoot $ProjectRoot
        
        & $scriptFile
        $code = $LASTEXITCODE
    }
    
    # Display final status (only if logging was disabled, otherwise already displayed in try block)
    if (-not ($loggingEnabled -and $logFilePath)) {
        $logEndTime = Get-Date
        Show-ScriptCompletionStatus -ScriptName $scriptName -ExitCode $code -StartTime $logStartTime -EndTime $logEndTime
    }
    
    Write-Host "Press any key to return to menu..."
    $null = [Console]::ReadKey($true)
}

while ($true) {
    Show-Menu
    $code = Read-TwoDigits
    if (-not $code) { continue }
    if ($code -in @('x','X')) { break }
    Invoke-Script $code
}
