# RELEASE QUALIFICATION PROBE (issue #352 offline review) - documents current, DELIBERATE behavior only.
# This is not a defect awaiting a fix; it is the accepted-by-decision outcome of an explicit (a)/(b)
# reconsideration. See the release qualification report, §5A.6, for the full evidence and reasoning.
#
# History: an earlier revision of this module (commit `af77839`) added a client-side precondition check
# for `properties.natGateway.id` alongside the pre-existing `properties.ipConfiguration.id` ownership
# check, after confirming that a NAT-Gateway-attached public IP presents `ipConfiguration = null` while
# `natGateway` is non-null - a shape the original ipConfiguration-only check could not see. That diagnosis
# was and remains correct. The client-side NAT-Gateway check was subsequently REVERTED after the parent
# directly tested the exact previously-unverified path: a live ARM PUT attaching a NAT-Gateway-owned public
# IP as a third ipConfiguration on this module's own live secured-hub Azure Firewall (api-version
# 2024-10-01). Azure rejected it with a synchronous `400 PublicIPAddressInUse` in ~5 seconds, naming the
# exact conflicting `natGateways/...` resource, BEFORE any mutation - the firewall remained `Succeeded` with
# its prior ipConfigurations unchanged, no orphaned config, no partial state.
#
# Because Azure's own rejection on this exact attach path is synchronous, pre-mutation, and names the true
# owner (strictly more informative than anything this module's own check could produce), and because a
# NAT-Gateway-only client-side check would cover just one of several possible non-ipConfiguration
# association surfaces while implying a completeness it does not have, the decision was made NOT to
# reintroduce that client-side check. A public IP already attached to a NAT Gateway (or any other surface
# not reflected in `ipConfiguration`) is an accepted, documented PREREQUISITE the caller must satisfy -
# enforced by Azure's own control plane, not by this module - rather than a client-side-checked condition.
#
# This file therefore asserts the module's current, deliberate ACCEPTANCE of a NAT-Gateway-owned public IP
# at plan/apply time offline (this module cannot make the live Azure call that would reject it), so a
# future change to this precondition is a visible, deliberate decision rather than a silent regression in
# either direction.
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
  ip_configurations = {
    primary = {
      name                 = "internet-primary"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
    }
  }
}

# KNOWN, ACCEPTED-BY-DECISION BEHAVIOR (not a fix candidate): a public IP with `ipConfiguration = null` but
# genuinely owned by a NAT Gateway (which this offline mock cannot represent as distinct from "free", since
# the module no longer reads a `natGateway` field at all) plans and applies successfully offline. The
# real-world backstop for this exact prerequisite is Azure's own synchronous, pre-mutation
# `PublicIPAddressInUse` rejection on this module's actual attach path, verified directly against real
# Azure - not this module's own precondition.
run "current_behavior_accepts_a_fully_detached_looking_public_ip_client_side" {
  command = apply
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address    = "203.0.113.10", allocation_method = "Static", association = null
        ip_version = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones      = ["1", "2", "3"]
      }
    }
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.ipConfigurations) == 1
    error_message = "Current, deliberate behavior (accepted by decision, not a bug): this module does not check NAT Gateway ownership client-side; a public IP that presents ipConfiguration = null is accepted regardless of any other, non-ipConfiguration association it may genuinely have. Azure's own live, synchronous PublicIPAddressInUse rejection on the actual firewall-attach path is the enforced backstop for this prerequisite - see the KNOWN, ACCEPTED-BY-DECISION comment above and the release qualification report §5A.6."
  }
}

# Regression control (must not regress): a public IP already associated with THIS SAME firewall's own IP
# configuration (the reconcile/no-op re-apply case) must still be accepted.
run "accept_reconciliation_of_ip_already_owned_by_this_firewall" {
  command = apply
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address           = "203.0.113.10"
        allocation_method = "Static"
        association       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test/azureFirewallIpConfigurations/internet-primary"
        ip_version        = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones             = ["1", "2", "3"]
      }
    }
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.ipConfigurations) == 1
    error_message = "Idempotent reconciliation of a public IP already attached to this same firewall must not regress."
  }
}

# Regression control (must not regress): a public IP genuinely attached elsewhere via `ipConfiguration`
# (the pre-existing, unrelated, still-enforced check) must still be rejected - only the NAT Gateway-specific
# client-side check was reverted; the ipConfiguration-parent-mismatch check is untouched.
run "reject_ipconfiguration_associated_elsewhere_unchanged" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address     = "203.0.113.10", allocation_method = "Static"
        association = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-other/providers/Microsoft.Network/networkInterfaces/nic-other/ipConfigurations/ipconfig1"
        ip_version  = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones       = ["1", "2", "3"]
      }
    }
  }
  expect_failures = [azapi_resource.this]
}
