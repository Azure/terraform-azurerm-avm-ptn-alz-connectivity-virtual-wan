#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$fixture = Join-Path $PSScriptRoot 'fixtures\example-plan\plan.tftest.hcl'
$originalDataDirectory = $env:TF_DATA_DIR
$results = @()

try {
    foreach ($example in Get-ChildItem -LiteralPath (Join-Path $root 'examples') -Directory) {
        $testDirectory = Join-Path $example.FullName '.offline-plan-tests'
        if (Test-Path -LiteralPath $testDirectory) {
            throw "Refusing to overwrite existing test directory: $testDirectory"
        }
        $null = New-Item -ItemType Directory -Path $testDirectory
        $testFile = Join-Path $testDirectory 'plan.tftest.hcl'
        Copy-Item -LiteralPath $fixture -Destination $testFile
        if ($example.Name -eq 'full-multi-region') {
            Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\example-plan\accelerator-mocks.hcl') |
                Add-Content -LiteralPath $testFile
        }
        $prefix = Join-Path $OutputDirectory $example.Name
        $env:TF_DATA_DIR = Join-Path $OutputDirectory "$($example.Name)-data"
        $result = [pscustomobject]@{ Example = $example.Name; Init = 'not run'; Providers = 'not run'; Validate = 'not run'; MockedPlan = 'not run' }

        try {
            & terraform "-chdir=$($example.FullName)" init -backend=false -input=false '-test-directory=.offline-plan-tests' -no-color *> "$prefix-init.log"
            if ($LASTEXITCODE -ne 0) {
                $result.Init = 'fail'
                Write-Warning "Example init failed. See $prefix-init.log."
                continue
            }
            $result.Init = 'pass'

            & terraform "-chdir=$($example.FullName)" providers *> "$prefix-providers.log"
            $providerExitCode = $LASTEXITCODE
            $azureRmDeclarations = @(Select-String -LiteralPath "$prefix-providers.log" -Pattern 'registry\.terraform\.io/hashicorp/azurerm')
            $expectedAzureRmDeclarations = if ($example.Name -eq 'full-multi-region') { 2 } else { 0 }
            $allowedOwners = $true
            if ($example.Name -eq 'full-multi-region') {
                $providerLines = Get-Content -LiteralPath "$prefix-providers.log"
                $owners = @(
                    foreach ($declaration in $azureRmDeclarations) {
                        $precedingModules = @($providerLines | Select-Object -First ($declaration.LineNumber - 1) |
                            Select-String -Pattern 'module\.[A-Za-z0-9_-]+\s*$')
                        if ($precedingModules.Count -eq 0) { 'root' }
                        else { $precedingModules[-1].Matches[0].Value.Trim() }
                    }
                )
                $allowedOwners = ($owners -join ',') -eq 'root,module.config'
            }
            if ($providerExitCode -ne 0 -or $azureRmDeclarations.Count -ne $expectedAzureRmDeclarations -or -not $allowedOwners) {
                $result.Providers = 'fail'
                Write-Warning "Provider discovery failed or has an unexpected AzureRM dependency. See $prefix-providers.log."
                continue
            }
            $result.Providers = if ($example.Name -eq 'full-multi-region') { 'AzureRM client-config exception' } else { 'AzAPI, no AzureRM' }

            & terraform "-chdir=$($example.FullName)" validate -no-color *> "$prefix-validate.log"
            if ($LASTEXITCODE -ne 0) {
                $result.Validate = 'fail'
                Write-Warning "Example validation failed. See $prefix-validate.log."
                continue
            }
            $result.Validate = 'pass'

            & terraform "-chdir=$($example.FullName)" test '-test-directory=.offline-plan-tests' -no-color *> "$prefix-plan.log"
            $result.MockedPlan = if ($LASTEXITCODE -eq 0) { 'pass' } else { 'fail' }
            if ($result.MockedPlan -eq 'fail') {
                Write-Warning "Mocked example plan failed. See $prefix-plan.log."
            }
        }
        finally {
            $results += $result
            Remove-Item -LiteralPath $testFile
            Remove-Item -LiteralPath $testDirectory
        }
    }
}
finally {
    $env:TF_DATA_DIR = $originalDataDirectory
    $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'example-results.json')
}

$results | Format-Table
if ($results | Where-Object MockedPlan -NE 'pass') {
    throw "One or more examples failed. See $OutputDirectory\example-results.json and per-example logs."
}
