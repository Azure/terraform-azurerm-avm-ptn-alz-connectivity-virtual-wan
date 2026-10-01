# Regression test for Azure/Azure-Landing-Zones#358.
# Verifies that a generated firewall policy can use a location different from its hub.

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
      westeurope = {
        zones = ["1", "2", "3"]
      }
    }
  }
}

override_module {
  target = module.firewall_policy
  outputs = {
    resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/firewallPolicies/test"
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
    primary = {
      location          = "eastus"
      default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"

      enabled_resources = {
        firewall                              = true
        firewall_policy                       = true
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }
    }

    secondary = {
      location          = "westeurope"
      default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"

      enabled_resources = {
        firewall                              = true
        firewall_policy                       = true
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }

      firewall_policy = {
        location       = "eastus"
        base_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-policy/providers/Microsoft.Network/firewallPolicies/base-policy"
      }
    }
    tertiary = {
      location          = "westeurope"
      default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"

      enabled_resources = {
        firewall                              = true
        firewall_policy                       = true
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }

      firewall_policy = {
        location = ""
      }
    }
  }
}

run "firewall_policy_location_contract" {
  command = apply

  assert {
    condition     = local.firewall_policies["primary"].location == "eastus"
    error_message = "A firewall policy without an override must use its hub location."
  }

  assert {
    condition     = local.firewall_policies["secondary"].location == "eastus"
    error_message = "An explicit firewall policy location must override the hub location."
  }
  assert {
    condition     = local.firewall_policies["secondary"].base_policy_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-policy/providers/Microsoft.Network/firewallPolicies/base-policy"
    error_message = "base_policy_id must be preserved when an explicit location override is also provided."
  }

  assert {
    condition     = local.firewall_policies["tertiary"].location == "westeurope"
    error_message = "An empty-string firewall policy location must fall back to the hub location."
  }
}