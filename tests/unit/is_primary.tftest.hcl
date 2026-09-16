# Unit test for the is_primary primary-region selection (Azure/Azure-Landing-Zones#4041).
# Verifies primary_region_key honors an explicit is_primary hub, otherwise falls back
# to the first hub key in alphabetical order, and rejects more than one primary hub.

mock_provider "azapi" {}
mock_provider "azurerm" {}
mock_provider "modtm" {}
mock_provider "random" {}

override_module {
  target = module.regions
  outputs = {
    regions_by_name = {
      southeastasia = {
        zones = ["1", "2", "3"]
      }
      swedencentral = {
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

  # Two hubs where the alphabetically-first key (southeastasia) is not the intended
  # primary region. No is_primary set here to exercise the default behaviour.
  virtual_hubs = {
    southeastasia = {
      location          = "southeastasia"
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
    }
    swedencentral = {
      location          = "swedencentral"
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
    }
  }
}

run "defaults_to_alphabetically_first_hub" {
  command = apply

  assert {
    condition     = local.primary_region_key == "southeastasia"
    error_message = "With no is_primary hub, primary_region_key should fall back to the first hub key in alphabetical order (southeastasia)."
  }
}

run "is_primary_overrides_alphabetical_order" {
  command = apply

  variables {
    virtual_hubs = {
      southeastasia = {
        location          = "southeastasia"
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
      }
      swedencentral = {
        location          = "swedencentral"
        is_primary        = true
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
      }
    }
  }

  assert {
    condition     = local.primary_region_key == "swedencentral"
    error_message = "primary_region_key should be the hub explicitly marked is_primary (swedencentral), not the alphabetically-first key."
  }
}

run "rejects_multiple_primary_hubs" {
  command = plan

  variables {
    virtual_hubs = {
      southeastasia = {
        location          = "southeastasia"
        is_primary        = true
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
      }
      swedencentral = {
        location          = "swedencentral"
        is_primary        = true
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
      }
    }
  }

  expect_failures = [
    var.virtual_hubs,
  ]
}
