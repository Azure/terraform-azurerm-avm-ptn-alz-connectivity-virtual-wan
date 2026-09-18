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
  locks                     = [var.parent_id]
  response_export_values    = ["properties.addressPrefixes", "properties.addressPrefix"]
  schema_validation_enabled = true
}

output "resource_id" {
  description = "The synthetic independently managed subnet ID."
  value       = azapi_resource.subnet[0].id
}