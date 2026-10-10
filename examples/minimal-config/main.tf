terraform {
  required_version = "~> 1.5"

  required_providers {
    # This example declares no azapi_* address of its own; azapi arrives through the
    # module under test. The pin is kept so the example resolves the same provider
    # version the module does. The annotation must be the line IMMEDIATELY above.
    # tflint-ignore: terraform_unused_required_providers
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
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
  version  = "0.4.0"
  for_each = local.resource_groups

  location         = each.value.location
  name             = each.value.name
  enable_telemetry = var.enable_telemetry
  tags             = local.common_tags
}

# This is the module call
module "test" {
  source = "../../"

  enable_telemetry = var.enable_telemetry
  tags             = local.common_tags
  virtual_hubs = {
    primary = {
      location = local.resource_groups["hub_primary"].location
      # default_hub_address_space = "10.0.0.0/16"
      default_parent_id = module.resource_groups["hub_primary"].resource_id
    }
    secondary = {
      location = local.resource_groups["hub_secondary"].location
      # default_hub_address_space = "10.1.0.0/16"
      default_parent_id = module.resource_groups["hub_secondary"].resource_id
    }
  }
}
