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
  parent_id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-single-ip"
  location         = "eastus"
  virtual_hub_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-single-ip/providers/Microsoft.Network/virtualHubs/hub-single-ip"
  ip_configurations = {
    primary = {
      name                 = "customer-owned-ip-config"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-single-ip/providers/Microsoft.Network/publicIPAddresses/pip-single"
    }
  }
}

# Explicit control, deliberately kept in its own file (one apply of azapi_resource.this per file, per this
# suite's convention - see the note at the end of private_ip_address_multi_ip_response_shape.tftest.hcl):
# the ipConfigurations shape Azure returns for a secured-hub firewall with one customer public IP.
# Its single ipConfigurations element trivially carries its own privateIPAddress at index 0 - there is only
# one element, so no ordering/scan question ever arises for this case. This exists side-by-side (as a
# sibling test file, not a combined run) with the multi-IP case in
# private_ip_address_multi_ip_response_shape.tftest.hcl so a reviewer can see the same
# private_ip_address expression resolve correctly on both a single-IP body (nothing to get wrong) and
# a multi-IP body (where index [0] alone would be wrong on a reversed key-omission, per
# private_ip_address_non_first_index.tftest.hcl).
run "single_ip_control_resolves_trivially" {
  command = apply
  override_resource {
    target = azapi_resource.this
    values = {
      output = {
        properties = {
          additionalProperties = {}
          ipConfigurations = [
            {
              id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-single-ip/providers/Microsoft.Network/azureFirewalls/fw-secured-hub/azureFirewallIpConfigurations/customer-owned-ip-config"
              name = "customer-owned-ip-config"
              type = "Microsoft.Network/azureFirewalls/azureFirewallIpConfigurations"
              properties = {
                privateIPAddress          = "10.224.8.132"
                privateIPAllocationMethod = "Dynamic"
                provisioningState         = "Succeeded"
                publicIPAddress           = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-single-ip/providers/Microsoft.Network/publicIPAddresses/pip-single" }
              }
            }
          ]
        }
      }
    }
  }
  assert {
    condition     = output.private_ip_address == "10.224.8.132"
    error_message = "A single-IP customer-mode firewall body must resolve its own (only) privateIPAddress - control case for the multi-IP shape covered in private_ip_address_multi_ip_response_shape.tftest.hcl."
  }
}
