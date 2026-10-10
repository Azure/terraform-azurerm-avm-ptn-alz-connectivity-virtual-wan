# AzAPI `body` is dynamic, so instances built from different optional inputs have different
# object types. A `resource` output that unifies a tuple of those instances with `[]` fails
# with "Inconsistent conditional result types". This reproduces the live failure seen when a
# routed connection and an unrouted connection share one module call.

mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        value = []
      }
    }
  }
}

run "virtual_network_connection_mixed_routing" {
  command = plan

  module {
    source = "./modules/virtual-network-connection"
  }

  variables {
    virtual_network_connections = {
      routed = {
        name                      = "conn-routed"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-routed"
        routing = {
          associated_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/defaultRouteTable"
          propagated_route_table = {
            labels = ["default"]
          }
        }
      }
      unrouted = {
        name                      = "conn-unrouted"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-unrouted"
      }
    }
  }

  assert {
    condition     = length(output.resource) == 2
    error_message = "The resource output must list both connections when their bodies differ in shape."
  }

  assert {
    condition     = length(output.resource_object) == 2 && length(output.resource_id) == 2
    error_message = "The resource_object and resource_id outputs must still cover both connections."
  }
}

run "virtual_network_connection_empty" {
  command = plan

  module {
    source = "./modules/virtual-network-connection"
  }

  assert {
    condition     = length(output.resource) == 0
    error_message = "The resource output must stay an empty list when no connections are configured."
  }
}

run "expressroute_gateway_connection_mixed_routing" {
  command = plan

  module {
    source = "./modules/expressroute-gateway-connection"
  }

  variables {
    er_circuit_connections = {
      routed = {
        name                             = "er-routed"
        express_route_gateway_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test"
        express_route_circuit_peering_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-a/peerings/AzurePrivatePeering"
        routing = {
          associated_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/defaultRouteTable"
          propagated_route_table = {
            labels = ["default"]
          }
        }
      }
      unrouted = {
        name                             = "er-unrouted"
        express_route_gateway_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test"
        express_route_circuit_peering_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-b/peerings/AzurePrivatePeering"
      }
    }
  }

  assert {
    condition     = length(output.resource) == 2
    error_message = "The resource output must list both ExpressRoute connections when their bodies differ in shape."
  }
}
