mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = { subscription_id = "00000000-0000-0000-0000-000000000001" }
  }
  mock_resource "azurerm_virtual_hub" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-fresh/providers/Microsoft.Network/virtualHubs/hub-fresh" }
  }
  mock_resource "azurerm_virtual_wan" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-fresh/providers/Microsoft.Network/virtualWans/wan-fresh" }
  }
}
mock_provider "azapi" {
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
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-fresh/providers/Microsoft.Network/azureFirewalls/fw-fresh"
      output = {
        properties = {
          hubIPAddresses = { privateIPAddress = "10.0.0.4" }, threatIntelMode = null, additionalProperties = {}
        }
      }
    }
  }
}

override_module {
  target  = module.virtual_wan.module.regions
  outputs = { regions_by_name = { eastus = { zones = ["1", "2", "3"] } } }
}
override_resource {
  target = module.resource_groups.azapi_resource.this
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-fresh" }
}
override_resource {
  target = azapi_resource.public_ips["primary"]
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-fresh/providers/Microsoft.Network/publicIPAddresses/pip-primary" }
}
override_resource {
  target = azapi_resource.public_ips["secondary"]
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-fresh/providers/Microsoft.Network/publicIPAddresses/pip-secondary" }
}

run "fresh_rg_and_unknown_ids_plan" {
  command = plan
  module {
    source = "./tests/unit/fixtures/firewall-root"
  }
  assert {
    condition     = length(output.firewall_public_ip_addresses["hub"]) == 2
    error_message = "A fresh RG with the Accelerator's merged dependency and unknown PIP/hub IDs must remain plannable."
  }
}

run "fresh_rg_and_unknown_ids_apply_mocked" {
  command = apply
  module {
    source = "./tests/unit/fixtures/firewall-root"
  }
  assert {
    condition     = length(output.firewall_public_ip_addresses["hub"]) == 2 && output.public_ip_ids["primary"] != output.public_ip_ids["secondary"]
    error_message = "Both caller-owned computed IDs must survive every typed boundary and reach the customer firewall."
  }
}

run "disable_firewall_keeps_caller_owned_ips" {
  command = apply
  module {
    source = "./tests/unit/fixtures/firewall-root"
  }
  variables {
    firewall_enabled = false
  }
  assert {
    condition     = output.firewall_public_ip_addresses == {} && output.public_ip_ids == run.fresh_rg_and_unknown_ids_apply_mocked.public_ip_ids
    error_message = "Disabling the firewall must leave the caller-owned public IP resources in place."
  }
}
