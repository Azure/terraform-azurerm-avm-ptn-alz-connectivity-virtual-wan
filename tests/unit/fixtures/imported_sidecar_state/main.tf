terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

module "virtual_network_side_car" {
  source   = "./virtual-network"
  for_each = toset(["hub1"])
}

module "virtual_wan" {
  source = "../../../../modules/virtual-wan"
  count  = 1

  location            = "eastus"
  resource_group_name = "rg-test"
  virtual_wan_name    = "vwan-test"
  enable_telemetry    = false
  tags                = {}
  virtual_hubs = {
    hub1 = {
      name                = "vhub-test"
      location            = "eastus"
      resource_group_name = "rg-test"
      address_prefix      = "10.0.0.0/23"
      sku                 = "Standard"
      tags                = {}
    }
  }
  virtual_network_connections = {
    private_dns_vnet_hub1 = {
      name                      = "vnet-side-car-hub1"
      virtual_hub_key           = "hub1"
      remote_virtual_network_id = module.virtual_network_side_car["hub1"].resource_id
    }
  }
}

output "imported_subnets" {
  description = "The Azure-returned parent subnet collection in the synthetic state."
  value       = module.virtual_network_side_car["hub1"].resource.body.properties.subnets
}

output "imported_peerings" {
  description = "The Azure-managed peering collection in the synthetic state."
  value       = module.virtual_network_side_car["hub1"].resource.body.properties.virtualNetworkPeerings
}

output "virtual_network_resource_id" {
  description = "The seeded sidecar VNet resource ID."
  value       = module.virtual_network_side_car["hub1"].resource_id
}

output "subnet_resource_id" {
  description = "The independently managed subnet resource ID."
  value       = module.virtual_network_side_car["hub1"].subnet_resource_id
}