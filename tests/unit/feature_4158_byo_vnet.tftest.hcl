# Baseline reproduction for Azure/Azure-Landing-Zones#4158.
# Verifies current behavior when Private DNS auto-registration is enabled
# while the module-managed sidecar virtual network is disabled.

mock_provider "azapi" {}
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
      location = "eastus"
      sidecar_virtual_network = {
        resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-byo-vnet/providers/Microsoft.Network/virtualNetworks/vnet-byo-sidecar"
      }

      default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"

      enabled_resources = {
        firewall                              = false
        firewall_policy                       = false
        bastion                               = true
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = true
        private_dns_resolver                  = true
        sidecar_virtual_network               = true
      }
      private_dns_resolver = {
        subnet_name = "dns-resolver-byo"
      }


      private_dns_zones = {
        auto_registration_zone_enabled = true
      }
    }
  }
}

run "reproduce_4158_no_sidecar_with_dns_auto_registration" {
  command = plan
}

override_module {
  target = module.private_dns_zones
  outputs = {
    private_link_private_dns_zones_map = {}
  }
}

override_module {
  target = module.dns_resolver
}

run "validate_4158_byo_vnet_resolution" {
  command = plan

  assert {
    condition     = local.sidecar_virtual_network_resource_ids["hub1"] == var.virtual_hubs["hub1"].sidecar_virtual_network.resource_id
    error_message = "The BYO VNet ID was not selected as the effective Sidecar VNet ID."
  }

  assert {
    condition     = length(module.virtual_network_side_car) == 0
    error_message = "A new Sidecar VNet was created even though a BYO VNet ID was supplied."
  }

  assert {
    condition     = local.private_dns_resolver["hub1"].inbound_endpoints["dns"].subnet_name == "dns-resolver-byo"
    error_message = "The existing BYO DNS Resolver subnet name was not used."
  }
}

override_module {
  target = module.bastion_public_ip
  outputs = {
    public_ip_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-bastion-test"
  }
}

override_module {
  target = module.bastion_host
}

run "validate_4158_byo_vnet_bastion_subnet" {
  command = plan

  assert {
    condition     = local.bastion_hosts["hub1"].ip_configuration.subnet_id == "${var.virtual_hubs["hub1"].sidecar_virtual_network.resource_id}/subnets/AzureBastionSubnet"
    error_message = "Bastion did not use AzureBastionSubnet from the supplied BYO VNet."
  }
}

run "validate_4158_byo_vnet_private_dns_link" {
  command = plan

  assert {
    condition     = local.private_dns_zones_virtual_network_link_default_virtual_networks["hub1"].virtual_network_resource_id == var.virtual_hubs["hub1"].sidecar_virtual_network.resource_id
    error_message = "The default Private DNS VNet link did not use the supplied BYO VNet ID."
  }
}

run "validate_4158_byo_vnet_output" {
  command = plan

  assert {
    condition     = output.sidecar_virtual_network_resource_ids["hub1"] == var.virtual_hubs["hub1"].sidecar_virtual_network.resource_id
    error_message = "The Sidecar VNet resource ID output did not return the supplied BYO VNet ID."
  }
}

run "validate_4158_byo_vnet_hub_connection" {
  command = plan

  assert {
    condition     = local.virtual_network_connections_side_car["private_dns_vnet_hub1"].remote_virtual_network_id == var.virtual_hubs["hub1"].sidecar_virtual_network.resource_id
    error_message = "The automatic Virtual Hub connection did not use the supplied BYO VNet ID."
  }
}
