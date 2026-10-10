# See `modules/site-to-site-vpn-site/tests/null_optionals.tftest.hcl` for why this exists:
# An earlier test apply failed at apply, not at plan, because the inputs were unknown at plan
# time and the locals were never evaluated. Known inputs force evaluation.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

mock_provider "azapi" {}

variables {
  resource_types = {
    network_express_route_gateways_express_route_connections = "Microsoft.Network/expressRouteGateways/expressRouteConnections@2025-07-01"
  }
}

run "all_optionals_null" {
  command = plan

  variables {
    er_circuit_connections = {
      conn_a = {
        name                             = "erconn-null"
        express_route_gateway_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test"
        express_route_circuit_peering_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-test/peerings/AzurePrivatePeering"
      }
    }
  }

  # AzureRM's Create builds `parameters.Properties` as a struct literal and sends these
  # UNCONDITIONALLY via `pointer.To(d.Get(...))`. Their schema defaults therefore reached
  # ARM on every create, so a migrated connection must send the same literals or the
  # first post-upgrade apply resets them on a live circuit connection.
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.enableInternetSecurity == false
    error_message = "enableInternetSecurity must reproduce AzureRM's schema default false."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingWeight == 0
    error_message = "routingWeight must reproduce AzureRM's schema default 0."
  }

  # 🔴 Note this one is a WRITE rather than a drop. `variables.tf` accepts
  # `express_route_gateway_bypass_enabled` (Fast Path) and always has, but the AzureRM
  # resource block never referenced it -- so AzureRM read the schema default and sent
  # `expressRouteGatewayBypass: false` on every create regardless of what the consumer
  # passed. Every connection this module has ever created has Fast Path explicitly OFF.
  # This assertion is what stops the variable being wired up by accident: doing so would
  # enable Fast Path on existing connections at the first post-migration apply.
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.expressRouteGatewayBypass == false
    error_message = "expressRouteGatewayBypass must stay the inert literal false. Honouring express_route_gateway_bypass_enabled is a behaviour change for live connections and needs its own decision."
  }

  # `expandExpressRouteConnectionRouting` returns an EMPTY STRUCT, never nil, when
  # `routing` is absent -- so `routingConfiguration: {}` was part of every request
  # AzureRM sent. Absent is NOT the same request.
  #
  # `body` still holds the nulls at plan time; `ignore_null_property` strips them from the
  # REQUEST and leaves the emptied object behind. So the assertion is "every child null",
  # which is the plan-time spelling of "the request carries `routingConfiguration: {}`".
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.associatedRouteTable == null && azapi_resource.this["conn_a"].body.properties.routingConfiguration.inboundRouteMap == null && azapi_resource.this["conn_a"].body.properties.routingConfiguration.outboundRouteMap == null && azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables == null
    error_message = "routingConfiguration must reduce to the empty struct when routing is null: the AzureRM expander returned an empty struct, never nil."
  }

  assert {
    condition     = !can(azapi_resource.this["conn_a"].body.properties.authorizationKey)
    error_message = "authorizationKey must be absent when unset: AzureRM guarded it on d.GetOk."
  }
}

# `routing` present but `propagated_route_table` and both route maps omitted.
run "routing_set_children_null" {
  command = plan

  variables {
    er_circuit_connections = {
      conn_a = {
        name                             = "erconn-partial"
        express_route_gateway_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test"
        express_route_circuit_peering_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-test/peerings/AzurePrivatePeering"
        routing = {
          associated_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/defaultRouteTable"
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.associatedRouteTable.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/defaultRouteTable"
    error_message = "associatedRouteTable must carry the configured route table ID."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables == null
    error_message = "propagatedRouteTables must be null, and so pruned from the request, when propagated_route_table is null."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.inboundRouteMap == null && azapi_resource.this["conn_a"].body.properties.routingConfiguration.outboundRouteMap == null
    error_message = "The route maps must be null, and so pruned from the request, when unset: the expander guards each on a non-empty string."
  }
}

# `propagated_route_table` present with BOTH list children left null. This is the
# null-into-length shape for this module. Unlike `virtual-network-connection`, these two
# attributes carry no `[]` default here, so they really do arrive as null.
run "propagated_route_table_null_lists" {
  command = plan

  variables {
    er_circuit_connections = {
      conn_a = {
        name                             = "erconn-null-lists"
        express_route_gateway_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test"
        express_route_circuit_peering_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-test/peerings/AzurePrivatePeering"
        routing = {
          associated_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/defaultRouteTable"
          propagated_route_table    = {}
        }
      }
    }
  }

  # The expander guards `labels` and `ids` on `len(...) != 0` (L419, L423), so an empty
  # list is ABSENT rather than sent as `[]`. This differs from the s2s connection module,
  # where `ids` was built unconditionally -- the two expanders are genuinely not the same,
  # and this assertion is what keeps that difference from being smoothed over.
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables != null && azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables.labels == null && azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables.ids == null
    error_message = "propagatedRouteTables must survive as an object whose children are both null, so the request carries `propagatedRouteTables: {}`: the expander guards labels and ids each on a non-empty length."
  }
}

run "all_optionals_set" {
  command = plan

  variables {
    er_circuit_connections = {
      conn_a = {
        name                                 = "erconn-full"
        express_route_gateway_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test"
        express_route_circuit_peering_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-test/peerings/AzurePrivatePeering"
        authorization_key                    = "placeholder-not-a-secret"
        enable_internet_security             = true
        express_route_gateway_bypass_enabled = true
        routing_weight                       = 7
        routing = {
          associated_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/defaultRouteTable"
          inbound_route_map_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/routeMaps/rm-in"
          outbound_route_map_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/routeMaps/rm-out"
          propagated_route_table = {
            route_table_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/noneRouteTable"]
            labels          = ["default"]
          }
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.enableInternetSecurity == true && azapi_resource.this["conn_a"].body.properties.routingWeight == 7
    error_message = "enableInternetSecurity and routingWeight must carry the configured values."
  }

  # 🔴 Again, from the other side: setting the variable must STILL produce false.
  # If this assertion ever fails, the input has been quietly made live.
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.expressRouteGatewayBypass == false
    error_message = "expressRouteGatewayBypass must remain false even when express_route_gateway_bypass_enabled is set to true. The input is documented-but-inert and wiring it up is a behaviour change for existing connections."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.authorizationKey == "placeholder-not-a-secret"
    error_message = "authorizationKey must be emitted when set to a non-empty value."
  }

  # ✅ Unlike `site-to-site-gateway-connection`, this module DOES wire the route maps.
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.inboundRouteMap.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/routeMaps/rm-in"
    error_message = "inboundRouteMap must be wired: this module, unlike the s2s connection module, has always supported it."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables.ids[0].id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/noneRouteTable"
    error_message = "propagatedRouteTables.ids must wrap each route table ID in a SubResource object."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables.labels == tolist(["default"])
    error_message = "propagatedRouteTables.labels must carry the configured labels verbatim."
  }
}

run "empty_map" {
  command = plan

  variables {
    er_circuit_connections = {}
  }

  assert {
    condition     = length(azapi_resource.this) == 0
    error_message = "An empty er_circuit_connections map must create no resources."
  }
}
