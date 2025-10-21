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
  resource_groups = {
    hub_primary = {
      name     = "rg-hub-primary-${random_string.suffix.result}"
      location = "australiaeast"
    }
    hub_secondary = {
      name     = "rg-hub-secondary-${random_string.suffix.result}"
      location = "australiacentral"
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

module "resource_group_vnet_demo_01" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.2.0"

  location         = var.starter_locations[0]
  name             = "rg-vnet-demo-01"
  enable_telemetry = false
  tags             = local.common_tags
}

module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.15.0"

  location      = var.starter_locations[0]
  parent_id     = module.resource_group_vnet_demo_01.resource_id
  address_space = ["10.100.0.0/16"]
  name          = "vnet-demo-01"
  tags          = local.common_tags
}

# This is the module call
module "test" {
  source = "../../"

  enable_telemetry = false
  tags             = local.common_tags
  virtual_hubs = {
    primary = {
      enabled_resources = {
        sidecar_virtual_network               = true
        bastion                               = false
        firewall                              = false
        private_dns_resolver                  = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
      }
      location = local.resource_groups["hub_primary"].location
      # default_hub_address_space = "10.0.0.0/16"
      default_parent_id = module.resource_groups["hub_primary"].resource_id
      virtual_network_connections = {
        vnet_demo_01 = {
          name                      = "vnet-connection-demo-01"
          remote_virtual_network_id = module.virtual_network.resource_id
          internet_security_enabled = true
        }
      }
    }
    secondary = {
      enabled_resources = {
        sidecar_virtual_network               = true
        bastion                               = false
        firewall                              = false
        private_dns_resolver                  = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
      }
      location = local.resource_groups["hub_secondary"].location
      # default_hub_address_space = "10.1.0.0/16"
      default_parent_id = module.resource_groups["hub_secondary"].resource_id
    }
  }
  virtual_wan_settings = {
    enabled_resources = {
      ddos_protection_plan = false
    }
  }
}
