# Documents current, deliberate behavior: this module does not check NAT Gateway ownership client-side.
#
# A NAT-Gateway-attached public IP presents `ipConfiguration = null` while `natGateway` is non-null, a
# shape the `ipConfiguration`-based ownership check in main.tf cannot see. A client-side `natGateway`
# check is deliberately not implemented: Azure rejects attaching a NAT-Gateway-owned public IP to a
# secured-hub Azure Firewall (api-version 2024-10-01) synchronously and before any mutation, with
# `400 PublicIPAddressInUse` naming the conflicting `natGateways/...` resource. The firewall remains
# `Succeeded` with its existing ipConfigurations unchanged.
#
# Azure's rejection names the true owner, so it is more informative than anything this module's own
# check could produce, and a NAT-Gateway-only check would cover just one of several possible
# non-ipConfiguration association surfaces while implying a completeness it does not have. A public IP
# that is not attached elsewhere is therefore a documented prerequisite the caller must satisfy, enforced
# by Azure's own control plane rather than by this module.
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

# Deliberate behavior: a public IP with `ipConfiguration = null` but genuinely owned by a NAT Gateway
# (which this offline mock cannot represent as distinct from "free", since the module does not read a
# `natGateway` field) plans and applies successfully offline. The backstop for this prerequisite is
# Azure's own synchronous, pre-mutation `PublicIPAddressInUse` rejection on the firewall-attach path, not
# this module's own precondition.
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
    error_message = "Deliberate behavior: this module does not check NAT Gateway ownership client-side; a public IP that presents ipConfiguration = null is accepted regardless of any other, non-ipConfiguration association it may genuinely have. Azure's own synchronous PublicIPAddressInUse rejection on the firewall-attach path is the enforced backstop for this prerequisite - see the comment at the top of this file."
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
# must still be rejected - the ipConfiguration-parent-mismatch check is enforced independently of the NAT
# Gateway decision above.
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
