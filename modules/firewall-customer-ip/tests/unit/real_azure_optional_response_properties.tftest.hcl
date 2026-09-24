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

# Regression coverage for real-Azure findings on a Secured Virtual Hub firewall's GET response: it commonly
# leaves properties.hubIPAddresses.privateIPAddress absent entirely even after a successful create (the
# private address is always present per-ipConfiguration instead), and it omits properties.threatIntelMode
# entirely too, since this module intentionally never sets it in the request body (see main.tf). This is the
# first (and only) apply against azapi_resource.this in this file, so the override_resource output below is
# guaranteed to be authoritative and not shadowed by state accumulated from an earlier run.
run "resolve_outputs_when_azure_omits_optional_response_properties" {
  command = apply
  override_resource {
    target = azapi_resource.this
    values = {
      output = {
        properties = {
          additionalProperties = {}
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
    condition     = output.private_ip_address == "10.224.8.132"
    error_message = "Real Azure GETs for a Secured Virtual Hub firewall commonly omit properties.hubIPAddresses entirely; the private IP must still resolve from properties.ipConfigurations."
  }
  assert {
    condition     = output.legacy_resource.threat_intel_mode == null
    error_message = "threatIntelMode is never set on this AZFW_Hub firewall, and real Azure omits it from the response entirely; the legacy compatibility output must degrade to null, not error."
  }
}
