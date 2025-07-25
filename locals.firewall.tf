locals {
  firewall_enabled = { for virtual_hub_key, virtual_hub_value in var.virtual_hubs : virtual_hub_key => try(virtual_hub_value.firewall.enabled, try(virtual_hub_value.firewall, null) != null) }
  firewall_policies = { for virtual_hub_key, virtual_hub_value in var.virtual_hubs : virtual_hub_key => merge({
    location            = try(virtual_hub_value.firewall_policy.location, virtual_hub_value.hub.location)
    resource_group_name = try(virtual_hub_value.firewall_policy.resource_group_name, virtual_hub_value.hub.resource_group)
    dns = merge({
      servers       = local.private_dns_resolver_enabled[virtual_hub_key] && local.private_dns_zones_enabled[virtual_hub_key] ? [module.dns_resolver[virtual_hub_key].inbound_endpoint_ips["dns"]] : []
      proxy_enabled = local.private_dns_resolver_enabled[virtual_hub_key] && local.private_dns_zones_enabled[virtual_hub_key]
    }, try(virtual_hub_value.firewall_policy.dns, {}))
    }, virtual_hub_value.firewall_policy) if local.firewall_enabled[virtual_hub_key]
  }
  firewalls = { for virtual_hub_key, virtual_hub_value in var.virtual_hubs : virtual_hub_key => merge({
    virtual_hub_key    = virtual_hub_key
    firewall_policy_id = module.firewall_policy[virtual_hub_key].resource_id
    }, virtual_hub_value.firewall) if local.firewall_enabled[virtual_hub_key]
  }
}
