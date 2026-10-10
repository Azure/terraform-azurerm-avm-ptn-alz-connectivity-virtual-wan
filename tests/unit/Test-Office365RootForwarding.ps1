#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $LogPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LogPath = [System.IO.Path]::GetFullPath($LogPath)
& terraform "-chdir=$root" test '-test-directory=tests\unit' '-filter=tests\unit\office365_root_forwarding.tftest.hcl' -verbose -json *> $LogPath
if ($LASTEXITCODE -ne 0) {
    throw "Root forwarding test failed. See $LogPath."
}

# Terraform HCL assertions cannot access a child module's unexported resource.
$wanChanges = @(
    foreach ($line in Get-Content -LiteralPath $LogPath) {
        $event = $line | ConvertFrom-Json
        if ($event.type -eq 'test_plan') {
            $event.test_plan.resource_changes |
                Where-Object address -EQ 'module.virtual_wan[0].azapi_resource.virtual_wan[0]'
        }
    }
)

if ($wanChanges.Count -ne 1 -or $wanChanges[0].change.after.body.properties.office365LocalBreakoutCategory -ne 'OptimizeAndAllow') {
    throw "The root input did not reach the actual WAN request body. See $LogPath."
}
Write-Output 'Root Office365 forwarding: pass (actual WAN request body).'
