mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "azurerm" {}

mock_provider "modtm" {}

mock_provider "random" {}

override_module {
  target = module.regions
  outputs = {
    regions_by_name = {
      eastus = {
        zones = ["1", "2", "3"]
      }
    }
  }
}

override_module {
  target = module.virtual_wan
}

variables {
  enable_telemetry = false

  virtual_wan_settings = {
    enabled_resources = {
      ddos_protection_plan = false
    }
  }

  virtual_hubs = {
    hub1 = {
      location          = "eastus"
      default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"

      enabled_resources = {
        firewall                              = false
        firewall_policy                       = false
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }

      virtual_network_connections = {
        connection1 = {
          name                      = "connection1"
          remote_virtual_network_id = "/subscriptions/00000000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
          routing = {
            associated_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub1/hubRouteTables/defaultRouteTable"
            static_vnet_route = {
              name                = "route-to-nva"
              address_prefixes    = ["10.20.0.0/16", "10.30.0.0/16"]
              next_hop_ip_address = "10.100.1.4"
            }
          }
        }
      }
    }
  }
}

run "root_input_retains_static_vnet_route" {
  command = apply

  assert {
    condition = (
      local.virtual_network_connections["hub1-connection1"].routing.static_vnet_route.name == "route-to-nva" &&
      local.virtual_network_connections["hub1-connection1"].routing.static_vnet_route.address_prefixes == tolist(["10.20.0.0/16", "10.30.0.0/16"]) &&
      local.virtual_network_connections["hub1-connection1"].routing.static_vnet_route.next_hop_ip_address == "10.100.1.4"
    )
    error_message = "The root input must retain every static VNet route field when forwarding the connection to the Virtual WAN module."
  }
  providers = {
    azapi   = azapi
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }
}

run "static_vnet_route_can_be_omitted" {
  command = apply

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        virtual_network_connections = {
          connection1 = merge(var.virtual_hubs.hub1.virtual_network_connections.connection1, {
            routing = {
              associated_route_table_id = var.virtual_hubs.hub1.virtual_network_connections.connection1.routing.associated_route_table_id
            }
          })
        }
      })
    }
  }

  assert {
    condition     = local.virtual_network_connections["hub1-connection1"].routing.static_vnet_route == null
    error_message = "Connections that omit static_vnet_route must retain their existing routing behavior."
  }
  providers = {
    azapi   = azapi
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }
}

run "static_vnet_route_optional_field_defaults" {
  command = apply

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        virtual_network_connections = {
          connection1 = merge(var.virtual_hubs.hub1.virtual_network_connections.connection1, {
            routing = {
              associated_route_table_id = var.virtual_hubs.hub1.virtual_network_connections.connection1.routing.associated_route_table_id
              static_vnet_route         = {}
            }
          })
        }
      })
    }
  }

  assert {
    condition = (
      local.virtual_network_connections["hub1-connection1"].routing.static_vnet_route.name == null &&
      length(local.virtual_network_connections["hub1-connection1"].routing.static_vnet_route.address_prefixes) == 0 &&
      local.virtual_network_connections["hub1-connection1"].routing.static_vnet_route.next_hop_ip_address == null
    )
    error_message = "Omitted static VNet route fields must default to null for name and next hop, and an empty list for address prefixes."
  }
  providers = {
    azapi   = azapi
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }
}
