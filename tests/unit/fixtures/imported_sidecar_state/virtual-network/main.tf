terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}

locals {
  parent_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
  virtual_network_id = "${local.parent_id}/providers/Microsoft.Network/virtualNetworks/vnet-sidecar-test"
}

resource "azapi_resource" "vnet" {
  location  = "eastus"
  name      = "vnet-sidecar-test"
  parent_id = local.parent_id
  type      = "Microsoft.Network/virtualNetworks@2024-07-01"
  body = {
    properties = {
      addressSpace = {
        addressPrefixes = ["10.100.0.0/16"]
      }
      subnets = [{
        id   = "${local.virtual_network_id}/subnets/snet-workload"
        name = "snet-workload"
        type = "Microsoft.Network/virtualNetworks/subnets"
        properties = {
          addressPrefix = "10.100.1.0/24"
        }
      }]
      virtualNetworkPeerings = [{
        id   = "${local.virtual_network_id}/virtualNetworkPeerings/RemoteVnetToHubPeering_fixture"
        name = "RemoteVnetToHubPeering_fixture"
        type = "Microsoft.Network/virtualNetworks/virtualNetworkPeerings"
        properties = {
          allowForwardedTraffic     = false
          allowGatewayTransit       = false
          allowVirtualNetworkAccess = true
          peeringState              = "Connected"
          remoteVirtualNetwork = {
            id = "${local.parent_id}/providers/Microsoft.Network/virtualNetworks/HV_fixture"
          }
          useRemoteGateways = true
        }
      }]
    }
  }
  response_export_values = []
  tags                   = {}
}

module "subnet" {
  source   = "./subnet"
  for_each = toset(["workload"])

  parent_id = azapi_resource.vnet.id
}

output "resource" {
  description = "The synthetic imported VNet state."
  value       = azapi_resource.vnet
}

output "resource_id" {
  description = "The synthetic VNet resource ID."
  value       = azapi_resource.vnet.id
}

output "subnet_resource_id" {
  description = "The independently managed subnet ID."
  value       = module.subnet["workload"].resource_id
}