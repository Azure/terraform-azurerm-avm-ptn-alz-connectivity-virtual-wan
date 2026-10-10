terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}

# Fixture for `tests/unit/tffr4_ignore_changes.tftest.hcl`.
#
# AVM spec TFFR4 is Severity-MUST and Class-Pattern: `response_export_values` MUST be specified on
# every AzAPI resource, "even if empty". Every `azapi_resource` in this repository therefore
# declares it, and every one of them also names it in `lifecycle.ignore_changes`, because the
# attribute carries no `skip_on` tag (azapi v2.12.0 `internal/services/azapi_resource.go` L77): a
# plan/state difference on it alone defeats `skip.CanSkipExternalRequest` and forces a full PUT of
# the stale `state.body`.
#
# The real modules hard-code `response_export_values = []`, so nothing in them can vary the value
# between two runs -- which is exactly what a behavioural test of `ignore_changes` needs. This
# fixture supplies that variation, and it supplies a CONTROL: two identical resources that differ
# only in whether they carry the `lifecycle` block. If `ignore_changes` ever stopped covering this
# attribute, `guarded` would start tracking `unguarded` and the test would fail.

variable "export_values" {
  type        = list(string)
  description = "The `response_export_values` list handed to both resources. Varied between runs to drive the comparison."
  default     = []
  nullable    = false
}

locals {
  parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
}

# The repository's pattern: attribute declared (TFFR4) and silenced (adoption safety).
resource "azapi_resource" "guarded" {
  name      = "vnet-tffr4-guarded"
  parent_id = local.parent_id
  type      = "Microsoft.Network/virtualNetworks@2024-07-01"
  body = {
    properties = {
      addressSpace = {
        addressPrefixes = ["10.200.0.0/16"]
      }
    }
  }
  location               = "eastus"
  response_export_values = var.export_values
  tags                   = {}

  lifecycle {
    ignore_changes = [
      response_export_values,
    ]
  }
}

# The control. Identical except that it has no `lifecycle` block, so it tracks the configuration.
# This is what every `azapi_resource` in this repository would look like if someone added
# `response_export_values` for TFFR4 and forgot the `ignore_changes` half of the change.
resource "azapi_resource" "unguarded" {
  name      = "vnet-tffr4-unguarded"
  parent_id = local.parent_id
  type      = "Microsoft.Network/virtualNetworks@2024-07-01"
  body = {
    properties = {
      addressSpace = {
        addressPrefixes = ["10.201.0.0/16"]
      }
    }
  }
  location               = "eastus"
  response_export_values = var.export_values
  tags                   = {}
}

output "guarded_response_export_values" {
  description = "The `response_export_values` Terraform settled on for the resource that silences the attribute."
  value       = azapi_resource.guarded.response_export_values
}

output "unguarded_response_export_values" {
  description = "The `response_export_values` Terraform settled on for the control resource."
  value       = azapi_resource.unguarded.response_export_values
}
