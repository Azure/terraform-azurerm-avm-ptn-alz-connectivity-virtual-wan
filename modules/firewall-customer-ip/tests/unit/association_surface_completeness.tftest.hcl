# These runs pin down that the ownership precondition in main.tf is generic across association surfaces,
# not specific to network interfaces. They are independent of the NAT Gateway decision documented in
# nat_gateway_ownership_gap.tftest.hcl.
#
# Per Microsoft.Network/publicIPAddresses@2024-10-01 (this module's default API version - see variables.tf
# and the ARM template reference at learn.microsoft.com/azure/templates/microsoft.network/2024-10-01/
# publicipaddresses), `PublicIPAddressPropertiesFormat` exposes exactly two top-level properties that
# indicate the IP is attached to another Azure resource:
#   - `ipConfiguration` (response-only; a `{id: string}` reference) - populated identically regardless of
#     which *type* of resource owns the referenced IP configuration: a network interface, a Load Balancer
#     frontend IP configuration, an Application Gateway frontend IP configuration, a VPN/ExpressRoute
#     Gateway IP configuration, an Azure Bastion IP configuration, a Route Server IP configuration, or a
#     NIC-attached API Management/VMSS instance. Azure does not expose a distinct field per consumer type;
#     they all funnel through this single, generic reference. This module checks this field.
#   - `natGateway` (a `{id: string}` reference) - the one consumer type that does NOT use an IP
#     configuration. This module deliberately does NOT check this field client-side (see
#     nat_gateway_ownership_gap.tftest.hcl for the reasoning); Azure's own synchronous rejection on the
#     firewall-attach path is the enforced backstop for that prerequisite instead.
# There is no separate `natRule`/`natRules` or `loadBalancerBackendAddressPools` property directly on this
# resource at this API version - confirmed via the same ARM template reference.
#
# Because `main.tf`'s ownership precondition already rejects ANY non-null `ipConfiguration` that does not
# parse as *this exact firewall's* own ipConfiguration (see `local.public_ip_association_parents` in
# locals.tf, and the pre-existing `reject_non_firewall_association` run in prerequisites.tftest.hcl, which
# already proved this for a network-interface-shaped association), the check is generic across resource
# *type* - it was never NIC-specific. The runs below simply substitute a Load Balancer frontend IP
# configuration and an Application Gateway frontend IP configuration in place of the NIC shape already
# tested, to make that genericity concrete for two more common surfaces (Load Balancer frontend attachment
# and Application Gateway attachment).
# Azure Bastion, Route Server, VPN/ExpressRoute Gateway, and VMSS/API-Management-via-NIC all present the
# same `.../<resourceType>/<name>/ipConfigurations/<name>`-shaped association value and are covered by the
# identical code path - they are not re-enumerated here to avoid redundant, purely-cosmetic test runs
# against one already-generic code path.
#
# Explicitly NOT covered by this check, and not claimed to be: `linkedPublicIPAddress` (dual-stack IPv4/IPv6
# sibling PIP reference) and `servicePublicIPAddress` (Basic-to-Standard migration sibling PIP reference).
# Both exist on this same schema but represent a PIP-to-PIP relationship, not "in use by a consuming network
# resource" - checking them speculatively risks rejecting legitimate configurations (e.g. a customer
# deliberately supplying both halves of a dual-stack pair).
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

# A public IP already attached to a Load Balancer's own frontend IP configuration presents ipConfiguration
# non-null but pointing at a loadBalancers resource, not an azureFirewalls one - rejected by the same
# generic parent-mismatch code path as reject_non_firewall_association (NIC case) in prerequisites.tftest.hcl.
run "reject_load_balancer_frontend_associated_public_ip" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address     = "203.0.113.10", allocation_method = "Static"
        association = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/loadBalancers/lb-test/frontendIPConfigurations/frontend1"
        ip_version  = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones       = ["1", "2", "3"]
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

# Same generic path, substituting an Application Gateway frontend IP configuration.
run "reject_application_gateway_frontend_associated_public_ip" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address     = "203.0.113.10", allocation_method = "Static"
        association = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/applicationGateways/agw-test/frontendIPConfigurations/frontend1"
        ip_version  = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones       = ["1", "2", "3"]
      }
    }
  }
  expect_failures = [azapi_resource.this]
}
