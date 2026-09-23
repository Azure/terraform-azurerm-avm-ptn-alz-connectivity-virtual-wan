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
  name             = "fw-alz352-customer-ip-eastus"
  parent_id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-alz352-case-m2-eastus"
  location         = "eastus"
  virtual_hub_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-alz352-case-m2-eastus/providers/Microsoft.Network/virtualHubs/hub-alz352-m2-eastus"
  ip_configurations = {
    a = {
      name                 = "ip-a"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-alz352-case-m2-eastus/providers/Microsoft.Network/publicIPAddresses/pip-alz352-m2-a-eastus"
    }
    b = {
      name                 = "ip-b"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-alz352-case-m2-eastus/providers/Microsoft.Network/publicIPAddresses/pip-alz352-m2-b-eastus"
    }
  }
}

# Documentation-flavored regression, verbatim from a real M2 acceptance-case observation reported by the
# parent qualification session (fw-alz352-customer-ip-eastus, rg-alz352-case-m2-eastus, AZFW_Hub/Standard,
# api-version 2024-10-01, one region). This is NOT a new defect-finding test - it is an optional,
# non-required addition that pins the exact real ipConfigurations shape parent measured live, so any future
# regression to this exact observed shape is caught in this test's own isolated file/state:
#
#   ipConfigurations: 2 elements
#   [0] name=ip-a  properties={privateIPAddress=10.224.10.132, privateIPAllocationMethod, provisioningState,
#       publicIPAddress=pip-alz352-m2-a-eastus}
#   [1] name=ip-b  properties={privateIPAllocationMethod, provisioningState, publicIPAddress=pip-alz352-m2-b-eastus}
#       (privateIPAddress KEY ABSENT ENTIRELY - not null - matching the same ARM key-omission behavior
#       already established for hubIPAddresses/zones/PIP association keys)
#
# In this real observation the address-bearing element (ip-a) is at index 0, so the pre-fix defect was
# latent here, not actively triggered - this test intentionally reproduces that exact ordering (address at
# index 0) as its own case, distinct from private_ip_address_non_first_index.tftest.hcl (which covers the
# reverse, address at a later index, using non-M2 generic names). Azure's array-ordering behavior is not
# asserted in either direction by this test or by citing it - only the verbatim observed shape is pinned.
run "resolves_private_ip_matching_the_real_m2_live_observation_verbatim" {
  command = apply
  override_resource {
    target = azapi_resource.this
    values = {
      output = {
        properties = {
          additionalProperties = {}
          ipConfigurations = [
            {
              id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-alz352-case-m2-eastus/providers/Microsoft.Network/azureFirewalls/fw-alz352-customer-ip-eastus/azureFirewallIpConfigurations/ip-a"
              name = "ip-a"
              type = "Microsoft.Network/azureFirewalls/azureFirewallIpConfigurations"
              properties = {
                privateIPAddress          = "10.224.10.132"
                privateIPAllocationMethod = "Dynamic"
                provisioningState         = "Succeeded"
                publicIPAddress           = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-alz352-case-m2-eastus/providers/Microsoft.Network/publicIPAddresses/pip-alz352-m2-a-eastus" }
              }
            },
            {
              id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-alz352-case-m2-eastus/providers/Microsoft.Network/azureFirewalls/fw-alz352-customer-ip-eastus/azureFirewallIpConfigurations/ip-b"
              name = "ip-b"
              type = "Microsoft.Network/azureFirewalls/azureFirewallIpConfigurations"
              properties = {
                # privateIPAddress key is intentionally absent here, matching the real observation exactly
                # (key omitted, not set to null).
                privateIPAllocationMethod = "Dynamic"
                provisioningState         = "Succeeded"
                publicIPAddress           = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-alz352-case-m2-eastus/providers/Microsoft.Network/publicIPAddresses/pip-alz352-m2-b-eastus" }
              }
            }
          ]
        }
      }
    }
  }
  assert {
    condition     = output.private_ip_address == "10.224.10.132"
    error_message = "Must resolve the private IP address exactly as observed live for the real M2 acceptance case (fw-alz352-customer-ip-eastus): ip-a carries privateIPAddress, ip-b omits the key entirely."
  }
}

# NOTE: the real single-IP control (rg-alz352-hub-eastus/customer-owned-ip-config) is deliberately kept in
# its own separate file (private_ip_address_m2_live_observation_single_ip_control.tftest.hcl), not appended
# here as a second `apply` run - this suite's tests/unit convention is one `apply` of azapi_resource.this
# per file, because a later run's override_resource in the same file was observed to leak a stale value
# from an earlier run's override rather than genuinely replacing it (see that file's own header comment
# and the tftest state-leakage note in this session's qualification report).
