mock_provider "azapi" {
  mock_data "azapi_resource" {
    defaults = {
      output = {
        properties = {
          routingConfiguration = {
            associatedRouteTable = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/hubRouteTables/defaultRouteTable" }
            propagatedRouteTables = {
              ids    = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/hubRouteTables/noneRouteTable" }]
              labels = ["none"]
            }
            inboundRouteMap  = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/routeMaps/inbound" }
            outboundRouteMap = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/routeMaps/outbound" }
            vnetRoutes = {
              bgpConnections = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/bgpConnections/peer" }]
              staticRoutes = [{
                name             = "static"
                addressPrefixes  = ["10.20.0.0/16"]
                nextHopIpAddress = "10.0.3.4"
              }]
              staticRoutesConfig = {
                propagateStaticRoutes          = true
                vnetLocalRouteOverrideCriteria = "Contains"
              }
            }
          }
        }
      }
    }
  }
}

variables {
  resource_types = {
    network_vpn_gateways_vpn_connections = "Microsoft.Network/vpnGateways/vpnConnections@2025-07-01"
  }
  vpn_site_connection = {
    conn = {
      name               = "connection"
      vpn_gateway_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/gateway"
      remote_vpn_site_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/site"
      vpn_links          = [{ name = "link", vpn_site_link_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/site/vpnSiteLinks/link" }]
    }
  }
}

run "omitted_routing_preserves_writable_arm_fields" {
  command = plan

  assert {
    condition = try(jsonencode(azapi_resource.this["conn"].body.properties.routingConfiguration), "") == jsonencode({
      associatedRouteTable = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/hubRouteTables/defaultRouteTable" }
      propagatedRouteTables = {
        ids    = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/hubRouteTables/noneRouteTable" }]
        labels = ["none"]
      }
      inboundRouteMap  = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/routeMaps/inbound" }
      outboundRouteMap = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/routeMaps/outbound" }
      vnetRoutes = {
        staticRoutes       = [{ name = "static", addressPrefixes = ["10.20.0.0/16"], nextHopIpAddress = "10.0.3.4" }]
        staticRoutesConfig = { propagateStaticRoutes = true, vnetLocalRouteOverrideCriteria = "Contains" }
      }
    })
    error_message = "An omitted routing input must preserve all writable ARM routing, excluding only the read-only BGP back-reference."
  }
}

run "attempt5_routing_without_bgp_is_preserved" {
  command = plan

  override_data {
    target = data.azapi_resource.existing_vpn_connection
    values = {
      output = {
        properties = {
          routingConfiguration = {
            associatedRouteTable = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/hubRouteTables/defaultRouteTable" }
            propagatedRouteTables = {
              ids    = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/hubRouteTables/noneRouteTable" }]
              labels = ["none"]
            }
          }
        }
      }
    }
  }

  assert {
    condition = jsonencode(azapi_resource.this["conn"].body.properties.routingConfiguration) == jsonencode({
      associatedRouteTable = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/hubRouteTables/defaultRouteTable" }
      propagatedRouteTables = {
        ids    = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/hubRouteTables/noneRouteTable" }]
        labels = ["none"]
      }
    })
    error_message = "The actual attempt-5 routing shape must survive unchanged when no vnetRoutes or BGP back-reference exists."
  }
}

run "missing_connection_uses_azure_routing_defaults" {
  command = plan

  override_data {
    target = data.azapi_resource.existing_vpn_connection
    values = { output = {} }
  }

  assert {
    condition     = !can(azapi_resource.this["conn"].body.properties.routingConfiguration)
    error_message = "A fresh connection must omit routing rather than invent an association or propagation."
  }
}

run "explicit_routing_is_authoritative" {
  command = plan

  variables {
    vpn_site_connection = {
      conn = {
        name               = "connection"
        vpn_gateway_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/gateway"
        remote_vpn_site_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/site"
        vpn_links          = [{ name = "link", vpn_site_link_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/site/vpnSiteLinks/link" }]
        routing = {
          associated_route_table = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/hubRouteTables/custom"
          propagated_route_table = { route_table_ids = [], labels = ["custom"] }
        }
      }
    }
  }

  assert {
    condition = jsonencode(azapi_resource.this["conn"].body.properties.routingConfiguration) == jsonencode({
      associatedRouteTable  = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub/hubRouteTables/custom" }
      propagatedRouteTables = { ids = [], labels = ["custom"] }
    })
    error_message = "Explicit caller routing must replace preserved ARM routing without stale route maps or static routes."
  }

  assert {
    condition     = length(data.azapi_resource.existing_vpn_connection) == 0
    error_message = "Explicit routing must not depend on an existing-resource read."
  }
}
