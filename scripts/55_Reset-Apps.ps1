<#
.SYNOPSIS
Resets all apps (refreshes shims)

.CMD
scoop reset *
#>

$ErrorActionPreference = 'Stop'

# Load simple Scoop command wrapper (standard bootstrap pattern)
$ModulePath = Join-Path $PSScriptRoot '..\modules\ScoopCommand.psm1'
Import-Module $ModulePath -Force
$ScoopEnvModule = Join-Path $PSScriptRoot '..\modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

Invoke-ScoopCommandScript -Command "reset" -CommandArgs "*" -InfoMessage "Resetting all apps..."

exit 0
