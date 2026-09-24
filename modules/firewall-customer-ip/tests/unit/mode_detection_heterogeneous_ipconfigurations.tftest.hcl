mock_provider "modtm" {}
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
}

variables {
  enable_telemetry = false
  name             = "fw-test"
  parent_id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test"
  location         = "eastus"
  virtual_hub_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
  ip_configurations = {
    a = {
      name                 = "ip-a"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-a"
    }
    b = {
      name                 = "ip-b"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-b"
    }
    c = {
      name                 = "ip-c"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-c"
    }
  }
}

# Same-shape regression as modules/firewall/tests/unit/mode_detection_heterogeneous_ipconfigurations.tftest.hcl,
# but exercised directly against this leaf module's own character-identical precondition on
# azapi_resource.this (see the comment on that precondition in main.tf). A pre-existing
# customer-mode firewall's real ipConfigurations response is a heterogeneous, unification-impossible tuple
# (one element carries privateIPAddress as a string, the other omits that key entirely - real ARM
# key-omission, not null). A coalesce()-based check would silently read this genuine
# customer-mode firewall as managed, and this precondition would wrongly reject an ordinary same-mode grow
# (adding a third customer IP).
run "grow_third_customer_ip_on_existing_two_ip_firewall_with_heterogeneous_ipconfigurations" {
  command = plan
  override_data {
    target = data.azapi_resource_list.firewalls
    values = {
      output = {
        firewalls = [{
          name = "FW-TEST"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/FW-TEST"
          properties = {
            ipConfigurations = [
              {
                name = "ip-a"
                properties = {
                  privateIPAddress = "10.224.10.132"
                  publicIPAddress  = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-a" }
                }
              },
              {
                name = "ip-b"
                properties = {
                  # privateIPAddress key intentionally absent (real ARM key-omission, not null) - this is
                  # what makes the tuple unification-impossible when combined with ip-a's string-valued
                  # privateIPAddress above.
                  publicIPAddress = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-b" }
                }
              }
            ]
          }
        }]
      }
    }
  }
  assert {
    condition     = local.existing_firewall != null
    error_message = "This run's own fixture must genuinely resolve the pre-existing firewall by name; otherwise the assertion below would be vacuously true."
  }
}

# Negative control (must stay green): a genuinely managed pre-existing firewall - ipConfigurations
# explicitly null (a legitimate value, not an error) - must still be read as managed and must still
# reject a customer-mode conversion attempt, without erroring anywhere else in the expression.
run "explicit_null_ipconfigurations_still_read_as_managed_without_erroring" {
  command = plan
  override_data {
    target = data.azapi_resource_list.firewalls
    values = {
      output = {
        firewalls = [{
          name = "FW-TEST"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/FW-TEST"
          properties = {
            ipConfigurations = null
            hubIPAddresses   = { publicIPs = { count = 1 } }
          }
        }]
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

# Negative control (must stay green): a genuinely managed pre-existing firewall where the
# ipConfigurations key is entirely absent from the properties object (a distinct shape from explicit
# null, and the actual real-Azure shape for a managed firewall) must also still be read as managed and
# reject a customer-mode conversion attempt, without erroring anywhere else in the expression.
run "absent_ipconfigurations_key_still_read_as_managed_without_erroring" {
  command = plan
  override_data {
    target = data.azapi_resource_list.firewalls
    values = {
      output = {
        firewalls = [{
          name = "FW-TEST"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/FW-TEST"
          properties = {
            hubIPAddresses = { publicIPs = { count = 1 } }
          }
        }]
      }
    }
  }
  expect_failures = [azapi_resource.this]
}
