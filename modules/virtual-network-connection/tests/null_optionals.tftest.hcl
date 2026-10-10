# See `modules/site-to-site-vpn-site/tests/null_optionals.tftest.hcl` for why this exists:
# An earlier test apply failed at apply, not at plan, because the inputs were unknown at plan
# time and the locals were never evaluated. Known inputs force evaluation.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

mock_provider "azapi" {}

variables {
  resource_types = {
    network_virtual_hubs_hub_virtual_network_connections = "Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2025-07-01"
  }
}

# `routing` omitted entirely -- the whole `routingConfiguration` branch is skipped.
run "routing_null" {
  command = plan

  variables {
    virtual_network_connections = {
      conn_a = {
        name                      = "conn-null"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
      }
    }
  }

  # AzureRM guards the whole block on `if v, ok := d.GetOk("routing")`, so no routing
  # means no `routingConfiguration` key -- not an empty object.
  assert {
    condition     = !can(azapi_resource.this["conn_a"].body.properties.routingConfiguration)
    error_message = "routingConfiguration must be absent when routing is null, matching AzureRM's d.GetOk guard."
  }

  # Schema default false, sent unconditionally by AzureRM.
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.enableInternetSecurity == false
    error_message = "enableInternetSecurity must be the AzureRM schema default false when unset."
  }
}

# `routing` present but every optional inside it omitted. This is the shape that exercises
# the null-into-length paths on `labels` and `route_table_ids`: the attributes carry an
# `optional(list(string), [])` default here, so they arrive as empty lists rather than
# nulls, and `propagated_route_table` itself is omitted so the branch is skipped.
run "routing_set_children_null" {
  command = plan

  variables {
    virtual_network_connections = {
      conn_a = {
        name                      = "conn-partial"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
        routing = {
          associated_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/defaultRouteTable"
        }
      }
    }
  }

  # 🔴 Two literals AzureRM's expander always sent and the module never exposed. If these
  # ever stop being emitted, a migrated connection silently changes its static-route
  # behaviour on the first post-upgrade apply. That is the whole point of the migration.
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.vnetRoutes.staticRoutesConfig.propagateStaticRoutes == true
    error_message = "propagateStaticRoutes must reproduce AzureRM's unexposed schema default true."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.vnetRoutes.staticRoutesConfig.vnetLocalRouteOverrideCriteria == "Contains"
    error_message = "vnetLocalRouteOverrideCriteria must reproduce AzureRM's unexposed schema default \"Contains\"."
  }

  assert {
    condition     = !can(azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables)
    error_message = "propagatedRouteTables must be absent when propagated_route_table is null."
  }

  assert {
    condition     = !can(azapi_resource.this["conn_a"].body.properties.routingConfiguration.vnetRoutes.staticRoutes)
    error_message = "staticRoutes must be absent when static_vnet_route is null."
  }
}

# `propagated_route_table` present with its list children left at their `[]` defaults.
# `ignore_null_property` prunes the resulting nulls, so both keys must be absent.
run "propagated_route_table_empty_lists" {
  command = plan

  variables {
    virtual_network_connections = {
      conn_a = {
        name                      = "conn-empty-lists"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
        routing = {
          associated_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/defaultRouteTable"
          propagated_route_table    = {}
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables.labels == null
    error_message = "labels must be null (and so pruned by ignore_null_property) when the list is empty."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables.ids == null
    error_message = "ids must be null (and so pruned by ignore_null_property) when the list is empty."
  }
}

run "all_optionals_set" {
  command = plan

  variables {
    virtual_network_connections = {
      conn_a = {
        name                      = "conn-full"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
        internet_security_enabled = true
        routing = {
          associated_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/defaultRouteTable"
          propagated_route_table = {
            route_table_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/noneRouteTable"]
            labels          = ["default", "vnet"]
          }
          static_vnet_route = {
            name                = "static-a"
            address_prefixes    = ["10.50.0.0/16"]
            next_hop_ip_address = "10.0.0.4"
          }
        }
      }
    }
  }

  # ARM takes SubResource objects here, not bare ID strings. Sending the strings would be
  # accepted as a shape and then silently mean nothing.
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables.ids[0].id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/noneRouteTable"
    error_message = "propagatedRouteTables.ids must wrap each route table ID in a SubResource object."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables.labels == tolist(["default", "vnet"])
    error_message = "propagatedRouteTables.labels must carry the configured labels verbatim."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.vnetRoutes.staticRoutes[0].nextHopIpAddress == "10.0.0.4"
    error_message = "staticRoutes must be emitted when static_vnet_route is set."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.enableInternetSecurity == true
    error_message = "enableInternetSecurity must carry the configured value."
  }
}

run "empty_map" {
  command = plan

  variables {
    virtual_network_connections = {}
  }

  assert {
    condition     = length(azapi_resource.this) == 0
    error_message = "An empty virtual_network_connections map must create no resources."
  }
}

# The timeout defaults come from `azurerm_virtual_hub_connection`, which defaulted
# create/update/delete to 60m -- NOT the blanket 30m the migrated module started with.
# virtual_hub_connection_resource.go L37-L42 at
# terraform-provider-azurerm 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0).
run "timeout_defaults_match_azurerm_virtual_hub_connection" {
  command = plan

  variables {
    virtual_network_connections = {
      conn_a = {
        name                      = "conn-timeouts"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
      }
    }
  }

  assert {
    condition     = azapi_resource.this["conn_a"].timeouts.create == "60m" && azapi_resource.this["conn_a"].timeouts.update == "60m" && azapi_resource.this["conn_a"].timeouts.delete == "60m"
    error_message = "azurerm_virtual_hub_connection defaulted create/update/delete to 60m, not 30m."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].timeouts.read == "5m"
    error_message = "azurerm_virtual_hub_connection defaulted read to 5m."
  }
}

# The public variable shape is unchanged: an explicit value still wins, and an attribute the
# consumer leaves unset still falls back to the AzureRM default.
run "partial_timeouts_fall_back" {
  command = plan

  variables {
    timeouts = { create = "45m" }
    virtual_network_connections = {
      conn_a = {
        name                      = "conn-timeouts"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
      }
    }
  }

  assert {
    condition     = azapi_resource.this["conn_a"].timeouts.create == "45m" && azapi_resource.this["conn_a"].timeouts.delete == "60m"
    error_message = "An explicit attribute must win; an unset one must fall back to the AzureRM default."
  }
}

# `var.timeouts = null` still omits the block entirely, exactly as before this change.
run "null_timeouts_omit_the_block" {
  command = plan

  variables {
    timeouts = null
    virtual_network_connections = {
      conn_a = {
        name                      = "conn-timeouts"
        virtual_hub_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
      }
    }
  }

  assert {
    condition     = azapi_resource.this["conn_a"].timeouts == null
    error_message = "Passing var.timeouts = null must keep omitting the timeouts block."
  }
}
