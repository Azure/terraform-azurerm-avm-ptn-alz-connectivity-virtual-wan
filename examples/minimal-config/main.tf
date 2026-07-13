terraform {
  required_version = "~> 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.21"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_string" "suffix" {
  length  = 4
  numeric = true
  special = false
  upper   = false
}

locals {
  common_tags = {
    created_by  = "terraform"
    project     = "Azure Landing Zones"
    owner       = "avm"
    environment = "demo"
  }
  minimal_enabled_resources = {
    firewall                              = false
    firewall_policy                       = false
    bastion                               = false
    virtual_network_gateway_express_route = false
    virtual_network_gateway_vpn           = false
    private_dns_zones                     = false
    private_dns_resolver                  = false
    sidecar_virtual_network               = false
  }
  resource_groups = {
    hub_primary = {
      name     = "rg-hub-primary-${random_string.suffix.result}"
      location = "italynorth"
    }
    hub_secondary = {
      name     = "rg-hub-secondary-${random_string.suffix.result}"
      location = "swedencentral"
    }
  }
}

module "resource_groups" {
  source   = "Azure/avm-res-resources-resourcegroup/azurerm"
  version  = "0.2.0"
  for_each = local.resource_groups

  location         = each.value.location
  name             = each.value.name
  enable_telemetry = false
  tags             = local.common_tags
}

# This is the module call
module "test" {
  source = "../../"

  enable_telemetry = false
  tags             = local.common_tags
  virtual_hubs = {
    primary = {
      location = local.resource_groups["hub_primary"].location
      # default_hub_address_space = "10.0.0.0/16"
      default_parent_id = module.resource_groups["hub_primary"].resource_id
      enabled_resources = local.minimal_enabled_resources
    }
    secondary = {
      location = local.resource_groups["hub_secondary"].location
      # default_hub_address_space = "10.1.0.0/16"
      default_parent_id = module.resource_groups["hub_secondary"].resource_id
      enabled_resources = local.minimal_enabled_resources
    }
  }
}
