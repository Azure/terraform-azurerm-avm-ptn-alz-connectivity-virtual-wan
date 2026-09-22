terraform {
  required_version = "~> 1.9"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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
  base_policy_name   = "afwp-base-${random_string.suffix.result}"
  primary_location   = "italynorth"
  secondary_location = "swedencentral"
  common_tags = {
    created_by  = "terraform"
    environment = "test"
    project     = "Azure Landing Zones"
  }
  resource_groups = {
    hub_primary = {
      name     = "rg-hub-primary-${random_string.suffix.result}"
      location = local.primary_location
    }
    hub_secondary = {
      name     = "rg-hub-secondary-${random_string.suffix.result}"
      location = local.secondary_location
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

# The module under test does not create parent firewall policies, so the
# shared base policy is provisioned directly with AzAPI, per repository
# convention for direct Azure dependencies outside the module under test.
resource "azapi_resource" "base_policy" {
  location  = local.primary_location
  name      = local.base_policy_name
  parent_id = module.resource_groups["hub_primary"].resource_id
  type      = "Microsoft.Network/firewallPolicies@2024-07-01"
  body = {
    properties = {
      sku = {
        tier = "Standard"
      }
    }
  }
  response_export_values = ["id"]
}

# This is the module call.
module "test" {
  source = "../../"

  enable_telemetry = false
  tags             = local.common_tags
  virtual_hubs = {
    primary = {
      location          = local.primary_location
      default_parent_id = module.resource_groups["hub_primary"].resource_id

      firewall_policy = {
        base_policy_id = azapi_resource.base_policy.output.id
      }
    }
    # The hub and its firewall stay in a different region from the shared
    # base policy. Azure requires a child firewall policy to reside in the
    # same region as its parent, so firewall_policy.location overrides the
    # policy's region without moving the hub or the firewall.
    secondary = {
      location          = local.secondary_location
      default_parent_id = module.resource_groups["hub_secondary"].resource_id

      firewall_policy = {
        location       = local.primary_location
        base_policy_id = azapi_resource.base_policy.output.id
      }
    }
  }
}
