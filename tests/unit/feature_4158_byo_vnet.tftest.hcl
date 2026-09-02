# Baseline reproduction for Azure/Azure-Landing-Zones#4158.
# Verifies current behavior when Private DNS auto-registration is enabled
# while the module-managed sidecar virtual network is disabled.

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
        private_dns_zones                     = true
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }

      private_dns_zones = {
        auto_registration_zone_enabled = true
      }
    }
  }
}

run "reproduce_4158_no_sidecar_with_dns_auto_registration" {
  command = plan
}
