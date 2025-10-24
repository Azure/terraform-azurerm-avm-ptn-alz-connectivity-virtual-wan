locals {
  virtual_network_gateways_express_route = {
    for hub_network_key, hub_network_value in var.virtual_hubs : hub_network_key => merge(hub_network_value.virtual_network_gateways.express_route, {
      virtual_hub_key = hub_network_key
      name            = coalesce(hub_network_value.virtual_network_gateways.express_route.name, local.default_names[hub_network_key].virtual_network_gateway_express_route_name)
      tags            = coalesce(hub_network_value.virtual_network_gateways.express_route.tags, var.tags, {})
    }) if local.virtual_network_gateways_express_route_enabled[hub_network_key]
  }
  virtual_network_gateways_express_route_enabled = {
    for hub_network_key, hub_network_value in var.virtual_hubs : hub_network_key => hub_network_value.enabled_resources.virtual_network_gateway_express_route
  }
}

locals {
  virtual_network_gateways_vpn = {
    for hub_network_key, hub_network_value in var.virtual_hubs : hub_network_key => merge(hub_network_value.virtual_network_gateways.vpn, {
      virtual_hub_key = hub_network_key
      name            = coalesce(hub_network_value.virtual_network_gateways.vpn.name, local.default_names[hub_network_key].virtual_network_gateway_vpn_name)
      tags            = coalesce(hub_network_value.virtual_network_gateways.vpn.tags, var.tags, {})
    }) if local.virtual_network_gateways_vpn_enabled[hub_network_key]
  }
  virtual_network_gateways_vpn_enabled = {
    for hub_network_key, hub_network_value in var.virtual_hubs : hub_network_key => hub_network_value.enabled_resources.virtual_network_gateway_vpn
  }
}
