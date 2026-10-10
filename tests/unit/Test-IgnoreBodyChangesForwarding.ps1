#Requires -Version 7.4
<#
.SYNOPSIS
Proves the root ignore_body_changes lists are consumed by the actual module and resource arguments.
.DESCRIPTION
`ignore_body_changes` is a write-only azapi attribute, so neither state nor a Terraform test can read it.
This checks the configuration instead: for every hop from the root lists to the azapi resources, the exact
module or resource block must assign `ignore_body_changes` from the expected expression. Removing any hop
fails here. It is a static contract check, not live evidence.
.EXAMPLE
pwsh -File tests\unit\Test-IgnoreBodyChangesForwarding.ps1
#>
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Get-Block([string]$Text, [string]$Header) {
    $m = [regex]::Matches($Text, "(?m)^$Header\s*\{")
    if ($m.Count -ne 1) { return $null }
    $depth = 0
    for ($i = $m[0].Index + $m[0].Length - 1; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -eq '{') { $depth++ } elseif ($Text[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $Text.Substring($m[0].Index, $i - $m[0].Index + 1) } }
    }
    return $null
}

# file, block header, pattern the block must contain
$hops = @(
    @('main.tf', 'module "virtual_wan"', 'ignore_body_changes\s*=\s*local\.ignore_body_changes_virtual_wans\s*\r?\n'),
    @('main.tf', 'module "route_map"', 'ignore_body_changes\s*=\s*\{\s*network_virtual_hubs_route_maps\s*=\s*local\.ignore_body_changes_route_maps\s*\}'),
    @('modules/virtual-wan/main.firewall.tf', 'module "firewalls"', 'ignore_body_changes\s*=\s*var\.ignore_body_changes\.network_azure_firewalls\s*\r?\n'),
    @('modules/firewall/main.tf', 'resource "azapi_resource" "fw"', 'ignore_body_changes\s*=\s*length\(var\.ignore_body_changes\.network_azure_firewalls\)\s*>\s*0\s*\?\s*\(\s*var\.ignore_body_changes\.network_azure_firewalls'),
    @('modules/firewall/main.tf', 'resource "azapi_resource" "diagnostic_setting"', 'ignore_body_changes\s*=\s*length\(var\.ignore_body_changes\.insights_diagnostic_settings\)\s*>\s*0\s*\?\s*\(\s*var\.ignore_body_changes\.insights_diagnostic_settings'),
    @('modules/firewall/main.tf', 'module "customer_firewalls"', 'ignore_body_changes\s*=\s*var\.ignore_body_changes\s*\r?\n'),
    @('modules/firewall-customer-ip/main.tf', 'resource "azapi_resource" "this"', 'ignore_body_changes\s*=\s*length\(var\.ignore_body_changes\.network_azure_firewalls\)\s*>\s*0\s*\?\s*var\.ignore_body_changes\.network_azure_firewalls\s*:\s*null'),
    @('modules/firewall-customer-ip/main.tf', 'resource "azapi_resource" "diagnostic_settings"', 'ignore_body_changes\s*=\s*length\(var\.ignore_body_changes\.insights_diagnostic_settings\)\s*>\s*0\s*\?\s*var\.ignore_body_changes\.insights_diagnostic_settings\s*:\s*null'),
    @('modules/route-map/main.tf', 'resource "azapi_resource" "route_map"', 'ignore_body_changes\s*=\s*length\(var\.ignore_body_changes\.network_virtual_hubs_route_maps\)\s*>\s*0\s*\?\s*var\.ignore_body_changes\.network_virtual_hubs_route_maps\s*:\s*null')
)

$failed = @()
foreach ($h in $hops) {
    $path = Join-Path $root $h[0]
    $text = (Get-Content -Raw $path) -replace '(?m)^\s*#.*$', ''
    $block = Get-Block $text $h[1]
    if (-not $block) { $failed += "$($h[0]): block '$($h[1])' missing or duplicated"; continue }
    if ($block -notmatch $h[2]) { $failed += "$($h[0]): '$($h[1])' does not consume the expected ignore_body_changes list" }
}
if ($failed) { throw ($failed -join "`n") }
'ignore_body_changes forwarding: pass'
