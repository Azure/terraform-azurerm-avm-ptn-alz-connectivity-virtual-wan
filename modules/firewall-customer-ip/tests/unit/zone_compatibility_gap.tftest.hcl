# RELEASE QUALIFICATION PROBE (issue #352 offline review) - documents current behavior only.
#
# The only zone-related precondition on azapi_resource.this (see main.tf) is:
#
#   condition = length(coalesce(var.zones, [])) == 0 ? true : alltrue([
#     for ip in data.azapi_resource.public_ips : length(try(coalesce(ip.output.zones, []), [])) > 0
#   ])
#
# This checks only that each customer public IP has a NON-EMPTY zones list whenever the firewall is
# zone-redundant (var.zones non-empty). It never compares the IP's actual zone SET against var.zones. A
# firewall configured with zones = ["1", "2", "3"] therefore currently accepts a customer public IP whose
# zones are only ["1"], or even a disjoint set such as ["2"], as long as the list is non-empty.
#
# This test deliberately does NOT assert that Azure itself would accept a mismatched/disjoint zone set at
# apply time - that is a live-Azure question this offline suite cannot answer. It only pins down and
# documents the module's own current plan/apply-time acceptance behavior so a future change to the
# precondition is a visible, deliberate decision instead of a silent regression.
#
# LIVE-AZURE ANSWER, measured 2026-09-22 (centralindia, api-version 2024-10-01):
# Azure REJECTS the mismatch this module accepts. A direct ARM PUT attaching a public IP zoned ["1"] to a
# firewall zoned ["1","2","3"] returned:
#
#   400 AzureFirewallZoneConstraintDoesNotMatchPublicIpAddressZoneConstraint
#   "Azure Firewall <fw> has zone constraint 1, 2, 3, but Public IP <pip> referenced by the azure firewall
#    has a different zone constraint 1"
#
# So the documented gap has a real consequence: the module accepts this configuration at plan time and the
# user hits a named ARM failure roughly ten minutes into the apply.
#
# The precondition was NOT tightened to set equality, deliberately. Only ONE direction was tested:
#   firewall ["1","2","3"] + IP ["1"]     -> REJECTED   (measured)
#   firewall ["1"] + IP ["1","2","3"]     -> UNTESTED
# The ARM message reads like exact equality, but that is an interpretation of a string, not a result. If
# the real rule is firewall-zones subset-of IP-zones, equality would falsely reject a configuration Azure
# accepts - a worse defect than the late failure it would fix, since a false plan-time rejection has no
# override. Settling it needs the reverse-direction test: a firewall zoned ["1"] with a ["1","2","3"] IP.
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
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
      output = {
        properties = {
          hubIPAddresses = { privateIPAddress = "10.0.0.4" }, threatIntelMode = null, additionalProperties = {}
        }
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
  zones            = [1, 2, 3]
  ip_configurations = {
    primary = {
      name                 = "internet-primary"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
    }
  }
}

# KNOWN GAP (documented, not fixed here): a fully zone-redundant firewall (zones ["1","2","3"]) is currently
# accepted with a customer public IP configured in only a single, matching-looking zone subset (["1"]). The
# module has no code path that would reject this; the precondition above only checks non-emptiness.
run "current_behavior_accepts_single_zone_subset_on_zone_redundant_firewall" {
  command = apply
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address    = "203.0.113.10", allocation_method = "Static", association = null
        ip_version = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones      = ["1"]
      }
    }
  }
  assert {
    condition     = azapi_resource.this.body.zones == tolist(["1", "2", "3"])
    error_message = "The firewall's own requested zones must remain the caller's full zone-redundant set."
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.ipConfigurations) == 1
    error_message = "Current behavior (documented gap, not a fix): the module accepts a customer public IP whose zones ([\"1\"]) are a strict, non-matching subset of the firewall's zones ([\"1\",\"2\",\"3\"]) instead of rejecting the mismatch. Only zone-list emptiness is validated, not zone-SET compatibility. See the KNOWN GAP comment at the top of this file and the release qualification report for the proposed bounded fix."
  }
}

# Same documented gap, with a fully DISJOINT zone set (no overlap at all with the firewall's zones).
run "current_behavior_accepts_disjoint_zone_set_on_zone_redundant_firewall" {
  command = apply
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address    = "203.0.113.10", allocation_method = "Static", association = null
        ip_version = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones      = ["2"]
      }
    }
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.ipConfigurations) == 1
    error_message = "Current behavior (documented gap, not a fix): the module accepts a customer public IP whose zones ([\"2\"]) are non-empty but never validated for overlap/equality against the firewall's zones ([\"1\",\"2\",\"3\"]). See the KNOWN GAP comment at the top of this file."
  }
}
