terraform {
  required_version = "~> 1.9"

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
  resource_group = {
    name     = "rg-hub-routemap-${random_string.suffix.result}"
    location = "centralus"
  }
  # Three route map definitions, each demonstrating a different rule pattern.
  # None are attached to any connection (associated_inbound/outbound_connections omitted).
  route_maps = {
    add_community = {
      name            = "rtmap-add-community-${random_string.suffix.result}"
      virtual_hub_key = "primary"
      rules = [
        {
          name                 = "add-community-for-spoke-prefixes"
          next_step_if_matched = "Terminate"
          match_criteria = [
            {
              match_condition = "Contains"
              route_prefix    = ["10.1.0.0/16", "10.2.0.0/16"]
            }
          ]
          actions = [
            {
              type = "Add"
              parameters = [
                {
                  community = ["65000:100"]
                }
              ]
            }
          ]
        }
      ]
    }

    drop_prefixes = {
      name            = "rtmap-drop-prefixes-${random_string.suffix.result}"
      virtual_hub_key = "secondary1"
      rules = [
        {
          name                 = "drop-rfc1918-10"
          next_step_if_matched = "Continue"
          match_criteria = [
            {
              match_condition = "Equals"
              route_prefix    = ["10.0.0.0/8"]
            }
          ]
          actions = [
            {
              type = "Drop"
            }
          ]
        },
        {
          name                 = "drop-rfc1918-172"
          next_step_if_matched = "Terminate"
          match_criteria = [
            {
              match_condition = "Equals"
              route_prefix    = ["172.16.0.0/12"]
            }
          ]
          actions = [
            {
              type = "Drop"
            }
          ]
        }
      ]
    }

    replace_aspath = {
      name            = "rtmap-replace-aspath-${random_string.suffix.result}"
      virtual_hub_key = "secondary2"
      rules = [
        {
          name                 = "prepend-aspath-for-community"
          next_step_if_matched = "Terminate"
          match_criteria = [
            {
              match_condition = "Contains"
              community       = ["65000:200"]
            }
          ]
          actions = [
            {
              type = "Replace"
              parameters = [
                {
                  as_path = ["22334", "22334", "22334"]
                }
              ]
            }
          ]
        }
      ]
    }
  }
  secondary1_location = "eastus2"
  secondary2_location = "westus2"
}

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.2.0"

  location         = local.resource_group.location
  name             = local.resource_group.name
  enable_telemetry = false
  tags             = local.common_tags
}

# Deploy a Virtual WAN with a single hub.
# All optional spoke resources are disabled to keep the example focused on route maps.
module "vwan" {
  source = "../../"

  enable_telemetry = false
  route_maps       = local.route_maps
  tags             = local.common_tags
  virtual_hubs = {
    primary = {
      location          = local.resource_group.location
      default_parent_id = module.resource_group.resource_id
      enabled_resources = {
        firewall                              = false
        firewall_policy                       = false
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }
    },
    secondary1 = {
      location          = local.secondary1_location
      default_parent_id = module.resource_group.resource_id
      enabled_resources = {
        firewall                              = false
        firewall_policy                       = false
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }
    },
    secondary2 = {
      location          = local.secondary2_location
      default_parent_id = module.resource_group.resource_id
      enabled_resources = {
        firewall                              = false
        firewall_policy                       = false
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }
    }
  }
}
