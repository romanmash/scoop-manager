<#
.SYNOPSIS
Text/JSON file writing helpers

.DESCRIPTION
Centralizes UTF-8 (no BOM) writing to avoid repeated `$utf8NoBom = New-Object ...`
blocks scattered across scripts/modules.

.EXAMPLE
Import-Module "$PSScriptRoot\TextFile.psm1" -Force
Write-TextFileUtf8NoBom -Path $path -Content $content
#>

function Get-Utf8NoBomEncoding {
    [CmdletBinding()]
    [OutputType([System.Text.Encoding])]
    param()

    if (-not $script:Utf8NoBom) {
        $script:Utf8NoBom = New-Object System.Text.UTF8Encoding $false
    }
    return $script:Utf8NoBom
}

function Write-TextFileUtf8NoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $encoding = Get-Utf8NoBomEncoding
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Write-JsonFileUtf8NoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $false)]
        [int]$Depth = 3,

        [Parameter(Mandatory = $false)]
        [switch]$Compress
    )

    $json = if ($Compress) {
        $Object | ConvertTo-Json -Depth $Depth -Compress
    } else {
        $Object | ConvertTo-Json -Depth $Depth
    }

    Write-TextFileUtf8NoBom -Path $Path -Content $json
}

Export-ModuleMember -Function @(
    'Get-Utf8NoBomEncoding',
    'Write-TextFileUtf8NoBom',
    'Write-JsonFileUtf8NoBom'
)

