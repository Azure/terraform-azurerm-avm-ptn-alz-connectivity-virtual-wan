# Regression test for Azure/Azure-Landing-Zones#4277.
# Verifies an imported sidecar VNet keeps its Azure-returned subnets and vWAN-managed peerings.

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar-test"
    }
  }
}

mock_provider "azurerm" {
  mock_resource "azurerm_virtual_wan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
    }
  }

  mock_resource "azurerm_virtual_hub" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
    }
  }

  mock_resource "azurerm_virtual_hub_connection" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubVirtualNetworkConnections/vnet-side-car-hub1"
    }
  }
}

mock_provider "modtm" {}
mock_provider "random" {}

override_module {
  target = module.regions
  outputs = {
    regions_by_name = {
      eastus = {
        zones = ["1", "2", "3"]
      }
    }
  }
}

override_resource {
  target = module.virtual_network_side_car["hub1"].module.subnet["workload"].azapi_resource.subnet[0]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar-test/subnets/snet-workload"
    output = {
      properties = {
        addressPrefixes = ["10.100.1.0/24"]
      }
    }
  }
}

variables {
  enable_telemetry = false
  tags             = {}

  virtual_wan_settings = {
    enabled_resources = {
      ddos_protection_plan = false
    }
    virtual_wan = {
      name                           = "vwan-test"
      allow_branch_to_branch_traffic = true
    }
  }

  virtual_hubs = {
    hub1 = {
      location          = "eastus"
      default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
      enabled_resources = {
        firewall                              = false
        firewall_policy                       = false
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = true
      }
      hub = {
        name           = "vhub-test"
        address_prefix = "10.0.0.0/23"
        sku            = "Standard"
      }
      sidecar_virtual_network = {
        name          = "vnet-sidecar-test"
        address_space = ["10.100.0.0/16"]
        subnets = {
          workload = {
            name             = "snet-workload"
            address_prefixes = ["10.100.1.0/24"]
          }
        }
      }
    }
  }
}

run "seed_imported_sidecar_state" {
  command   = apply
  state_key = "imported_sidecar"

  module {
    source = "./tests/unit/fixtures/imported_sidecar_state"
  }
}

run "first_post_import_plan" {
  command   = plan
  state_key = "imported_sidecar"

  assert {
    condition     = try(jsonencode(module.virtual_network_side_car["hub1"].resource.body.properties.subnets), "") == jsonencode(run.seed_imported_sidecar_state.imported_subnets)
    error_message = "The first B4 plan must preserve the complete Azure-returned parent subnet collection."
  }

  assert {
    condition     = try(jsonencode(module.virtual_network_side_car["hub1"].resource.body.properties.virtualNetworkPeerings), "") == jsonencode(run.seed_imported_sidecar_state.imported_peerings)
    error_message = "The first B4 plan must preserve the complete Azure-managed RemoteVnetToHubPeering collection."
  }

  assert {
    condition = (
      module.virtual_network_side_car["hub1"].resource_id == run.seed_imported_sidecar_state.virtual_network_resource_id &&
      module.virtual_network_side_car["hub1"].subnets["workload"].resource_id == run.seed_imported_sidecar_state.subnet_resource_id
    )
    error_message = "Adopting the imported state must preserve both VNet and independent subnet identities."
  }
}

run "apply_candidate" {
  command   = apply
  state_key = "imported_sidecar"
}

run "unrelated_tag_plan" {
  command   = plan
  state_key = "imported_sidecar"

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        sidecar_virtual_network = merge(var.virtual_hubs.hub1.sidecar_virtual_network, {
          tags = { regression = "after-import" }
        })
      })
    }
  }

  assert {
    condition = (
      try(jsonencode(module.virtual_network_side_car["hub1"].resource.body.properties.subnets), "") == jsonencode(run.seed_imported_sidecar_state.imported_subnets) &&
      try(jsonencode(module.virtual_network_side_car["hub1"].resource.body.properties.virtualNetworkPeerings), "") == jsonencode(run.seed_imported_sidecar_state.imported_peerings) &&
      module.virtual_network_side_car["hub1"].resource.tags.regression == "after-import"
    )
    error_message = "A later tag plan must retain both imported child collections."
  }
}

run "apply_tag_update" {
  command   = apply
  state_key = "imported_sidecar"

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        sidecar_virtual_network = merge(var.virtual_hubs.hub1.sidecar_virtual_network, {
          tags = { regression = "after-import" }
        })
      })
    }
  }
}

run "second_plan_is_idempotent" {
  command   = plan
  state_key = "imported_sidecar"

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        sidecar_virtual_network = merge(var.virtual_hubs.hub1.sidecar_virtual_network, {
          tags = { regression = "after-import" }
        })
      })
    }
  }

  assert {
    condition = (
      try(jsonencode(module.virtual_network_side_car["hub1"].resource.body.properties.subnets), "") == jsonencode(run.seed_imported_sidecar_state.imported_subnets) &&
      try(jsonencode(module.virtual_network_side_car["hub1"].resource.body.properties.virtualNetworkPeerings), "") == jsonencode(run.seed_imported_sidecar_state.imported_peerings) &&
      module.virtual_network_side_car["hub1"].subnets["workload"].resource_id == run.seed_imported_sidecar_state.subnet_resource_id
    )
    error_message = "Subsequent plans must preserve imported collections and the separately managed subnet."
  }
}