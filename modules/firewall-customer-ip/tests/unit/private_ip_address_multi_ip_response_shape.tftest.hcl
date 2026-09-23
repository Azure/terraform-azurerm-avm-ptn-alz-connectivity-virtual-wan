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
  name             = "fw-secured-hub"
  parent_id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip"
  location         = "eastus"
  virtual_hub_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/virtualHubs/hub-multi-ip"
  ip_configurations = {
    a = {
      name                 = "ip-a"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/publicIPAddresses/pip-multi-a"
    }
    b = {
      name                 = "ip-b"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/publicIPAddresses/pip-multi-b"
    }
  }
}

# Pins the ipConfigurations shape Azure returns for a secured-hub firewall with two customer public IPs
# (AZFW_Hub/Standard, api-version 2024-10-01), so a regression to this exact shape is caught in this
# test's own isolated file/state:
#
#   ipConfigurations: 2 elements
#   [0] name=ip-a  properties={privateIPAddress=10.224.10.132, privateIPAllocationMethod, provisioningState,
#       publicIPAddress=pip-multi-a}
#   [1] name=ip-b  properties={privateIPAllocationMethod, provisioningState, publicIPAddress=pip-multi-b}
#       (privateIPAddress KEY ABSENT ENTIRELY - not null - matching the same ARM key-omission behavior
#       already established for hubIPAddresses/zones/PIP association keys)
#
# Here the address-bearing element (ip-a) is at index 0. This is kept as its own case, distinct from
# private_ip_address_non_first_index.tftest.hcl, which covers the reverse (address at a later index).
# Azure's array-ordering behavior is not asserted in either direction by either test.
run "resolves_private_ip_from_multi_ip_response_shape" {
  command = apply
  override_resource {
    target = azapi_resource.this
    values = {
      output = {
        properties = {
          additionalProperties = {}
          ipConfigurations = [
            {
              id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/azureFirewalls/fw-secured-hub/azureFirewallIpConfigurations/ip-a"
              name = "ip-a"
              type = "Microsoft.Network/azureFirewalls/azureFirewallIpConfigurations"
              properties = {
                privateIPAddress          = "10.224.10.132"
                privateIPAllocationMethod = "Dynamic"
                provisioningState         = "Succeeded"
                publicIPAddress           = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/publicIPAddresses/pip-multi-a" }
              }
            },
            {
              id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/azureFirewalls/fw-secured-hub/azureFirewallIpConfigurations/ip-b"
              name = "ip-b"
              type = "Microsoft.Network/azureFirewalls/azureFirewallIpConfigurations"
              properties = {
                # privateIPAddress key is intentionally absent here, matching the Azure response exactly
                # (key omitted, not set to null).
                privateIPAllocationMethod = "Dynamic"
                provisioningState         = "Succeeded"
                publicIPAddress           = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/publicIPAddresses/pip-multi-b" }
              }
            }
          ]
        }
      }
    }
  }
  assert {
    condition     = output.private_ip_address == "10.224.10.132"
    error_message = "Must resolve the private IP address from the multi-IP response shape: ip-a carries privateIPAddress, ip-b omits the key entirely."
  }
}

# NOTE: the single-IP control is deliberately kept in its own separate file
# (private_ip_address_single_ip_response_shape.tftest.hcl), not appended here as a second `apply` run -
# this suite's tests/unit convention is one `apply` of azapi_resource.this per file, because a later run's
# override_resource in the same file was observed to leak a stale value from an earlier run's override
# rather than genuinely replacing it.
