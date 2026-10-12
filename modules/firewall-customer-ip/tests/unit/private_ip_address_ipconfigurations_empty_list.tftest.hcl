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

# Negative case, distinct from private_ip_address_all_missing_named_error.tftest.hcl (which has two
# ipConfigurations elements, neither carrying a private IP): here properties.ipConfigurations is an explicit
# empty list, and properties.hubIPAddresses is also absent. compact() over an empty for-expression is itself
# an empty list, so index [0] fails (caught by the enclosing try(), degrading to null), and the outer
# coalesce(null, null) - which would otherwise raise "no non-null, non-empty-string arguments" - is itself
# wrapped in try(..., null), so this local silently degrades to null rather than erroring here. The named,
# firewall-identifying error must instead come from azapi_resource.this's own postcondition in main.tf.
#
# This is the only run in this file that applies azapi_resource.this, so its override_resource output is
# guaranteed authoritative and not shadowed by state accumulated from an earlier run in the same file (see
# real_azure_optional_response_properties.tftest.hcl for the same convention/rationale).
run "empty_ipconfigurations_list_produces_named_error_not_raw_coalesce_error" {
  command = apply
  override_resource {
    target = azapi_resource.this
    values = {
      output = {
        properties = {
          additionalProperties = {}
          ipConfigurations     = []
        }
      }
    }
  }
  expect_failures = [azapi_resource.this]
}
