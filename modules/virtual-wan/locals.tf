locals {
  er_circuit_connections = var.er_circuit_connections != null ? {
    for key, er_conn in var.er_circuit_connections : key => {
      name                                 = er_conn.name
      express_route_gateway_key            = er_conn.express_route_gateway_key
      express_route_circuit_peering_id     = er_conn.express_route_circuit_peering_id
      authorization_key                    = try(er_conn.authorization_key, null)
      enable_internet_security             = try(er_conn.enable_internet_security, null)
      express_route_gateway_bypass_enabled = try(er_conn.express_route_gateway_bypass_enabled, null)
      routing_weight                       = try(er_conn.routing_weight, null)
      routing                              = try(er_conn.routing, null)
    }
  } : null
  expressroute_gateways = var.expressroute_gateways != null ? {
    for key, gw in var.expressroute_gateways : key => {
      name                          = gw.name
      virtual_hub_key               = gw.virtual_hub_key
      scale_units                   = gw.scale_units
      allow_non_virtual_wan_traffic = gw.allow_non_virtual_wan_traffic
      tags                          = try(gw.tags, null) == null ? var.tags : gw.tags
    }
  } : null
  p2s_gateway_vpn_server_configurations = var.p2s_gateway_vpn_server_configurations != null ? {
    for key, svr in var.p2s_gateway_vpn_server_configurations : key => {
      name                                  = svr.name
      virtual_hub_key                       = svr.virtual_hub_key
      vpn_authentication_types              = svr.vpn_authentication_types
      client_root_certificate               = svr.client_root_certificate
      azure_active_directory_authentication = svr.azure_active_directory_authentication
      tags                                  = try(svr.tags, null) == null ? var.tags : svr.tags
    }
  } : null
  p2s_gateways = var.p2s_gateways != null ? {
    for key, gw in var.p2s_gateways : key => {
      name                                     = gw.name
      virtual_hub_key                          = gw.virtual_hub_key
      scale_unit                               = gw.scale_unit
      connection_configuration                 = gw.connection_configuration
      p2s_gateway_vpn_server_configuration_key = gw.p2s_gateway_vpn_server_configuration_key
      tags                                     = try(gw.tags, null) == null ? var.tags : gw.tags
      dns_servers                              = gw.dns_servers
    }
  } : null
  routing_intents = {
    for key, intent in var.routing_intents : key => {
      name            = intent.name
      virtual_hub_key = intent.virtual_hub_key
      routing_policies = lookup(intent, "routing_policies", null) == null ? [] : [
        for routing_policy in intent.routing_policies : {
          name                  = routing_policy.name
          destinations          = routing_policy.destinations
          next_hop_firewall_key = routing_policy.next_hop_firewall_key
      }]
    }
  }
  virtual_hubs = {
    for key, vhub in var.virtual_hubs : key => {
      name                                   = vhub.name
      location                               = vhub.location
      resource_group_name                    = try(vhub.resource_group_name, "")
      address_prefix                         = vhub.address_prefix
      hub_routing_preference                 = try(vhub.hub_routing_preference, "")
      sku                                    = try(vhub.sku, null)
      tags                                   = try(vhub.tags, null) == null ? var.tags : vhub.tags
      virtual_router_auto_scale_min_capacity = vhub.virtual_router_auto_scale_min_capacity
    }
  }
  vpn_gateways = var.vpn_gateways != null ? {
    for key, gw in var.vpn_gateways : key => {
      name                                  = gw.name
      virtual_hub_key                       = gw.virtual_hub_key
      bgp_route_translation_for_nat_enabled = gw.bgp_route_translation_for_nat_enabled
      bgp_settings                          = gw.bgp_settings
      routing_preference                    = gw.routing_preference
      scale_unit                            = gw.scale_unit
      tags                                  = try(gw.tags, null) == null ? var.tags : gw.tags
    }
  } : null
  vpn_site_connections = var.vpn_site_connections != null ? {
    for key, conn in var.vpn_site_connections : key => {
      name                      = conn.name
      vpn_gateway_key           = conn.vpn_gateway_key
      remote_vpn_site_key       = conn.remote_vpn_site_key
      internet_security_enabled = conn.internet_security_enabled
      vpn_links                 = conn.vpn_links
      routing                   = conn.routing
      traffic_selector_policy   = conn.traffic_selector_policy
    }
  } : null
  vpn_sites = var.vpn_sites != null ? {
    for key, site in var.vpn_sites : key => {
      name            = site.name
      virtual_hub_key = site.virtual_hub_key
      address_cidrs   = site.address_cidrs
      links           = site.links
      device_vendor   = site.device_vendor
      device_model    = site.device_model
      o365_policy     = site.o365_policy
      tags            = try(site.tags, null) == null ? var.tags : site.tags
    }
  } : null
}

locals {
  create_virtual_wan         = var.virtual_wan_id == null
  effective_virtual_wan_id   = local.create_virtual_wan ? azapi_resource.virtual_wan[0].id : var.virtual_wan_id
  effective_virtual_wan_name = local.create_virtual_wan ? azapi_resource.virtual_wan[0].name : provider::azapi::parse_resource_id("Microsoft.Network/virtualWans", var.virtual_wan_id).name
  resource_group_name        = var.create_resource_group ? azapi_resource.rg[0].name : var.resource_group_name
  # AzureRM took the resource group by name; AzAPI needs its ID. When the module creates the
  # group the ID comes off the resource itself, which also preserves the implicit dependency
  # AzureRM got from `resource_group_name = azurerm_resource_group.rg[0].name`.
  resource_group_resource_id = var.create_resource_group ? azapi_resource.rg[0].id : "/subscriptions/${data.azapi_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
}

locals {
  # AzureRM's Create builds `HubRouteTableProperties` from `utils.ExpandStringSlice` and
  # `expandVirtualHubRouteTableHubRoutes`, both of which return a pointer to a slice that is
  # EMPTY rather than nil when nothing is configured. `labels: []` and `routes: []` were
  # therefore part of every request AzureRM sent, and they stay part of this one. Verified
  # against virtual_hub_route_table_resource.go at v4.81.0.
  virtual_hub_route_table_bodies = {
    for key, value in var.virtual_hub_route_tables : key => {
      properties = {
        labels = value.labels != null ? value.labels : []
        # `routes` is `optional(map(...))` with no default, so it can be null. The original
        # `dynamic "route" { for_each = each.value.routes }` failed outright on that null;
        # the guard is new.
        routes = [
          for route in values(value.routes != null ? value.routes : {}) : {
            destinations = route.destinations
            # Schema key `destinations_type` maps to the SINGULAR ARM property
            # `destinationType`. Easy to get wrong.
            destinationType = route.destinations_type
            name            = route.name
            # `vnet_connection_key` is optional; indexing the map with a null key raises,
            # which is what `try` is catching here, exactly as before.
            nextHop     = try(module.virtual_network_connections.resource_object[route.vnet_connection_key].id, route.next_hop)
            nextHopType = route.next_hop_type
          }
        ]
      }
    }
  }
}
