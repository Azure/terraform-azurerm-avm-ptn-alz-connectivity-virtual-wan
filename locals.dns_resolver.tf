locals {
  private_dns_resolver_enabled = { for key, value in var.virtual_hubs : key => value.enabled_resources.private_dns_resolver && local.sidecar_virtual_networks_enabled[key] }
}

locals {
  private_dns_resolver = { for key, value in var.virtual_hubs : key => {
    name                = coalesce(value.private_dns_resolver.name, local.default_names[key].private_dns_resolver_name)
    location            = value.location
    resource_group_name = coalesce(value.private_dns_resolver.resource_group_name, local.hub_virtual_networks_resource_group_names[key])
    inbound_endpoints = local.private_dns_zones_enabled[key] && value.private_dns_resolver.default_inbound_endpoint_enabled ? merge({
      dns = {
        name                         = "dns"
        subnet_name                  = module.virtual_network_side_car[key].subnets["dns_resolver"].name
        private_ip_allocation_method = "Dynamic"
        tags                         = coalesce(value.private_dns_resolver.tags, var.tags, {})
        merge_with_module_tags       = false
      }
    }, value.private_dns_resolver.inbound_endpoints) : value.private_dns_resolver.inbound_endpoints
    outbound_endpoints = value.private_dns_resolver.outbound_endpoints
    tags               = coalesce(value.private_dns_resolver.tags, var.tags, {})
    } if local.private_dns_resolver_enabled[key]
  }
}
