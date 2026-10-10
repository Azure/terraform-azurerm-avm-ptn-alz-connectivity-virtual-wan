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

# Terraform tests cannot read resources inside nested modules, so this file checks what the root
# itself decides: the defaults kept for its own children and the null it hands the Virtual WAN
# submodule. The leaf modules' own tests prove that a value reaching them is honoured.
run "unset_inputs_keep_root_defaults_and_cascade_null" {
  command = apply
  assert {
    condition     = local.timeouts == { create = "60m", read = "5m", update = "60m", delete = "60m" }
    error_message = "The root's own children must keep the published 60m/5m/60m/60m timeouts."
  }
  assert {
    condition     = local.retry.error_message_regex == tolist(["ReferencedResourceNotProvisioned", "UpdateGatewayInProgress", "CannotDeleteVirtualHubWhenItIsInUse", "InUseVirtualWanCannotBeDeleted"]) && local.retry.interval_seconds == 10 && local.retry.max_interval_seconds == 180
    error_message = "The root's own children must keep the published four-regex retry."
  }
  assert {
    condition     = var.timeouts.create == null && var.timeouts.delete == null && var.retry.error_message_regex == null
    error_message = "What cascades to the Virtual WAN submodule must stay null so its per-resource defaults, such as 90m for a firewall, apply."
  }
}

run "explicit_inputs_replace_root_defaults" {
  command = apply
  variables {
    retry    = { error_message_regex = ["CallerRegex"], interval_seconds = 3, max_interval_seconds = 30 }
    timeouts = { create = "11m", delete = "13m" }
  }
  assert {
    condition     = local.timeouts == { create = "11m", read = "5m", update = "60m", delete = "13m" } && local.retry.error_message_regex == tolist(["CallerRegex"]) && local.retry.interval_seconds == 3
    error_message = "Caller values must override the root defaults attribute by attribute."
  }
}
