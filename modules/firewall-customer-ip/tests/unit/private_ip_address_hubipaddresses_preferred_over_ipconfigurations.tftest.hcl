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
  }
}

# Regression coverage for the private_ip_address branch order itself (not merely each source in isolation):
# properties.hubIPAddresses.privateIPAddress is checked first, for managed-mode/legacy compatibility - this
# must not regress. Both sources are mocked here with genuinely different values, so the assertion actually
# proves precedence, not merely "one source happened to resolve." A real customer-mode firewall was never
# observed to populate hubIPAddresses at all (see real_azure_optional_response_properties.tftest.hcl), so
# this is a mechanical precedence-order test of the code itself, not a claim that both sources are ever
# simultaneously populated with different values on a real firewall.
run "hubipaddresses_private_ip_preferred_over_ipconfigurations_when_both_present" {
  command = apply
  override_resource {
    target = azapi_resource.this
    values = {
      output = {
        properties = {
          additionalProperties = {}
          hubIPAddresses = {
            privateIPAddress = "10.0.0.4"
          }
          ipConfigurations = [{
            name = "internet-primary"
            properties = {
              privateIPAddress = "10.224.8.132"
              publicIPAddress  = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary" }
            }
          }]
        }
      }
    }
  }
  assert {
    condition     = output.private_ip_address == "10.0.0.4"
    error_message = "properties.hubIPAddresses.privateIPAddress must be preferred over properties.ipConfigurations[*].properties.privateIPAddress when both are present - this branch order is for managed-mode/legacy compatibility and must not regress."
  }
}
