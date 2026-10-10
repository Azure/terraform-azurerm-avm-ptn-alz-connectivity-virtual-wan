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
      }
    }
  }
}

# The root builds the per-submodule lists in locals, so these runs assert on those locals.
run "defaults_are_empty" {
  command = plan
  assert {
    condition     = length(local.ignore_body_changes_virtual_wans.network_azure_firewalls.network_azure_firewalls) == 0 && length(local.ignore_body_changes_virtual_wans.network_azure_firewalls.insights_diagnostic_settings) == 0 && length(local.ignore_body_changes_route_maps) == 0
    error_message = "With nothing set, no body path may be ignored."
  }
}

run "explicit_nested_keys_pass_through" {
  command = plan
  variables {
    ignore_body_changes = {
      network_virtual_hubs_route_maps = { network_virtual_hubs_route_maps = ["properties.rules"] }
      network_virtual_wans            = { network_azure_firewalls = { network_azure_firewalls = ["properties.sku"], insights_diagnostic_settings = ["properties.logs"] } }
    }
  }
  assert {
    condition     = local.ignore_body_changes_virtual_wans.network_azure_firewalls.network_azure_firewalls == tolist(["properties.sku"]) && local.ignore_body_changes_virtual_wans.network_azure_firewalls.insights_diagnostic_settings == tolist(["properties.logs"]) && local.ignore_body_changes_route_maps == tolist(["properties.rules"])
    error_message = "The nested keys must reach the submodule lists unchanged when no alias is set."
  }
}

run "deprecated_aliases_alone_populate_the_lists" {
  command = plan
  variables {
    ignore_body_changes = {
      virtual_hubs_firewalls                     = ["tags"]
      virtual_hubs_firewalls_diagnostic_settings = ["properties.logs"]
      virtual_hubs_route_maps                    = { virtual_hubs_route_maps = ["properties.rules"] }
    }
  }
  assert {
    condition     = local.ignore_body_changes_virtual_wans.network_azure_firewalls.network_azure_firewalls == tolist(["tags"]) && local.ignore_body_changes_virtual_wans.network_azure_firewalls.insights_diagnostic_settings == tolist(["properties.logs"]) && local.ignore_body_changes_route_maps == tolist(["properties.rules"])
    error_message = "Each deprecated alias must land in its replacement list."
  }
}

run "aliases_and_nested_keys_merge_without_duplicates" {
  command = plan
  variables {
    ignore_body_changes = {
      virtual_hubs_firewalls          = ["tags", "properties.sku"]
      virtual_hubs_route_maps         = { virtual_hubs_route_maps = ["properties.rules"] }
      network_virtual_hubs_route_maps = { network_virtual_hubs_route_maps = ["properties.rules", "properties.other"] }
      network_virtual_wans            = { network_azure_firewalls = { network_azure_firewalls = ["properties.sku"] } }
    }
  }
  assert {
    condition     = local.ignore_body_changes_virtual_wans.network_azure_firewalls.network_azure_firewalls == tolist(["properties.sku", "tags"]) && local.ignore_body_changes_route_maps == tolist(["properties.rules", "properties.other"])
    error_message = "Nested keys come first, aliases are appended, and a path listed twice appears once."
  }
}

run "alias_rejects_empty_path" {
  command = plan
  variables {
    ignore_body_changes = { virtual_hubs_firewalls = [" "] }
  }
  expect_failures = [var.ignore_body_changes]
}
