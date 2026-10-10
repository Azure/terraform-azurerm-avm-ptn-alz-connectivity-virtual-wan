terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}

variable "parent_id" {
  type        = string
  description = "The synthetic parent VNet resource ID."
}

resource "azapi_resource" "subnet" {
  count = 1

  name      = "snet-workload"
  parent_id = var.parent_id
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-07-01"
  body = {
    properties = {
      addressPrefix                     = null
      addressPrefixes                   = ["10.100.1.0/24"]
      delegations                       = null
      defaultOutboundAccess             = false
      natGateway                        = null
      networkSecurityGroup              = null
      privateEndpointNetworkPolicies    = "Enabled"
      privateLinkServiceNetworkPolicies = "Enabled"
      routeTable                        = null
      serviceEndpoints                  = null
      serviceEndpointPolicies           = null
      sharingScope                      = null
    }
  }
  locks = [var.parent_id]
  # Seed-only fixture: it stands in for the subnet submodule of
  # `Azure/avm-res-network-virtualnetwork/azurerm` v0.22.2, a module this repository does not own.
  # The non-empty list and the absent `lifecycle.ignore_changes` both mirror that upstream module
  # so the seeded state is faithful; neither is a pattern to copy into `modules/*`. This
  # repository's own TFFR4 contract is pinned in `tests/unit/tffr4_ignore_changes.tftest.hcl`.
  response_export_values    = ["properties.addressPrefixes", "properties.addressPrefix"]
  schema_validation_enabled = true
}

output "resource_id" {
  description = "The synthetic independently managed subnet ID."
  value       = azapi_resource.subnet[0].id
}