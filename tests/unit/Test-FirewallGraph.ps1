#Requires -Version 7.4
<#
.SYNOPSIS
Runs provider-mocked upgrade and negative graph regressions without Azure access.
.DESCRIPTION
Terraform downloads the pinned published baseline during init. Every Azure
provider is mocked. No state commands, imports or artificial migration blocks
are used. Generated test cases and JSON evidence stay under the fixture's
ignored work directory. Real-Azure upgrade testing remains a separate gate.
.EXAMPLE
pwsh -File tests\unit\Test-FirewallGraph.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('upgrade', 'first_known', 'first_deferred', 'managed_known', 'managed_unknown', 'managed_deferred', 'customer_known', 'customer_unknown', 'customer_deferred')]
    [string[]] $Case = @('upgrade', 'first_known', 'first_deferred', 'managed_known', 'managed_unknown', 'managed_deferred', 'customer_known', 'customer_unknown', 'customer_deferred'),
    [switch] $SkipInit
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixture = Join-Path $PSScriptRoot 'fixtures\firewall-graph'
$work = Join-Path $fixture 'work'
$testDirectory = Join-Path $fixture 't'
$null = New-Item -ItemType Directory -Path $testDirectory -Force
$null = New-Item -ItemType Directory -Path $work -Force
$cases = @{
    upgrade           = @{ File = 'u' }
    first_known       = @{ File = 'a'; Before = 'baseline'; After = 'candidate'; Inventory = $true; Diagnostic = 'Resource precondition failed'; Detail = 'changing between managed and customer public IP modes' }
    first_deferred    = @{ File = 'b'; Before = 'baseline'; After = 'deferred'; Unknown = $true; Diagnostic = 'Invalid for_each argument'; Detail = 'cannot be determined until apply' }
    managed_known     = @{ File = 'c'; Before = 'candidate'; After = 'candidate'; Diagnostic = 'Resource postcondition failed'; Detail = 'recorded public IP mode cannot change' }
    managed_unknown   = @{ File = 'd'; Before = 'candidate'; After = 'candidate'; Unknown = $true; Diagnostic = 'Resource postcondition failed'; Detail = 'recorded public IP mode cannot change' }
    managed_deferred  = @{ File = 'e'; Before = 'candidate'; After = 'deferred'; Unknown = $true; Diagnostic = 'Resource postcondition failed'; Detail = 'recorded public IP mode cannot change' }
    customer_known    = @{ File = 'f'; Before = 'candidate'; After = 'candidate'; Customer = $true; Diagnostic = 'Resource postcondition failed'; Detail = 'recorded public IP mode cannot change' }
    customer_unknown  = @{ File = 'g'; Before = 'candidate'; After = 'candidate'; Customer = $true; Unknown = $true; Diagnostic = 'Resource postcondition failed'; Detail = 'recorded public IP mode cannot change' }
    customer_deferred = @{ File = 'h'; Before = 'candidate'; After = 'deferred'; Customer = $true; Unknown = $true; Diagnostic = 'Resource postcondition failed'; Detail = 'recorded public IP mode cannot change' }
}
$inventoryOverride = @'
override_data {
  target = module.virtual_wan[0].module.firewalls.data.azapi_resource_list.firewalls[0]
  values = {
    output = {
      firewalls = [
        {
          id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/RG-FIREWALL-GRAPH/providers/Microsoft.Network/azureFirewalls/FW-EDGE-EAST"
          name = "FW-EDGE-EAST"
          properties = { ipConfigurations = [] }
        },
        {
          id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-other/providers/Microsoft.Network/azureFirewalls/fw-edge-east"
          name = "fw-edge-east"
          properties = { ipConfigurations = [] }
        },
        {
          id = "a-nonmatching-name-must-not-be-parsed"
          name = "unrelated"
          properties = {}
        }
      ]
    }
  }
}
'@
foreach ($name in $Case | Where-Object { $_ -ne 'upgrade' }) {
    $scenario = $cases[$name]
    $test = Get-Content (Join-Path $fixture 'cases\transition.tftest.hcl.tmpl') -Raw
    $east = if ($scenario.Customer) {
        'module.virtual_wan[0].module.firewalls.module.customer_firewalls["edge-east"].azapi_resource.this'
    } else {
        'module.virtual_wan[0].module.firewalls.azurerm_firewall.fw["edge-east"]'
    }
    $replacements = @{
        '@BEFORE_SOURCE@'        = "./$($scenario.Before)"
        '@AFTER_SOURCE@'         = "./$($scenario.After)"
        '@BEFORE_CUSTOMER_KEYS@' = $(if ($scenario.Customer) { '["edge-east"]' } else { '[]' })
        '@AFTER_CUSTOMER_KEYS@'  = $(if ($scenario.Customer) { '[]' } else { '["edge-east"]' })
        '@BEFORE_EAST_RESOURCE@' = $east
        '@BEFORE_EAST_OUTPUT@'   = $(if ($scenario.Customer) { 'output = { properties = { additionalProperties = {}, hubIPAddresses = { privateIPAddress = "10.0.0.4" }, threatIntelMode = null } }' } else { '' })
        '@REVISION@'            = $(if ($scenario.Unknown) { '1' } else { '0' })
        '@UNKNOWN_VALUES@'      = $(if ($scenario.Unknown) { 'true' } else { 'false' })
        '@INVENTORY_OVERRIDE@'  = $(if ($scenario.Inventory) { $inventoryOverride } else { '' })
    }
    foreach ($key in $replacements.Keys) {
        $test = $test.Replace($key, $replacements[$key])
    }
    Set-Content (Join-Path $testDirectory "$($scenario.File).tftest.hcl") $test -NoNewline
}
if ('upgrade' -in $Case) {
    $test = Get-Content (Join-Path $PSScriptRoot 'firewall_upgrade.tftest.hcl') -Raw
    $test = $test.Replace('./tests/unit/fixtures/firewall-graph/', './')
    $shortRuns = @{
        published_0_17_2     = 'published'
        upgrade_plan        = 'planned'
        upgrade_apply       = 'upgraded'
        idempotent_plan     = 'unchanged'
        remove_one_firewall  = 'removed'
        disable_firewalls   = 'disabled'
        zero_deployed_hubs   = 'no_hubs'
    }
    foreach ($run in $shortRuns.Keys) {
        $test = $test.Replace($run, $shortRuns[$run])
    }
    Set-Content (Join-Path $testDirectory 'u.tftest.hcl') $test -NoNewline
}

$savedAutomation = $env:TF_IN_AUTOMATION
$savedDataDirectory = $env:TF_DATA_DIR
$savedLogCore = $env:TF_LOG_CORE
$savedLogPath = $env:TF_LOG_PATH
$env:TF_IN_AUTOMATION = '1'
$cacheKey = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($root))).Substring(0, 12)
$env:TF_DATA_DIR = Join-Path ([System.IO.Path]::GetTempPath()) "avm352-graph-$cacheKey"
try {
    if (-not $SkipInit) {
        $providerArguments = @()
        $installedProviders = Join-Path $root '.terraform\providers'
        if (Test-Path $installedProviders) {
            $providerArguments += "-plugin-dir=$installedProviders"
        }
        $initArguments = @(
            "-chdir=$fixture", 'init', '-backend=false', '-input=false', '-upgrade=false',
            '-test-directory=t', '-no-color'
        ) + $providerArguments
        & terraform @initArguments 2>&1 | Set-Content (Join-Path $work 'init.log')
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform init failed. See $(Join-Path $work 'init.log')."
        }
    }

    foreach ($name in $Case) {
        $log = Join-Path $work "$name.jsonl"
        $testName = $cases[$name].File
        $trace = Join-Path $work "$name.trace.log"
        if (Test-Path $trace) { Remove-Item $trace }
        $env:TF_LOG_CORE = 'TRACE'
        $env:TF_LOG_PATH = $trace
        $testPath = Join-Path 't' "$testName.tftest.hcl"
        & terraform "-chdir=$fixture" test '-test-directory=t' "-filter=$testPath" -json -verbose -no-color 2>&1 |
            Set-Content $log
        $exitCode = $LASTEXITCODE
        if ($name -eq 'upgrade' -and $exitCode -ne 0) {
            throw "Case '$name' exited $exitCode. See $log."
        }
        $events = @(Get-Content $log | Where-Object { $_.StartsWith('{') } | ConvertFrom-Json)
        $summary = $events | Where-Object type -eq 'test_summary'
        if ($null -eq $summary -or $summary.test_summary.passed -eq 0) {
            throw "Case '$name' did not execute any passing test runs. See $log."
        }
        if ($name -ne 'upgrade') {
            $diagnostics = @($events | Where-Object { $_.type -eq 'diagnostic' -and $_.'@testrun' -eq 'reject' })
            $expected = @($diagnostics | Where-Object {
                $_.diagnostic.summary -eq $cases[$name].Diagnostic -and
                $_.diagnostic.detail.Contains($cases[$name].Detail)
            })
            if ($exitCode -eq 0 -or $expected.Count -eq 0) {
                throw "Case '$name' did not reject the requested transition with the expected diagnostic. See $log."
            }
            $traceContent = Get-Content -LiteralPath $trace -Raw
            $rejectedPlan = [regex]::Match($traceContent, '(?s)TestFileRunner: starting plan for reject.*?TestFileRunner: completed plan for reject')
            if (-not $rejectedPlan.Success -or $rejectedPlan.Value.Contains('Starting graph walk: walkApply') -or $traceContent.Contains('TestFileRunner: starting apply for reject')) {
                throw "Case '$name' did not fail strictly before the rejected run's apply phase. See $trace."
            }
        } else {
            $plans = @($events | Where-Object type -eq 'test_plan')
            $upgradePlan = @($plans | Where-Object '@testrun' -eq 'planned')
            $secondPlan = @($plans | Where-Object '@testrun' -eq 'unchanged')
            if ($upgradePlan.Count -ne 1 -or $secondPlan.Count -ne 1) {
                throw "Upgrade case did not emit both required plans. See $log."
            }
            $unexpected = @($upgradePlan[0].test_plan.resource_changes | Where-Object {
                ($_.change.actions -join ',') -ne 'no-op' -and
                -not ($_.address -match '\.terraform_data\.public_ip_mode\[' -and ($_.change.actions -join ',') -eq 'create')
            })
            $secondChanges = @($secondPlan[0].test_plan.resource_changes | Where-Object { ($_.change.actions -join ',') -ne 'no-op' })
            if ($unexpected.Count -gt 0 -or $secondChanges.Count -gt 0) {
                throw "Upgrade must change only the new state-only mode records, followed by an entirely no-op plan. See $log."
            }
        }
        Write-Host "PASS $name ($($summary.test_summary.passed) setup/positive runs; $log)"
    }
}
finally {
    $env:TF_IN_AUTOMATION = $savedAutomation
    $env:TF_DATA_DIR = $savedDataDirectory
    $env:TF_LOG_CORE = $savedLogCore
    $env:TF_LOG_PATH = $savedLogPath
}
