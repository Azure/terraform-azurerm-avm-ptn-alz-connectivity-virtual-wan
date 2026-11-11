mock_provider "random" {}

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
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
      output = {
        properties = {
          hubIPAddresses = { privateIPAddress = "10.0.0.4" }, threatIntelMode = null, additionalProperties = {}
        }
      }
    }
  }
  mock_data "azapi_client_config" {
    defaults = {
      subscription_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  enable_telemetry = false
  name             = "fw-test"
  parent_id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test"
  location         = "eastus"
  virtual_hub_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
  ip_configurations = {
    primary = {
      name                 = "internet-primary"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
    }
  }
}

run "pins_sorted_null_safe_zones_replacement_trigger_and_sorted_body" {
  command = plan

  variables {
    zones = [3, 1, 2]
  }

  assert {
    condition     = jsonencode(azapi_resource.this.body.zones) == jsonencode(["1", "2", "3"])
    error_message = "The request body must send the configured zones in sorted order."
  }
  assert {
    condition     = contains(azapi_resource.this.replace_triggers_refs, "sort(zones || `[]`)")
    error_message = "The zones replacement trigger must compare the sorted zone set, treating missing zones as empty, so Azure returning the same zones in another order does not replace the firewall."
  }
  assert {
    condition     = contains(azapi_resource.this.replace_triggers_refs, "properties.sku.name")
    error_message = "The SKU name must remain a replacement trigger."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "non_zonal_firewall_sends_empty_zones" {
  command = plan

  variables {
    zones = []
  }
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address           = "203.0.113.10"
        allocation_method = "Static"
        association       = null
        ip_version        = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones             = []
      }
    }
  }

  assert {
    condition     = length(azapi_resource.this.body.zones) == 0
    error_message = "A non-zonal firewall must send an empty zones list, which the replacement trigger treats the same as missing zones."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}
