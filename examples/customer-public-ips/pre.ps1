#!/usr/bin/env pwsh
# Gives each e2e run unique resource names. Customer mode needs the firewall name
# and resource group known at plan time, so the suffix is an input rather than a
# random resource. The *.tfvars file is gitignored and loaded automatically.

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$randomness = '{0:x4}' -f (Get-Random -Minimum 0 -Maximum 0x10000)
$tfvarsPath = Join-Path $PSScriptRoot 'e2e.auto.tfvars'
[System.IO.File]::WriteAllText($tfvarsPath, "name_prefix = `"cip-$randomness`"`n")

Write-Host "Using name prefix 'cip-$randomness'."
