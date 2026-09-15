# Validation test for Azure/Azure-Landing-Zones#4158.
# Verifies that a BYO Sidecar VNet ID must reference Microsoft.Network/virtualNetworks.

mock_provider "azapi" {}
mock_provider "azurerm" {}
mock_provider "modtm" {}
mock_provider "random" {}

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

      sidecar_virtual_network = {
        resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/not-a-vnet"
      }

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

run "reject_invalid_byo_vnet_resource_id" {
  command = plan

  expect_failures = [
    var.virtual_hubs
  ]
}
