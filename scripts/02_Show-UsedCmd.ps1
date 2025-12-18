<#
.SYNOPSIS
Display all used native Scoop commands

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Path resolution
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Console UI helpers (section/subsection headers)
try {
    $ConsoleUiPath = Join-Path $ProjectRoot 'modules\ConsoleUi.psm1'
    if (Test-Path -LiteralPath $ConsoleUiPath) {
        Import-Module $ConsoleUiPath -Force -ErrorAction SilentlyContinue
    }
} catch { }

# Duplicate functions from Manage-ScoopMenu.ps1
function Get-Scripts {
    Get-ChildItem -Path $ScriptDir -Filter '*.ps1' -File |
        Where-Object { $_.Name -notlike 'Manage-ScoopMenu.ps1' } |
        Sort-Object Name
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
        # Match .CMD block in help comments (all scripts now have explicit .CMD blocks)
        # Use same pattern as Manage-ScoopMenu.ps1 for consistency
        if ($content -match '(?s)\.CMD\s+(.+?)(?:\r?\n\.|#>)') {
            $cmdSection = $Matches[1].Trim()
            # If .CMD block contains only "-", return empty array (will display as "-")
            if ($cmdSection -eq '-') {
                return ,@()
            }
            $cmdLines = $cmdSection -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
            foreach ($line in $cmdLines) {
                $cmd = $line.Trim()
                # Skip empty lines and lines starting with .
                if ($cmd -and $cmd -notmatch '^\.') { 
                    $cmds += $cmd 
                }
            }
            if ($cmds.Count -gt 0) { return ,$cmds }
        }
    }
    # Fallback to old format (for backward compatibility)
    $lines = Get-Content -Path $filePath -TotalCount 15 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*#\s*Cmd\s*:\s*(.+)$' }
    foreach ($line in $lines) {
        $cmd = ($line -replace '^\s*#\s*Cmd\s*:\s*','').Trim()
        if ($cmd) { $cmds += $cmd }
    }
    return ,$cmds
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

Write-SectionHeader -Title 'USED NATIVE SCOOP COMMANDS'

# Get all scripts and organize by series
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

# Calculate max widths for alignment
$maxNameWidth = 0
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

# Calculate max section title width
$maxSectionWidth = 0
foreach ($series in ($bySeries.Keys | Sort-Object)) {
    $title = Get-SectionTitle $series $bySeries[$series]
    $sectionHeader = "[$($series.Substring(0,1))] $title"
    if ($sectionHeader.Length -gt $maxSectionWidth) { $maxSectionWidth = $sectionHeader.Length }
}
$sectionTitleWidth = $maxSectionWidth + 4

# Display table
foreach ($series in ($bySeries.Keys | Sort-Object)) {
    $title = Get-SectionTitle $series $bySeries[$series]
    $sectionHeader = "[$($series.Substring(0,1))] $title"
    
    # Show all scripts EXCEPT x0@ (section listers are hidden)
    $sectionItems = @($bySeries[$series] | Where-Object {
        $secondDigit = $_.Code.Substring(1,1)
        $isSection = $_.File.BaseName -like ("{0}@*" -f $_.Code)
        $shouldExclude = ($secondDigit -eq '0' -and $isSection)
        -not $shouldExclude
    })
    
    if ($sectionItems.Count -gt 0) {
        foreach ($entry in $sectionItems) {
            $file = $entry.File
            $cmds = Get-Commands $file.FullName
            $label = Get-ScriptLabel $file.BaseName
            
            # Build the first line with section title (only for first item in section)
            if ($entry -eq $sectionItems[0]) {
                $line = $sectionHeader.PadRight($sectionTitleWidth) + "{0}) {1}" -f $entry.Code, $label.PadRight($maxNameWidth)
            } else {
                $line = "".PadRight($sectionTitleWidth) + "{0}) {1}" -f $entry.Code, $label.PadRight($maxNameWidth)
            }
            
            # Calculate the indent width for command lines (where first command starts)
            $commandIndentWidth = $line.Length + 4
            
            # Add first command or "-" if none
            if ($cmds.Count -gt 0) {
                $line += "    {0}" -f $cmds[0]
            } else {
                $line += "    -"
            }
            
            Write-Host $line
            
            # Display remaining commands on separate lines, indented to align with first command
            if ($cmds.Count -gt 1) {
                for ($i = 1; $i -lt $cmds.Count; $i++) {
                    $cmd = $cmds[$i]
                    $indentedLine = "".PadRight($commandIndentWidth) + $cmd
                    Write-Host $indentedLine
                }
            }
        }
    }
    Write-Host ""
}

exit 0
