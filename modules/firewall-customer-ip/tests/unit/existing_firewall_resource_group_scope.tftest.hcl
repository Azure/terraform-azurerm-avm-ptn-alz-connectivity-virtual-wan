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
  }
}

# Reproduces the real-Azure mis-resolution the parent measured against subscription 9f5f4d40: two Azure
# Firewalls named identically ("fw-alz352-customer-ip-eastus") existing in two different resource groups
# (the one this module is actually creating/managing, and a wholly unrelated pre-existing firewall
# elsewhere). existing_firewall's pre-fix filter only checks firewall.name, never the resource group, so
# it cannot distinguish "the firewall this apply owns" from "some other firewall that merely shares a
# name" once more than one same-named firewall exists in the subscription-wide response. With two matches
# for the same name, the pre-fix filter yields two elements and one() itself errors, rather than
# transparently picking the correct one - the lookup does not resolve on identity, it happens to work only
# while at most one same-named firewall exists anywhere.
run "resolves_the_firewall_in_its_own_resource_group_not_a_same_named_one_elsewhere" {
  command = plan
  override_data {
    target = data.azapi_resource_list.firewalls
    values = {
      output = {
        firewalls = [
          {
            name = "FW-TEST"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/FW-TEST"
            properties = {
              ipConfigurations = [{
                properties = {
                  privateIPAddress = "10.224.10.132"
                  publicIPAddress  = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-a" }
                }
              }]
            }
          },
          {
            name = "FW-TEST"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-other-unrelated/providers/Microsoft.Network/azureFirewalls/FW-TEST"
            properties = {
              ipConfigurations = null
              hubIPAddresses   = { publicIPs = { count = 1 } }
            }
          }
        ]
      }
    }
  }
  assert {
    condition     = lower(provider::azapi::parse_resource_id("Microsoft.Network/azureFirewalls", local.existing_firewall.id).resource_group_name) == "rg-test"
    error_message = "existing_firewall must resolve to the same-named firewall inside this module's own resource group (var.parent_id), not a same-named firewall living in an unrelated resource group."
  }
}

# The more consequential "silent wrong answer" case (parent's own framing): no firewall of this name
# exists yet in this module's own resource group (a genuine fresh create), but an entirely unrelated
# firewall elsewhere in the subscription happens to share the name and is in MANAGED mode. The pre-fix
# name-only filter finds that one unrelated match, misreads it as "the pre-existing firewall this apply is
# managing", sees it has no customer IP (managed), and wrongly rejects this legitimate customer-mode
# create as an unsupported managed-to-customer conversion - even though, from this resource group's own
# point of view, there is no pre-existing firewall at all.
run "unrelated_same_named_managed_firewall_in_another_resource_group_does_not_block_a_fresh_create" {
  command = plan
  override_data {
    target = data.azapi_resource_list.firewalls
    values = {
      output = {
        firewalls = [{
          name = "FW-TEST"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-other-unrelated/providers/Microsoft.Network/azureFirewalls/FW-TEST"
          properties = {
            ipConfigurations = null
            hubIPAddresses   = { publicIPs = { count = 1 } }
          }
        }]
      }
    }
  }
}

# Regression control (must already pass, and must keep passing): no same-named firewall anywhere in the
# mocked inventory - existing_firewall must resolve to null and the create must proceed, exactly as today.
run "no_same_named_firewall_anywhere_still_short_circuits_to_a_fresh_create" {
  command = plan
  override_data {
    target = data.azapi_resource_list.firewalls
    values = { output = { firewalls = [] } }
  }
  assert {
    condition     = local.existing_firewall == null
    error_message = "With no same-named firewall in the mocked inventory, existing_firewall must resolve to null so a fresh create is never blocked."
  }
}

# Regression control (must already pass, and must keep passing): a genuine incumbent - same name, same
# resource group, managed mode - must still be found and must still correctly reject a real
# managed-to-customer conversion attempt.
run "genuine_same_resource_group_incumbent_still_blocks_a_real_managed_to_customer_conversion" {
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
