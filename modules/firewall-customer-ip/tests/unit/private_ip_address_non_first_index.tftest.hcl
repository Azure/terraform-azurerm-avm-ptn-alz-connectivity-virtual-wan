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

# Guards against assuming the private IP address is on properties.ipConfigurations[0]. Azure GETs for a
# multi-ipConfiguration firewall (api-version 2024-10-01) report privateIPAddress on exactly one element
# and omit the key entirely (not null) on the others, and nothing guarantees that element is at index 0.
# This test does not assert how Azure orders the elements; it proves the module does not depend on order.
# An index-0-only lookup would not degrade to null when index 0 lacks privateIPAddress but a later index
# has it - it would hard-fail with an opaque
# `Call to function "coalesce" failed: no non-null, non-empty-string arguments.` error naming neither the
# firewall nor the cause, even though the private IP address is genuinely available at another index.
#
# This is the only run in this file that applies azapi_resource.this, so its override_resource output is
# guaranteed authoritative and not shadowed by state accumulated from an earlier run in the same file (see
# real_azure_optional_response_properties.tftest.hcl for the same convention/rationale).
#
# The module searches every ipConfiguration, not only index 0, so this run must resolve the address from
# ipConfigurations[1].
run "resolves_private_ip_from_non_first_ip_configuration" {
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
                # index 0 genuinely lacks a private IP in this Azure response shape (key absent).
                publicIPAddress = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary" }
              }
            },
            {
              name = "internet-secondary"
              properties = {
                privateIPAddress = "10.224.8.133"
                publicIPAddress  = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-secondary" }
              }
            }
          ]
        }
      }
    }
  }
  assert {
    condition     = output.private_ip_address == "10.224.8.133"
    error_message = "The private IP address is genuinely present on a later ipConfiguration element; a hardcoded index-0 lookup must not hard-fail or silently miss it."
  }
}
