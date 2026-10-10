mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        value = [{
          name = "connection-test"
          properties = {
            allowHubToRemoteVnetTransit         = true
            allowRemoteVnetToUseHubVnetGateways = true
            remoteVirtualNetwork = {
              id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
            }
            routingConfiguration = {
              associatedRouteTable = {
                id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/custom"
              }
              propagatedRouteTables = {
                labels = ["custom"]
                ids    = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/custom" }]
              }
              inboundRouteMap  = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/routeMaps/inbound" }
              outboundRouteMap = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/routeMaps/outbound" }
              vnetRoutes = {
                bgpConnections = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/bgpConnections/bgp-test" }]
                staticRoutes = [{
                  name             = "custom-route"
                  addressPrefixes  = ["10.42.0.0/16"]
                  nextHopIpAddress = "10.0.0.4"
                }]
                staticRoutesConfig = {
                  propagateStaticRoutes          = false
                  vnetLocalRouteOverrideCriteria = "Equal"
                }
              }
            }
          }
        }]
      }
    }
  }
}

variables {
  virtual_network_connections = {
    test = {
      name                      = "connection-test"
      virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
      remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
    }
  }
}

run "omitted_routing_preserves_existing_custom_routing" {
  command = plan

  assert {
    condition     = try(azapi_resource.this["test"].body.properties.routingConfiguration.associatedRouteTable.id, null) == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/custom"
    error_message = "Omitted routing must retain the existing route-table association, not reset it to defaults."
  }
  assert {
    condition     = try(azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutes[0].nextHopIpAddress, null) == "10.0.0.4"
    error_message = "Omitted routing must retain existing custom static routes."
  }
  assert {
    condition     = try(azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutesConfig.propagateStaticRoutes, null) == false
    error_message = "Omitted routing must retain custom static-route propagation settings."
  }
  assert {
    condition     = !contains(keys(azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes), "bgpConnections")
    error_message = "The carried-over routing body must exclude the read-only BGP connection back-reference."
  }
  assert {
    condition = (
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutes[0].name == "custom-route" &&
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutes[0].addressPrefixes == ["10.42.0.0/16"] &&
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutesConfig.vnetLocalRouteOverrideCriteria == "Equal" &&
      azapi_resource.this["test"].body.properties.routingConfiguration.propagatedRouteTables.labels == ["custom"] &&
      azapi_resource.this["test"].body.properties.routingConfiguration.propagatedRouteTables.ids[0].id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/custom" &&
      azapi_resource.this["test"].body.properties.routingConfiguration.inboundRouteMap.id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/routeMaps/inbound" &&
      azapi_resource.this["test"].body.properties.routingConfiguration.outboundRouteMap.id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/routeMaps/outbound"
    )
    error_message = "Filtering response-only BGP references must preserve all writable routing settings."
  }
  assert {
    condition     = azapi_resource.this["test"].body.properties.allowHubToRemoteVnetTransit && azapi_resource.this["test"].body.properties.allowRemoteVnetToUseHubVnetGateways
    error_message = "Returned legacy transit flags must not be removed during adoption."
  }
}

run "explicit_routing_overrides_existing_routing" {
  command = plan

  variables {
    virtual_network_connections = {
      test = {
        name                      = "connection-test"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
        routing = {
          associated_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/explicit"
          propagated_route_table    = { labels = ["explicit"] }
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["test"].body.properties.routingConfiguration.associatedRouteTable.id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/explicit"
    error_message = "Explicit routing must override the existing association."
  }
  assert {
    condition     = azapi_resource.this["test"].body.properties.routingConfiguration.propagatedRouteTables.labels[0] == "explicit"
    error_message = "Explicit propagation labels must be honored."
  }
}

run "fresh_connection_keeps_azure_routing_defaults" {
  command = plan

  override_data {
    target = data.azapi_resource_list.virtual_network_connections["test"]
    values = { output = { value = [] } }
  }

  assert {
    condition     = !contains(keys(azapi_resource.this["test"].body.properties), "routingConfiguration")
    error_message = "A new connection with omitted routing must use Azure defaults."
  }
}

run "routing_without_vnet_routes_is_preserved" {
  command = plan

  override_data {
    target = data.azapi_resource_list.virtual_network_connections["test"]
    values = {
      output = {
        value = [{
          name = "connection-test"
          properties = {
            remoteVirtualNetwork = {
              id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
            }
            routingConfiguration = {
              propagatedRouteTables = { labels = ["custom"], ids = [] }
            }
          }
        }]
      }
    }
  }

  assert {
    condition = (
      azapi_resource.this["test"].body.properties.routingConfiguration.propagatedRouteTables.labels == ["custom"] &&
      !contains(keys(azapi_resource.this["test"].body.properties.routingConfiguration), "vnetRoutes")
    )
    error_message = "Filtering must not introduce vnetRoutes when ARM returned only propagation settings."
  }
}

run "accelerator_bgp_routing_preserves_baseline_fields" {
  command = plan

  override_data {
    target = data.azapi_resource_list.virtual_network_connections["test"]
    values = {
      output = {
        value = [{
          name = "connection-test"
          properties = {
            remoteVirtualNetwork = {
              id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
            }
            routingConfiguration = {
              associatedRouteTable = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/defaultRouteTable" }
              propagatedRouteTables = {
                labels = ["none"]
                ids    = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/noneRouteTable" }]
              }
              vnetRoutes = {
                bgpConnections = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/bgpConnections/primary-nva1" }]
                staticRoutes   = []
                staticRoutesConfig = {
                  propagateStaticRoutes          = true
                  vnetLocalRouteOverrideCriteria = "Contains"
                }
              }
            }
          }
        }]
      }
    }
  }

  assert {
    condition = (
      !contains(keys(azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes), "bgpConnections") &&
      azapi_resource.this["test"].body.properties.routingConfiguration.associatedRouteTable.id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/defaultRouteTable" &&
      azapi_resource.this["test"].body.properties.routingConfiguration.propagatedRouteTables.labels == ["none"] &&
      azapi_resource.this["test"].body.properties.routingConfiguration.propagatedRouteTables.ids[0].id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/noneRouteTable" &&
      length(azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutes) == 0 &&
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutesConfig.propagateStaticRoutes == true &&
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutesConfig.vnetLocalRouteOverrideCriteria == "Contains"
    )
    error_message = "The Accelerator BGP baseline must retain default/none tables and its static-route configuration without the read-only back-reference."
  }
}

run "custom_routing_without_bgp_is_preserved" {
  command = plan

  override_data {
    target = data.azapi_resource_list.virtual_network_connections["test"]
    values = {
      output = {
        value = [{
          name = "connection-test"
          properties = {
            remoteVirtualNetwork = {
              id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
            }
            routingConfiguration = {
              associatedRouteTable  = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/custom" }
              propagatedRouteTables = { labels = ["custom"], ids = [] }
              inboundRouteMap       = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/routeMaps/inbound" }
              outboundRouteMap      = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/routeMaps/outbound" }
              vnetRoutes = {
                staticRoutes = [{ name = "custom-route", addressPrefixes = ["10.42.0.0/16"], nextHopIpAddress = "10.0.0.4" }]
                staticRoutesConfig = {
                  propagateStaticRoutes          = false
                  vnetLocalRouteOverrideCriteria = "Equal"
                }
              }
            }
          }
        }]
      }
    }
  }

  assert {
    condition = (
      azapi_resource.this["test"].body.properties.routingConfiguration.associatedRouteTable.id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/custom" &&
      azapi_resource.this["test"].body.properties.routingConfiguration.propagatedRouteTables.labels == ["custom"] &&
      length(azapi_resource.this["test"].body.properties.routingConfiguration.propagatedRouteTables.ids) == 0 &&
      azapi_resource.this["test"].body.properties.routingConfiguration.inboundRouteMap.id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/routeMaps/inbound" &&
      azapi_resource.this["test"].body.properties.routingConfiguration.outboundRouteMap.id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/routeMaps/outbound" &&
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutes[0].name == "custom-route" &&
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutes[0].addressPrefixes == ["10.42.0.0/16"] &&
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutes[0].nextHopIpAddress == "10.0.0.4" &&
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutesConfig.propagateStaticRoutes == false &&
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes.staticRoutesConfig.vnetLocalRouteOverrideCriteria == "Equal"
    )
    error_message = "The no-BGP path must still preserve custom tables, route maps and static-route settings instead of reverting to Azure defaults."
  }
}

run "null_vnet_routes_is_preserved" {
  command = plan

  override_data {
    target = data.azapi_resource_list.virtual_network_connections["test"]
    values = {
      output = {
        value = [{
          name = "connection-test"
          properties = {
            remoteVirtualNetwork = {
              id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
            }
            routingConfiguration = {
              propagatedRouteTables = { labels = ["custom"], ids = [] }
              vnetRoutes            = null
            }
          }
        }]
      }
    }
  }

  assert {
    condition = (
      azapi_resource.this["test"].body.properties.routingConfiguration.propagatedRouteTables.labels == ["custom"] &&
      azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes == null
    )
    error_message = "A null vnetRoutes response must not be iterated or changed into an object."
  }
}

run "bgp_only_vnet_routes_leaves_empty_object" {
  command = plan

  override_data {
    target = data.azapi_resource_list.virtual_network_connections["test"]
    values = {
      output = {
        value = [{
          name = "connection-test"
          properties = {
            remoteVirtualNetwork = {
              id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
            }
            routingConfiguration = {
              vnetRoutes = {
                bgpConnections = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/bgpConnections/bgp-test" }]
              }
            }
          }
        }]
      }
    }
  }

  assert {
    condition     = length(keys(azapi_resource.this["test"].body.properties.routingConfiguration.vnetRoutes)) == 0
    error_message = "Only the read-only back-reference should be removed; no routing defaults should be invented."
  }
}

run "connection_to_another_vnet_does_not_inherit_routing" {
  command = plan

  variables {
    virtual_network_connections = {
      test = {
        name                      = "connection-test"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/different-vnet"
      }
    }
  }

  assert {
    condition     = !contains(keys(azapi_resource.this["test"].body.properties), "routingConfiguration")
    error_message = "A replacement targeting another VNet must not inherit unrelated routing."
  }
}
