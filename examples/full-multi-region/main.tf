terraform {
  required_version = "~> 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.21"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "starter_locations" {
  type        = list(string)
  description = "The default for Azure resources. (e.g 'uksouth')"
  default     = ["eastus2", "westus2"]
}

variable "connectivity_resource_groups" {
  type = map(object({
    name     = string
    location = string
  }))
  default     = {}
  description = <<DESCRIPTION
A map of resource groups to create. These must be created before the connectivity module is applied.

The following attributes are supported:

  - name: The name of the resource group
  - location: The location of the resource group

DESCRIPTION
}

variable "virtual_wan_settings" {
  type        = any
  default     = {}
  description = <<DESCRIPTION
The shared settings for the Virtual WAN. This is where global resources are defined.

The following attributes are supported:

  - ddos_protection_plan: (Optional) The DDoS protection plan settings. Detailed information about the DDoS protection plan can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-ptn-ddosprotectionplan

The Virtual WAN module attributes are also supported. Detailed information about the Virtual WAN module variables can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-ptn-virtualwan

DESCRIPTION
}

variable "virtual_wan_virtual_hubs" {
  type = map(object({
    hub               = any
    firewall          = optional(any)
    firewall_policy   = optional(any)
    private_dns_zones = optional(any)
    bastion           = optional(any)
    virtual_network_gateways = optional(object({
      express_route = optional(any)
      vpn           = optional(any)
    }))
    side_car_virtual_network = optional(any)
  }))
  default     = {}
  description = <<DESCRIPTION
A map of virtual hubs to create.

The following attributes are supported:

  - hub: The virtual hub settings. Detailed information about the virtual hub can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-ptn-virtualhub
  - firewall: (Optional) The firewall settings. Detailed information about the firewall can be found in the Virtual WAN module's README: https://registry.terraform.io/modules/Azure/avm-ptn-virtualhub
  - firewall_policy: (Optional) The firewall policy settings. Detailed information about the firewall policy can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-ptn-firewall-policy
  - private_dns_zones: (Optional) The private DNS zone settings. Detailed information about the private DNS zone can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-ptn-network-private-link-private-dns-zones
  - bastion: (Optional) The bastion host settings. Detailed information about the bastion can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-res-network-bastionhost/
  - virtual_network_gateways: (Optional) The virtual network gateway settings. Detailed information about the virtual network gateway can be found in the Virtual WAN module's README: https://registry.terraform.io/modules/Azure/avm-ptn-virtualhub
  - side_car_virtual_network: (Optional) The side car virtual network settings. Detailed information about the side car virtual network can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork

DESCRIPTION
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "(Optional) Tags of the resource."
}

data "azurerm_client_config" "current" {}

module "config" {
  source           = "github.com/Azure/alz-terraform-accelerator//templates/platform_landing_zone/modules/config-templating"
  enable_telemetry = var.enable_telemetry

  starter_locations               = var.starter_locations
  subscription_id_connectivity    = data.azurerm_client_config.current.subscription_id
  subscription_id_identity        = data.azurerm_client_config.current.subscription_id
  subscription_id_management      = data.azurerm_client_config.current.subscription_id
  root_parent_management_group_id = ""

  custom_replacements = var.custom_replacements

  connectivity_resource_groups = var.connectivity_resource_groups
  virtual_wan_settings         = var.virtual_wan_settings
  virtual_wan_virtual_hubs     = var.virtual_wan_virtual_hubs
  management_resource_settings = var.management_resource_settings
  management_group_settings    = var.management_group_settings
  tags                         = var.tags
}

module "resource_groups" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.2.0"

  for_each = module.config.connectivity_resource_groups

  name             = each.value.name
  location         = each.value.location
  enable_telemetry = false
  tags             = module.config.tags
}

# Build an implicit dependency on the resource groups
locals {
  resource_groups = {
    resource_groups = module.resource_groups
  }
  virtual_wan_settings     = merge(module.config.virtual_wan_settings, local.resource_groups)
  virtual_wan_virtual_hubs = (merge({ hubs = module.config.virtual_wan_virtual_hubs }, local.resource_groups)).hubs
}

# This is the module call
module "test" {
  source = "../../"

  virtual_wan_settings = local.virtual_wan_settings
  virtual_hubs         = local.virtual_wan_virtual_hubs
  enable_telemetry     = false
  tags                 = module.config.tags
}
