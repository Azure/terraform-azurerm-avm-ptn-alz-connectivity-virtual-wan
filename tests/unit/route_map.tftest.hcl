# Covers the TFFR6/TFFR7/TFFR8 inputs added to the route-map submodule.

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/routeMaps/rm-test"
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
  outputs = {
    virtual_hub_resource_ids = {
      hub1 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
    }
  }
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
    }
  }

  route_maps = {
    main = {
      name            = "rm-test"
      virtual_hub_key = "hub1"
      rules = [{
        name                 = "prepend-as-path"
        next_step_if_matched = "Continue"
        actions = [{
          type = "Add"
          parameters = [{
            as_path = ["65001"]
          }]
        }]
        match_criteria = [{
          match_condition = "Equals"
          route_prefix    = ["10.0.0.0/16"]
        }]
      }]
    }
  }
}

run "route_map_defaults" {
  command = plan

  assert {
    condition     = module.route_map["main"].resource.type == "Microsoft.Network/virtualHubs/routeMaps@2025-05-01"
    error_message = "The default resource_types value must keep the route map on its original API version."
  }

  assert {
    condition = (
      module.route_map["main"].resource.name == "rm-test" &&
      module.route_map["main"].resource.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
    )
    error_message = "Route map identity must resolve from the supplied name and virtual hub key."
  }
}

run "route_map_accepts_operational_inputs" {
  command = plan

  variables {
    ignore_body_changes = {
      virtual_hubs_route_maps = {
        virtual_hubs_route_maps = ["properties.rules"]
      }
    }
    retry = {
      error_message_regex = ["ReferencedResourceNotProvisioned"]
    }
    timeouts = {
      create = "45m"
    }
  }

  assert {
    condition     = module.route_map["main"].resource.type == "Microsoft.Network/virtualHubs/routeMaps@2025-05-01"
    error_message = "Supplying the AzAPI operational inputs must not disturb the route map resource."
  }
}

run "route_map_ignore_body_changes_rejects_empty_path" {
  command = plan

  variables {
    ignore_body_changes = {
      virtual_hubs_route_maps = {
        virtual_hubs_route_maps = ["   "]
      }
    }
  }

  expect_failures = [var.ignore_body_changes]
}
