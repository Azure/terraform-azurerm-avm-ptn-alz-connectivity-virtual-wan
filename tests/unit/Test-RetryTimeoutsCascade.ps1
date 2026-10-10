#Requires -Version 7.4
<#
.SYNOPSIS
Proves root retry/timeouts reach the exact firewall azapi resource in both public IP modes, mocked, no Azure access.
.DESCRIPTION
Terraform tests cannot assert on resources inside nested modules, so this reads the state that
`terraform test -verbose` prints. For every run it isolates the block of one exact resource address and
asserts retry/timeouts only inside that block. A missing or duplicated address fails, and so does the
other mode's firewall address appearing in the run.
.EXAMPLE
pwsh -File tests\unit\Test-RetryTimeoutsCascade.ps1
#>
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$dir = 'tests/unit/fixtures/cascade-observe'

$managed = 'module.virtual_wan[0].module.firewalls.azapi_resource.fw["hub"]'
$customer = 'module.virtual_wan[0].module.firewalls.module.customer_firewalls["hub"].azapi_resource.this'
$wan = 'module.virtual_wan[0].azapi_resource.virtual_wan[0]'

$defaultTimeouts = 'timeouts \{\s*create = "90m"\s*delete = "90m"\s*read\s*= "5m"\s*update = "90m"\s*\}'
$explicitTimeouts = 'timeouts \{\s*create = "11m"\s*delete = "13m"\s*read\s*= "5m"\s*update = "90m"\s*\}'
$defaultRetry = 'retry\s*= \{\s*error_message_regex\s*= \[\s*"ReferencedResourceNotProvisioned",?\s*\]\s*interval_seconds\s*= 10\s*max_interval_seconds\s*= 180'
$explicitRetry = 'retry\s*= \{\s*error_message_regex\s*= \[\s*"CallerRegex",?\s*\]\s*interval_seconds\s*= 3\s*max_interval_seconds\s*= 30'
$wanExplicit = 'timeouts \{\s*create = "11m"\s*delete = "13m"'

# run -> @{ Address; Absent; Patterns }
$expect = [ordered]@{
    managed_default   = @{ Address = $managed; Absent = $customer; Patterns = @($defaultRetry, $defaultTimeouts) }
    managed_explicit  = @{ Address = $managed; Absent = $customer; Patterns = @($explicitRetry, $explicitTimeouts); Extra = @{ Address = $wan; Patterns = @($wanExplicit, '"CallerRegex"') } }
    customer_default  = @{ Address = $customer; Absent = $managed; Patterns = @($defaultRetry, $defaultTimeouts) }
    customer_explicit = @{ Address = $customer; Absent = $managed; Patterns = @($explicitRetry, $explicitTimeouts); Extra = @{ Address = $wan; Patterns = @($wanExplicit, '"CallerRegex"') } }
}

function Get-RunSection([string]$Text, [string]$Name) {
    $parts = [regex]::Split($Text, '(?m)^\s*run "')
    $hits = @($parts | Where-Object { $_.StartsWith("$Name`"") })
    if ($hits.Count -ne 1) { return $null }
    return $hits[0]
}

# Returns the single block opened by "# <address>:" up to the next "# " header, or $null when missing/duplicated.
function Get-ResourceBlock([string]$Section, [string]$Address) {
    $header = "(?m)^# $([regex]::Escape($Address)):\s*$"
    $found = [regex]::Matches($Section, $header)
    if ($found.Count -ne 1) { return @{ Count = $found.Count; Text = $null } }
    $tail = $Section.Substring($found[0].Index + $found[0].Length)
    $next = [regex]::Match($tail, '(?m)^# \S')
    $text = if ($next.Success) { $tail.Substring(0, $next.Index) } else { $tail }
    return @{ Count = 1; Text = $text }
}

function Test-Cascade([string]$Output) {
    $failed = @()
    foreach ($name in $expect.Keys) {
        $e = $expect[$name]
        $section = Get-RunSection $Output $name
        if (-not $section) { $failed += "${name}: run missing or duplicated"; continue }
        if ((Get-ResourceBlock $section $e.Absent).Count -ne 0) { $failed += "${name}: unexpected address $($e.Absent)" }
        $targets = @(@{ Address = $e.Address; Patterns = $e.Patterns })
        if ($e.Extra) { $targets += $e.Extra }
        foreach ($t in $targets) {
            $block = Get-ResourceBlock $section $t.Address
            if ($block.Count -ne 1) { $failed += "${name}: $($t.Address) found $($block.Count) times, expected 1"; continue }
            foreach ($pattern in $t.Patterns) {
                if ($block.Text -notmatch $pattern) { $failed += "${name}: $($t.Address) has no match for $pattern" }
            }
        }
    }
    return $failed
}

Push-Location $root
try {
    $out = terraform test -no-color -verbose "-test-directory=$dir" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "terraform test failed:`n$out" }
    $failed = Test-Cascade $out
    if ($failed) { throw ($failed -join "`n") }
    'retry/timeouts cascade: pass'
}
finally { Pop-Location }
