mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = { output = { firewalls = [], results = [] } }
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
    secondary = {
      name                 = "internet-secondary"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-secondary"
    }
  }
}

# Negative case: index 0's privateIPAddress is present but an empty string (a distinct real-Azure shape from
# a genuinely absent key), and index 1 carries the real address. An empty string must be treated as absent
# (compact() drops it), not accepted as a valid-but-empty address, and must not itself trigger the raw
# `coalesce` failure that empty strings are documented to cause identically to null (Terraform's `coalesce`
# treats null and "" the same way).
run "empty_string_private_ip_address_treated_as_absent" {
  command = apply
  override_resource {
    target = azapi_resource.this
    values = {
      output = {
        properties = {
          additionalProperties = {}
          ipConfigurations = [
            {
              name = "internet-primary"
              properties = {
                privateIPAddress = ""
                publicIPAddress  = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary" }
              }
            },
            {
              name = "internet-secondary"
              properties = {
                privateIPAddress = "10.224.8.140"
                publicIPAddress  = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-secondary" }
              }
            }
          ]
        }
      }
    }
  }
  assert {
    condition     = output.private_ip_address == "10.224.8.140"
    error_message = "An empty-string privateIPAddress must be treated the same as an absent one, not accepted as a valid (empty) address, and must not itself trigger the raw coalesce failure."
  }
}
