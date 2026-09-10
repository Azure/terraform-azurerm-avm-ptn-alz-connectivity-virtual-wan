# Regression test for Azure/Azure-Landing-Zones#4092.
# Verifies the root input type and flattening logic retain dpd_timeout_seconds.

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
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }

      vpn_site_connections = {
        connection1 = {
          name                = "connection1"
          remote_vpn_site_key = "hub1-site1"
          vpn_links = [
            {
              name                 = "link1"
              vpn_site_key         = "hub1-site1"
              vpn_site_link_number = 0
              dpd_timeout_seconds  = 30
            }
          ]
        }
      }
    }
  }
}

run "root_input_retains_dpd_timeout_seconds" {
  command = apply

  assert {
    condition     = local.vpn_site_connections["hub1-connection1"].vpn_links[0].dpd_timeout_seconds == 30
    error_message = "The root vpn_site_connections input discarded dpd_timeout_seconds before forwarding it to the Virtual WAN module."
  }
}
