# Regression test for Azure/Azure-Landing-Zones#4158.
# Verifies the existing module-created Sidecar VNet path still works when no BYO VNet ID is supplied.

mock_provider "azapi" {}
mock_provider "azurerm" {}
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

override_module {
  target = module.virtual_network_side_car
  outputs = {
    resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-created-sidecar"
    subnets     = {}
  }
}

override_module {
  target = module.virtual_wan
}

variables {
  enable_telemetry = false

  virtual_wan_settings = {
    enabled_resources = {
      ddos_protection_plan = false
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
    }
  }
}

run "created_sidecar_path_remains_supported" {
  command = plan

  assert {
    condition     = local.sidecar_virtual_networks_create["hub1"] == true
    error_message = "The module should create the Sidecar VNet when no BYO VNet resource ID is supplied."
  }

  assert {
    condition     = local.sidecar_virtual_network_resource_ids["hub1"] == module.virtual_network_side_car["hub1"].resource_id
    error_message = "The effective Sidecar VNet ID should come from the module-created VNet when no BYO VNet ID is supplied."
  }

  assert {
    condition     = output.sidecar_virtual_network_resource_ids["hub1"] == module.virtual_network_side_car["hub1"].resource_id
    error_message = "The Sidecar VNet output should return the module-created VNet ID."
  }
}
