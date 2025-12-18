<#
.SYNOPSIS
Path update utilities for Scoop migration

.DESCRIPTION
Provides reusable functions for extracting path prefixes and updating paths in text content and JSON objects.
Used for migrating Scoop installations between different locations.

.EXAMPLE
Import-Module "$PSScriptRoot\ScoopPathTools.psm1" -Force
$oldPrefix = Get-PathPrefix -Path "D:\_\portable_scoop"
$newContent = Update-PathsInText -Content $textContent -OldPrefix $oldPrefix -NewPrefix "C:\Apps"
#>

function Get-PathPrefix {
    <#
    .SYNOPSIS
    Extracts path prefix (everything before \portable_scoop)
    
    .DESCRIPTION
    Extracts the path prefix from a full path. The prefix is everything before \portable_scoop.
    For example: "D:\_\portable_scoop" -> "D:\_"
    
    .PARAMETER Path
    Full path containing portable_scoop
    
    .EXAMPLE
    $prefix = Get-PathPrefix -Path "D:\_\portable_scoop"
    # Returns: "D:\_"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    if ([string]::IsNullOrEmpty($Path)) {
        return $null
    }
    
    if ($Path -match '\\portable_scoop') {
        $prefix = $Path -replace '\\portable_scoop.*$', ''
        # Return null if prefix is empty (path was just "portable_scoop" or "\portable_scoop")
        if ([string]::IsNullOrEmpty($prefix)) {
            return $null
        }
        return $prefix
    }
    
    return $null
}

function Update-PathsInText {
    <#
    .SYNOPSIS
    Updates path prefixes in text content
    
    .DESCRIPTION
    Updates all occurrences of old path prefix with new path prefix in text content.
    Handles both plain and escaped forms of paths.
    
    .PARAMETER Content
    Text content to process
    
    .PARAMETER OldPrefix
    Old path prefix (everything before \portable_scoop)
    
    .PARAMETER NewPrefix
    New path prefix (everything before \portable_scoop)
    
    .EXAMPLE
    $newContent = Update-PathsInText -Content $textContent -OldPrefix "D:\_" -NewPrefix "C:\Apps"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,
        
        [Parameter(Mandatory=$true)]
        [string]$OldPrefix,
        
        [Parameter(Mandatory=$true)]
        [string]$NewPrefix
    )
    
    # Ensure Content is a string and not null
    if ($null -eq $Content) {
        return $null
    }
    
    # Convert to string if it's not already
    $contentStr = [string]$Content
    
    if ([string]::IsNullOrEmpty($contentStr)) {
        return $contentStr
    }
    
    # Check if content contains portable_scoop (plain or escaped)
    if ($contentStr -notmatch '\\portable_scoop' -and $contentStr -notmatch '\\\\portable_scoop') {
        return $contentStr
    }
    
    # Validate prefixes are not null or empty
    if ([string]::IsNullOrEmpty($OldPrefix) -or [string]::IsNullOrEmpty($NewPrefix)) {
        return $contentStr
    }
    
    $newContent = $contentStr
    
    # Create escaped versions for JSON/REG files
    $OldPrefixEscaped = $OldPrefix -replace '\\', '\\\\'
    $NewPrefixEscaped = $NewPrefix -replace '\\', '\\\\'
    
    # Replace all occurrences of plain form: OldPrefix\portable_scoop -> NewPrefix\portable_scoop
    # This handles cases like "C:\path\portable_scoop\" or "C:\path\portable_scoop\apps" etc.
    $newContent = $newContent.Replace("$OldPrefix\portable_scoop", "$NewPrefix\portable_scoop")
    
    # Replace all occurrences of escaped form: OldPrefixEscaped\\portable_scoop -> NewPrefixEscaped\\portable_scoop
    # This handles cases like "D:\\_\\portable_scoop" or "D:\\_\\portable_scoop\\apps" etc.
    $newContent = $newContent.Replace("$OldPrefixEscaped\\portable_scoop", "$NewPrefixEscaped\\portable_scoop")
    
    return $newContent
}

function Update-PathsInJsonObject {
    <#
    .SYNOPSIS
    Updates path prefixes in JSON object
    
    .DESCRIPTION
    Recursively processes a JSON object (PSCustomObject) and updates all path values
    that contain portable_scoop with new path prefix.
    
    .PARAMETER JsonObject
    JSON object (PSCustomObject) to process
    
    .PARAMETER OldPrefix
    Old path prefix (everything before \portable_scoop)
    
    .PARAMETER NewPrefix
    New path prefix (everything before \portable_scoop)
    
    .EXAMPLE
    $newConfig = Update-PathsInJsonObject -JsonObject $config -OldPrefix "D:\_" -NewPrefix "C:\Apps"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$JsonObject,
        
        [Parameter(Mandatory=$true)]
        [string]$OldPrefix,
        
        [Parameter(Mandatory=$true)]
        [string]$NewPrefix
    )
    
    if ($null -eq $JsonObject) {
        return $JsonObject
    }
    
    # Create escaped versions for JSON/REG files
    $OldPrefixEscaped = $OldPrefix -replace '\\', '\\\\'
    $NewPrefixEscaped = $NewPrefix -replace '\\', '\\\\'
    
    # Process each property in the object
    $properties = $JsonObject.PSObject.Properties
    
    foreach ($prop in $properties) {
        $value = $prop.Value
        
        if ($null -eq $value) {
            continue
        }
        
        # If value is a string and contains portable_scoop, replace it
        if ($value -is [string]) {
            if ($value -match '\\portable_scoop' -or $value -match '\\\\portable_scoop') {
                $newValue = Update-PathsInText -Content $value -OldPrefix $OldPrefix -NewPrefix $NewPrefix
                $JsonObject.$($prop.Name) = $newValue
            }
        }
        # If value is a PSCustomObject, recurse
        elseif ($value -is [PSCustomObject]) {
            $JsonObject.$($prop.Name) = Update-PathsInJsonObject -JsonObject $value -OldPrefix $OldPrefix -NewPrefix $NewPrefix
        }
        # If value is an array, process each element
        elseif ($value -is [Array]) {
            $newArray = @()
            foreach ($item in $value) {
                if ($item -is [PSCustomObject]) {
                    $newArray += Update-PathsInJsonObject -JsonObject $item -OldPrefix $OldPrefix -NewPrefix $NewPrefix
                } elseif ($item -is [string] -and ($item -match '\\portable_scoop' -or $item -match '\\\\portable_scoop')) {
                    $newArray += Update-PathsInText -Content $item -OldPrefix $OldPrefix -NewPrefix $NewPrefix
                } else {
                    $newArray += $item
                }
            }
            $JsonObject.$($prop.Name) = $newArray
        }
    }
    
    return $JsonObject
}

Export-ModuleMember -Function @(
    'Get-PathPrefix',
    'Update-PathsInText',
    'Update-PathsInJsonObject'
)

