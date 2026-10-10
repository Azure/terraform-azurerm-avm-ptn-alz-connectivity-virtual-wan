locals {
  virtual_network_connections = var.virtual_network_connections != null ? var.virtual_network_connections : {}

  # AzureRM retains Optional/Computed routing from its read when the caller omits it.
  virtual_network_connection_existing_properties = {
    for key, value in local.virtual_network_connections : key => merge([
      for connection in data.azapi_resource_list.virtual_network_connections[key].output.value : merge(
        {
          for property in ["routingConfiguration", "allowHubToRemoteVnetTransit", "allowRemoteVnetToUseHubVnetGateways"] :
          property => connection.properties[property]
          if try(connection.properties[property], null) != null
        },
        try(connection.properties.routingConfiguration.vnetRoutes, null) != null ? {
          routingConfiguration = merge(connection.properties.routingConfiguration, {
            # ARM returns this BGP back-reference, but the connection PUT schema marks it read-only.
            vnetRoutes = {
              for property, route_value in connection.properties.routingConfiguration.vnetRoutes :
              property => route_value if property != "bgpConnections"
            }
          })
        } : {},
      )
      if lower(connection.name) == lower(value.name) &&
      lower(connection.properties.remoteVirtualNetwork.id) == lower(value.remote_virtual_network_id)
    ]...)
  }

  # When routing is explicitly configured, AzureRM's expander always
  # builds `vnetRoutes.staticRoutesConfig` from two schema defaults the module never
  # exposed: `static_vnet_propagate_static_routes_enabled = true` and
  # `static_vnet_local_route_override_criteria = "Contains"`. Those literals are
  # reproduced below so a migrated connection PUTs the same body it PUT before.
  virtual_network_connection_bodies = {
    for key, value in local.virtual_network_connections : key => {
      properties = merge(
        local.virtual_network_connection_existing_properties[key],
        {
          remoteVirtualNetwork   = { id = value.remote_virtual_network_id }
          enableInternetSecurity = value.internet_security_enabled
        },
        try(value.routing, null) != null ? {
          routingConfiguration = merge(
            {
              vnetRoutes = merge(
                {
                  staticRoutesConfig = {
                    propagateStaticRoutes          = true
                    vnetLocalRouteOverrideCriteria = "Contains"
                  }
                },
                try(value.routing.static_vnet_route, null) != null ? {
                  staticRoutes = [
                    {
                      name             = try(value.routing.static_vnet_route.name, null)
                      addressPrefixes  = try(value.routing.static_vnet_route.address_prefixes, null)
                      nextHopIpAddress = try(value.routing.static_vnet_route.next_hop_ip_address, null)
                    }
                  ]
                } : {},
              )
            },
            # AzureRM guards this on a non-empty string, so an unset ID omits the key.
            try(value.routing.associated_route_table_id, null) != null && try(value.routing.associated_route_table_id, "") != "" ? {
              associatedRouteTable = { id = value.routing.associated_route_table_id }
            } : {},
            try(value.routing.propagated_route_table, null) != null ? {
              propagatedRouteTables = {
                labels = length(try(value.routing.propagated_route_table.labels, null) != null ? value.routing.propagated_route_table.labels : []) > 0 ? value.routing.propagated_route_table.labels : null
                # ARM takes SubResource objects here, not bare ID strings.
                ids = length(try(value.routing.propagated_route_table.route_table_ids, null) != null ? value.routing.propagated_route_table.route_table_ids : []) > 0 ? [
                  for route_table_id in value.routing.propagated_route_table.route_table_ids : { id = route_table_id }
                ] : null
              }
            } : {},
          )
        } : {},
      )
    }
  }
}

locals {
  # Per-resource timeout defaults. `var.timeouts` keeps its published shape -- same name, same
  # four attributes, same types -- but its attributes no longer carry a blanket `30m`/`5m`
  # default. An attribute the consumer leaves unset now falls back to the default of the
  # AzureRM resource this module replaced. A consumer who sets `var.timeouts` today is
  # unaffected.
  #
  # ⚠️ This module is one of the two where the blanket `30m` was WRONG:
  # `azurerm_virtual_hub_connection` defaulted create/update/delete to 60m, not 30m. A hub
  # connection routinely takes longer than half an hour when the hub is busy, so the previous
  # default could time out an operation AzureRM would have waited out.
  #
  # Cited against terraform-provider-azurerm@5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0).
  #
  # azapi_resource.this -> azurerm_virtual_hub_connection
  #   virtual_hub_connection_resource.go L37-L42: Create 60m, Read 5m, Update 60m, Delete 60m
  timeouts = {
    create = try(var.timeouts.create, null) != null ? var.timeouts.create : "60m"
    read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
    update = try(var.timeouts.update, null) != null ? var.timeouts.update : "60m"
    delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "60m"
  }
}
