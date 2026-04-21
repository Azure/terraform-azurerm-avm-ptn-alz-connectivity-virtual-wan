# Create the Express Route Connection
resource "azapi_resource" "er_connection" {
  for_each = var.er_circuit_connections != null && length(var.er_circuit_connections) > 0 ? var.er_circuit_connections : {}

  type      = "Microsoft.Network/expressRouteGateways/expressRouteConnections@2024-05-01"
  name      = each.value.name
  parent_id = each.value.express_route_gateway_id

  body = {
    properties = {
      expressRouteCircuitPeering = {
        id = each.value.express_route_circuit_peering_id
      }
      authorizationKey          = try(each.value.authorization_key, null)
      enableInternetSecurity    = try(each.value.enable_internet_security, null)
      expressRouteGatewayBypass = try(each.value.express_route_gateway_bypass_enabled, null)
      routingWeight             = try(each.value.routing_weight, null)
      routingConfiguration = each.value.routing != null ? {
        associatedRouteTable = {
          id = each.value.routing.associated_route_table_id
        }
        propagatedRouteTables = try(each.value.routing.propagated_route_table, null) != null ? {
          ids    = try([for id in each.value.routing.propagated_route_table.route_table_ids : { id = id }], [])
          labels = try(each.value.routing.propagated_route_table.labels, [])
        } : null
        inboundRouteMap = try(each.value.routing.inbound_route_map_id, null) != null ? {
          id = each.value.routing.inbound_route_map_id
        } : null
        outboundRouteMap = try(each.value.routing.outbound_route_map_id, null) != null ? {
          id = each.value.routing.outbound_route_map_id
        } : null
      } : null
    }
  }

  retry = {
    error_message_regex  = var.retry.error_message_regex
    interval_seconds     = var.retry.interval_seconds
    max_interval_seconds = var.retry.max_interval_seconds
  }

  response_export_values = ["*"]
}

moved {
  from = azurerm_express_route_connection.er_connection
  to   = azapi_resource.er_connection
}
