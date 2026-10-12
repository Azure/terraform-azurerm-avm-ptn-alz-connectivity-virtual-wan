locals {
  firewall_hubs = {
    edge-east = "east"
    edge-west = "west"
  }
  firewalls = {
    for key in var.configuration.firewall_keys : key => {
      name                 = "fw-${key}"
      sku_tier             = "Standard"
      virtual_hub_key      = local.firewall_hubs[key]
      zones                = [1, 2, 3]
      vhub_public_ip_count = contains(var.configuration.customer_keys, key) ? null : "1"
      firewall_policy_id = var.configuration.unknown_values ? (
        "${local.parent_id}/providers/Microsoft.Network/firewallPolicies/policy-${terraform_data.upstream.output}"
      ) : null
      # The root pattern supplies one managed IP; the customer branch supplies none.
      ip_configurations = contains(var.configuration.customer_keys, key) ? {
        primary = {
          name = "customer-primary"
          public_ip_address_id = var.configuration.unknown_values ? (
            "${local.parent_id}/providers/Microsoft.Network/publicIPAddresses/pip-${key}-${terraform_data.upstream.output}"
          ) : "${local.parent_id}/providers/Microsoft.Network/publicIPAddresses/pip-${key}"
        }
      } : {}
      tags = {
        fixture    = "firewall-graph"
        dependency = var.configuration.unknown_values ? tostring(terraform_data.upstream.output) : "stable"
      }
    } if contains(var.configuration.hub_keys, local.firewall_hubs[key])
  }
  parent_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-firewall-graph"
}
