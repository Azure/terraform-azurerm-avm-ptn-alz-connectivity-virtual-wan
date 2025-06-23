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

data "azurerm_client_config" "current" {}

module "config" {
  source = "github.com/Azure/alz-terraform-accelerator//templates/platform_landing_zone/modules/config-templating"

  connectivity_resource_groups    = var.connectivity_resource_groups
  custom_replacements             = var.custom_replacements
  enable_telemetry                = var.enable_telemetry
  management_group_settings       = var.management_group_settings
  management_resource_settings    = var.management_resource_settings
  root_parent_management_group_id = ""
  starter_locations               = var.starter_locations
  subscription_id_connectivity    = data.azurerm_client_config.current.subscription_id
  subscription_id_identity        = data.azurerm_client_config.current.subscription_id
  subscription_id_management      = data.azurerm_client_config.current.subscription_id
  tags                            = var.tags
  virtual_wan_settings            = var.virtual_wan_settings
  virtual_wan_virtual_hubs        = var.virtual_wan_virtual_hubs
}

module "resource_groups" {
  source   = "Azure/avm-res-resources-resourcegroup/azurerm"
  version  = "0.2.0"
  for_each = module.config.connectivity_resource_groups

  location         = each.value.location
  name             = each.value.name
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

  enable_telemetry     = false
  tags                 = module.config.tags
  virtual_hubs         = local.virtual_wan_virtual_hubs
  virtual_wan_settings = local.virtual_wan_settings
}

