locals {
  private_dns_resolver_enabled = { for key, value in var.virtual_hubs : key => try(value.private_dns_resolver.enabled, try(value.private_dns_resolver, null) != null) }
}

locals {
  private_dns_resolver = { for key, value in var.virtual_hubs : key => merge({
    location            = value.hub.location
    resource_group_name = value.hub.resource_group
    inbound_endpoints = local.private_dns_zones_enabled[key] ? {
      dns = {
        name        = "dns"
        subnet_name = module.virtual_network_side_car[key].subnets["dns_resolver"].name
      }
    } : {}
  }, value.private_dns_resolver.dns_resolver) if local.private_dns_resolver_enabled[key] && local.side_car_virtual_networks_enabled[key] }
}
