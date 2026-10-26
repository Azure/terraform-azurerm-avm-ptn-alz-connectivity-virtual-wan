mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
    }
  }
}

mock_provider "modtm" {}

mock_provider "azurerm" {
  mock_resource "azurerm_virtual_hub" {
    defaults = {
      id                     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
      default_route_table_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/defaultRouteTable"
    }
  }
  mock_resource "azurerm_firewall" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
    }
  }
}

mock_provider "random" {}
run "additional_private_traffic_route" {
  command = apply

  module {
    source = "./modules/virtual-wan"
  }

  variables {
    location            = "eastus"
    resource_group_name = "rg-test"
    virtual_wan_name    = "vwan-test"
    virtual_wan_id      = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"

    virtual_hubs = {
      hub = {
        name                                   = "hub-test"
        location                               = "eastus"
        resource_group_name                    = "rg-test"
        address_prefix                         = "10.0.0.0/23"
        hub_routing_preference                 = "ExpressRoute"
        sku                                    = "Standard"
        tags                                   = {}
        virtual_router_auto_scale_min_capacity = 2
      }
    }

    firewalls = {
      hub = {
        name            = "fw-test"
        sku_tier        = "Standard"
        virtual_hub_key = "hub"
      }
    }

    private_traffic_routes = {
      hub-carrier_grade_nat = {
        name                  = "private_traffic"
        destinations          = ["100.64.0.0/16"]
        next_hop_firewall_key = "hub"
        virtual_hub_key       = "hub"
      }
    }
  }

  assert {
    condition = (
      azurerm_virtual_hub_route_table_route.private_traffic_route["hub-carrier_grade_nat"].name == "private_traffic"
    )
    error_message = "The configured additional private-traffic route must be created."
  }

  assert {
    condition = (
      contains(
        azurerm_virtual_hub_route_table_route.private_traffic_route["hub-carrier_grade_nat"].destinations,
        "100.64.0.0/16"
      )
    )
    error_message = "The additional private-traffic route must contain the configured CIDR."
  }

  assert {
    condition = (
      azurerm_virtual_hub_route_table_route.private_traffic_route["hub-carrier_grade_nat"].route_table_id ==
      "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test/hubRouteTables/defaultRouteTable"
    )
    error_message = "The additional private-traffic route must target the Virtual Hub default route table."
  }

  assert {
    condition = (
      azurerm_virtual_hub_route_table_route.private_traffic_route["hub-carrier_grade_nat"].next_hop ==
      "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
    )
    error_message = "The additional private-traffic route must use the configured Azure Firewall as the next hop."
  }
}