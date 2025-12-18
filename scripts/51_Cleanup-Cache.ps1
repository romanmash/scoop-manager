<#
.SYNOPSIS
Clears download cache

.CMD
scoop cache show
scoop cache rm *
#>

$ErrorActionPreference = 'Stop'

# Load simple Scoop command wrapper (standard bootstrap pattern)
$ModulePath = Join-Path $PSScriptRoot '..\modules\ScoopCommand.psm1'
Import-Module $ModulePath -Force
$ScoopEnvModule = Join-Path $PSScriptRoot '..\modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

$commands = @(
    @{ Command = "cache show"; Message = "Cache status before cleanup:" }
    @{ Command = "cache rm"; Args = "*"; Message = "Clearing cache..." }
    @{ Command = "cache show"; Message = "Cache status after cleanup:" }
)

Invoke-ScoopCommandScript -MultipleCommands $commands

exit 0
