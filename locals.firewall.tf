locals {
  firewall_enabled = { for key, value in var.virtual_hubs : key => value.enabled_resources.firewall }
  firewall_policies = { for key, value in var.virtual_hubs : key => merge(value.firewall_policy, {
    name                = coalesce(value.firewall_policy.name, local.default_names[key].firewall_policy_name)
    location            = value.location
    dns                 = value.firewall_policy.dns != null ? value.firewall_policy.dns : local.firewall_policy_dns_defaults[key]
    resource_group_name = coalesce(value.firewall_policy.resource_group_name, local.hub_virtual_networks_resource_group_names[key])
    tags                = coalesce(value.firewall_policy.tags, var.tags, {})
  }) if local.firewall_policy_enabled[key] }
  firewall_policy_dns_defaults = { for key, value in var.virtual_hubs : key => local.private_dns_resolver_enabled[key] && local.private_dns_zones_enabled[key] && local.firewall_enabled[key] && !local.firewall_sku_is_basic[key] ? {
    proxy_enabled = true
    servers       = [local.private_dns_resolver_ip_addresses[key]]
  } : null }
  firewall_policy_enabled = { for key, value in var.virtual_hubs : key => value.enabled_resources.firewall_policy && local.firewall_enabled[key] }
  firewall_sku_is_basic   = { for key, value in var.virtual_hubs : key => local.firewall_enabled[key] && (value.firewall.sku_tier == "Basic" || value.firewall_policy.sku == "Basic") }
  firewalls = { for key, value in var.virtual_hubs : key => merge(value.firewall, {
    virtual_hub_key    = key
    name               = coalesce(value.firewall.name, local.default_names[key].firewall_name)
    firewall_policy_id = coalesce(value.firewall.firewall_policy_id, local.firewall_policy_enabled[key] ? module.firewall_policy[key].resource_id : null)
    tags               = coalesce(value.firewall.tags, var.tags, {})
    zones              = coalesce(value.firewall.zones, local.availability_zones[key])
  }) if local.firewall_enabled[key] }
}
