mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = { subscription_id = "00000000-0000-0000-0000-000000000001" }
  }
  mock_data "azapi_resource_list" {
    defaults = { output = { firewalls = [] } }
  }
  mock_data "azapi_resource" {
    defaults = {
      output = {
        address        = "203.0.113.10", allocation_method = "Static", association = null
        ip_version     = "IPv4", location = "eastus", sku = "Standard", tier = "Regional", type = "Standard"
        virtual_wan_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/wan-test"
        zones          = ["1", "2", "3"]
      }
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
      output = {
        properties = {
          hubIPAddresses = { privateIPAddress = "10.0.0.4" }, threatIntelMode = null, additionalProperties = {}
        }
      }
    }
  }
}

override_resource {
  target = module.virtual_wan[0].module.virtual_hubs.azapi_resource.this["hub"]
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test" }
}
override_resource {
  target = module.virtual_wan[0].azapi_resource.virtual_wan[0]
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/wan-test" }
}

override_module {
  target  = module.regions
  outputs = { regions_by_name = { eastus = { zones = ["1", "2", "3"] } } }
}

variables {
  enable_telemetry     = false
  virtual_wan_settings = { enabled_resources = { ddos_protection_plan = false } }
}

run "customer_default" {
  command = apply
  variables {

    virtual_hubs = {
      hub = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test"
        enabled_resources = {
          firewall                              = true, firewall_policy = false, bastion = false
          virtual_network_gateway_express_route = false, virtual_network_gateway_vpn = false
          private_dns_zones                     = false, private_dns_resolver = false, sidecar_virtual_network = false
        }
        firewall = {
          name               = "fw-test"
          firewall_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/firewallPolicies/policy-test"
          ip_configurations = {
            primary = {
              name                 = "explicit-primary"
              public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
            }
          }
        }

      }
    }
  }
  assert {
    condition     = var.enable_telemetry == false
    error_message = "x"
  }
}

run "customer_explicit" {
  command = apply
  variables {
    retry    = { error_message_regex = ["CallerRegex"], interval_seconds = 3, max_interval_seconds = 30 }
    timeouts = { create = "11m", delete = "13m" }
    virtual_hubs = {
      hub = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test"
        enabled_resources = {
          firewall                              = true, firewall_policy = false, bastion = false
          virtual_network_gateway_express_route = false, virtual_network_gateway_vpn = false
          private_dns_zones                     = false, private_dns_resolver = false, sidecar_virtual_network = false
        }
        firewall = {
          name               = "fw-test"
          firewall_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/firewallPolicies/policy-test"
          ip_configurations = {
            primary = {
              name                 = "explicit-primary"
              public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
            }
          }
        }

      }
    }
  }
  assert {
    condition     = var.enable_telemetry == false
    error_message = "x"
  }
}
