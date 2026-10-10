#Requires -Version 7.4
[CmdletBinding()]
param(
    [string] $DnsModulePath,
    [switch] $CustomOnly,
    [switch] $SkipInit
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixture = Join-Path $PSScriptRoot 'fixtures\dns-dependency'
$work = Join-Path $fixture 'work'
$null = New-Item -ItemType Directory -Path $work -Force

function Get-Block([string] $Text, [string] $Header) {
    $match = [regex]::Match($Text, "(?m)^$Header\s*\{")
    if (-not $match.Success) { throw "Missing block: $Header" }
    $depth = 0
    for ($i = $match.Index + $match.Length - 1; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -eq '{') { $depth++ }
        if ($Text[$i] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($match.Index, $i - $match.Index + 1) }
        }
    }
    throw "Unterminated block: $Header"
}

foreach ($name in @('terraform.tf', 'main.tf', 'variables.tf', 'locals.tf', 'sidecar', 'tests')) {
    Copy-Item -LiteralPath (Join-Path $fixture $name) -Destination $work -Recurse -Force
}
if ($CustomOnly) {
    $variablesPath = Join-Path $work 'variables.tf'
    $variables = (Get-Content $variablesPath -Raw).Replace('default_inbound_endpoint_enabled = true', 'default_inbound_endpoint_enabled = false')
    Set-Content $variablesPath $variables
}
# Exercise the production caller and locals, not a separately maintained implementation.
$caller = Get-Block (Get-Content (Join-Path $root 'main.tf') -Raw) 'module "dns_resolver"'
if ($DnsModulePath) {
    $source = (Resolve-Path -LiteralPath $DnsModulePath).Path.Replace('\', '/')
    $caller = [regex]::Replace($caller, '(?m)^(\s*source\s*=\s*)"[^"]+"', "`$1`"$source`"")
}
Set-Content (Join-Path $work 'main.dns_resolver.tf') $caller
Copy-Item -LiteralPath (Join-Path $root 'locals.dns_resolver.tf') -Destination $work -Force

if (-not $SkipInit) {
    & terraform "-chdir=$work" init -backend=false -input=false -no-color *> (Join-Path $work 'init.log')
    if ($LASTEXITCODE -ne 0) { throw "Fixture init failed. See $work\init.log." }
}
& terraform "-chdir=$work" test -json -verbose -no-color *> (Join-Path $work 'test.jsonl')
if ($LASTEXITCODE -ne 0) { throw "Fixture test failed. See $work\test.jsonl." }
$events = @(Get-Content (Join-Path $work 'test.jsonl') | Where-Object { $_.StartsWith('{') } | ConvertFrom-Json -Depth 100)
$planEvent = @($events | Where-Object { $_.type -eq 'test_plan' -and $_.'@testrun' -eq 'sidecar_update' })
if ($planEvent.Count -ne 1) { throw 'Expected one evaluated sidecar update plan.' }
$changes = @($planEvent[0].test_plan.resource_changes)
$resolver = @($changes | Where-Object address -eq 'module.dns_resolver["hub"].azapi_resource.this')
if ($resolver.Count -ne 1 -or $resolver[0].change.after.parent_id -ne '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test' -or $resolver[0].change.after_unknown.parent_id) {
    throw 'Sidecar updates made the DNS resolver parent ID unknown.'
}
$expectedSubnets = @{ custom = 'snet-custom-in'; existing = 'snet-existing' }
if (-not $CustomOnly) { $expectedSubnets.dns = 'snet-dns' }
foreach ($endpoint in $expectedSubnets.GetEnumerator()) {
    $resource = @($changes | Where-Object address -eq "module.dns_resolver[`"hub`"].azapi_resource.inbound_endpoint[`"$($endpoint.Key)`"]")
    $expected = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/$($endpoint.Value)"
    if ($resource.Count -ne 1 -or $resource[0].change.after.body.properties.ipConfigurations[0].subnet.id -ne $expected) {
        throw "Inbound endpoint '$($endpoint.Key)' no longer targets its requested subnet."
    }
}
if ($CustomOnly -and @($changes | Where-Object address -eq 'module.dns_resolver["hub"].azapi_resource.inbound_endpoint["dns"]').Count) {
    throw 'A disabled default inbound endpoint was unexpectedly created.'
}
$outbound = @($changes | Where-Object address -eq 'module.dns_resolver["hub"].azapi_resource.outbound_endpoint["custom"]')
if ($outbound.Count -ne 1 -or $outbound[0].change.after.body.properties.subnet.id -ne '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-custom-out') {
    throw 'The custom outbound endpoint no longer targets its requested subnet.'
}
& terraform "-chdir=$work" graph -type=plan > (Join-Path $work 'graph.dot')
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the dependency graph.' }
$edges = @{}
foreach ($line in Get-Content (Join-Path $work 'graph.dot')) {
    $edge = [regex]::Match($line, '"([^"]+)" -> "([^"]+)"')
    if ($edge.Success) { $edges[$edge.Groups[1].Value] = @($edges[$edge.Groups[1].Value]) + $edge.Groups[2].Value }
}
foreach ($kind in @('inbound_endpoint', 'outbound_endpoint')) {
    $nodes = @($edges.Keys | Where-Object { $_.Contains("module.dns_resolver.azapi_resource.$kind ") })
    if ($nodes.Count -ne 1) { throw "Missing $kind graph node." }
    $pending = [System.Collections.Generic.Queue[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $pending.Enqueue($nodes[0])
    while ($pending.Count) {
        $node = $pending.Dequeue()
        if (-not $seen.Add($node)) { continue }
        foreach ($next in $edges[$node]) { $pending.Enqueue($next) }
    }
    if (-not @($seen | Where-Object { $_.Contains('module.virtual_network_side_car.terraform_data.subnet ') }).Count) {
        throw "$kind lost its dependency on managed subnets."
    }
}
if ($CustomOnly) {
    'DNS dependencies: parent known; default inbound disabled; custom/existing subnets preserved; inbound/outbound subnet ordering retained.'
}
else {
    'DNS dependencies: parent known; default/custom/existing subnets preserved; inbound/outbound subnet ordering retained.'
}
