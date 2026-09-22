# Compatibility test for Azure/Azure-Landing-Zones#4277.
# Verifies the sidecar VNet dependency upgrade keeps the existing subnet inputs and module outputs.

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar-test"
    }
  }
}

mock_provider "azurerm" {
  mock_data "azurerm_public_ip" {
    defaults = {
      id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-bastion"
      zones = ["1", "2", "3"]
    }
  }
}

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
        sidecar_virtual_network               = true
      }

      sidecar_virtual_network = {
        name          = "vnet-sidecar-test"
        address_space = ["10.100.0.0/16"]
      }
    }
  }
}

run "default_sidecar" {
  command = apply

  assert {
    condition     = keys(module.virtual_network_side_car) == ["hub1"]
    error_message = "The dependency upgrade must preserve the sidecar module instance key."
  }

  assert {
    condition     = module.virtual_network_side_car["hub1"].resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar-test"
    error_message = "The default sidecar must retain its virtual network resource ID output."
  }

  assert {
    condition     = length(local.subnets["hub1"]) == 0
    error_message = "A sidecar without custom, DNS resolver or Bastion subnets must not create subnets."
  }
}

run "custom_subnet_contract" {
  command = apply

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        sidecar_virtual_network = merge(var.virtual_hubs.hub1.sidecar_virtual_network, {
          subnets = {
            workload = {
              name             = "snet-workload"
              address_prefixes = ["10.100.1.0/24"]
              nat_gateway = {
                id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/natGateways/nat-test"
              }
              network_security_group = {
                id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkSecurityGroups/nsg-test"
              }
              route_table = {
                id                           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/routeTables/rt-test"
                assign_generated_route_table = false
              }
              service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
              delegations = [{
                name = "web"
                service_delegation = {
                  name = "Microsoft.Web/serverFarms"
                }
              }]
              private_endpoint_network_policies_enabled     = false
              private_link_service_network_policies_enabled = false
              default_outbound_access_enabled               = true
            }
          }
        })
      })
    }
  }

  assert {
    condition = toset([
      for endpoint in module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.serviceEndpoints : endpoint.service
    ]) == toset(["Microsoft.Storage", "Microsoft.Sql"])
    error_message = "The dependency upgrade must retain names-only service_endpoints from the existing endpoint fix."
  }

  assert {
    condition = (
      module.virtual_network_side_car["hub1"].subnets["workload"].name == "snet-workload" &&
      toset(module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.addressPrefixes) == toset(["10.100.1.0/24"]) &&
      module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.natGateway.id == var.virtual_hubs.hub1.sidecar_virtual_network.subnets.workload.nat_gateway.id &&
      module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.networkSecurityGroup.id == var.virtual_hubs.hub1.sidecar_virtual_network.subnets.workload.network_security_group.id &&
      module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.routeTable.id == var.virtual_hubs.hub1.sidecar_virtual_network.subnets.workload.route_table.id
    )
    error_message = "Subnet identity, prefixes, NAT, NSG and external route table associations must remain unchanged."
  }

  assert {
    condition = (
      module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.defaultOutboundAccess &&
      module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.privateLinkServiceNetworkPolicies == "Disabled" &&
      !contains(keys(module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties), "privateEndpointNetworkPolicies") &&
      module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.delegations[0].properties.serviceName == "Microsoft.Web/serverFarms"
    )
    error_message = "Subnet outbound access, private network policies and delegation must retain their configured values."
  }
}

# ignore_body_changes is write-only provider state, so its value cannot be read back here.
run "subnet_ignore_body_changes_passthrough" {
  command = apply

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        sidecar_virtual_network = merge(var.virtual_hubs.hub1.sidecar_virtual_network, {
          subnets = {
            workload = {
              name                = "snet-workload"
              address_prefixes    = ["10.100.1.0/24"]
              ignore_body_changes = ["properties.routeTable"]
            }
          }
        })
      })
    }
  }

  assert {
    condition = (
      module.virtual_network_side_car["hub1"].subnets["workload"].name == "snet-workload" &&
      toset(module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.addressPrefixes) == toset(["10.100.1.0/24"])
    )
    error_message = "Supplying ignore_body_changes must not disturb subnet identity or address prefixes."
  }

  assert {
    condition     = try(module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.routeTable, null) == null
    error_message = "An ignored path must be left unmanaged, so no route table may be sent for this subnet."
  }
}

run "module_level_ignore_body_changes" {
  command = apply

  variables {
    ignore_body_changes = {
      virtual_networks = ["tags"]
      virtual_networks_subnets = {
        virtual_networks_subnets = ["properties.routeTable"]
      }
    }

    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        sidecar_virtual_network = merge(var.virtual_hubs.hub1.sidecar_virtual_network, {
          subnets = {
            workload = {
              name             = "snet-workload"
              address_prefixes = ["10.100.1.0/24"]
            }
          }
        })
      })
    }
  }

  assert {
    condition = (
      module.virtual_network_side_car["hub1"].name == "vnet-sidecar-test" &&
      module.virtual_network_side_car["hub1"].subnets["workload"].name == "snet-workload" &&
      try(module.virtual_network_side_car["hub1"].subnets["workload"].resource.body.properties.routeTable, null) == null
    )
    error_message = "The shared ignore_body_changes slots must not disturb the virtual network or its subnets."
  }
}

run "ignore_body_changes_rejects_empty_path" {
  command = plan

  variables {
    ignore_body_changes = {
      virtual_networks_subnets = {
        virtual_networks_subnets = ["   "]
      }
    }
  }

  expect_failures = [var.ignore_body_changes]
}

run "generated_dns_and_bastion_subnets" {
  command   = apply
  state_key = "generated_subnets"

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        enabled_resources = merge(var.virtual_hubs.hub1.enabled_resources, {
          bastion              = true
          private_dns_resolver = true
        })
        bastion = {
          subnet_address_prefix = "10.100.250.0/26"
        }
        private_dns_resolver = {
          subnet_address_prefix = "10.100.251.0/28"
        }
      })
    }
  }

  override_module {
    target = module.bastion_public_ip["hub1"]
    outputs = {
      public_ip_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-bastion"
    }
  }

  override_resource {
    target = module.virtual_network_side_car["hub1"].module.subnet["bastion"].azapi_resource.subnet[0]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar-test/subnets/AzureBastionSubnet"
    }
  }

  override_resource {
    target = module.virtual_network_side_car["hub1"].module.subnet["dns_resolver"].azapi_resource.subnet[0]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar-test/subnets/dns-resolver"
    }
  }

  assert {
    condition = (
      toset(keys(module.virtual_network_side_car["hub1"].subnets)) == toset(["bastion", "dns_resolver"]) &&
      module.virtual_network_side_car["hub1"].subnets["bastion"].name == "AzureBastionSubnet" &&
      toset(module.virtual_network_side_car["hub1"].subnets["bastion"].resource.body.properties.addressPrefixes) == toset(["10.100.250.0/26"]) &&
      toset(module.virtual_network_side_car["hub1"].subnets["dns_resolver"].resource.body.properties.addressPrefixes) == toset(["10.100.251.0/28"]) &&
      module.virtual_network_side_car["hub1"].subnets["dns_resolver"].resource.body.properties.delegations[0].properties.serviceName == "Microsoft.Network/dnsResolvers"
    )
    error_message = "Generated DNS resolver and Bastion subnets must preserve their keys, names, prefixes and delegation."
  }

  assert {
    condition = alltrue([
      for subnet_key in ["bastion", "dns_resolver"] :
      !module.virtual_network_side_car["hub1"].subnets[subnet_key].resource.body.properties.defaultOutboundAccess
    ])
    error_message = "Generated subnets must keep outbound access disabled by default."
  }

  assert {
    condition = (
      local.bastion_hosts.hub1.ip_configuration.subnet_id == module.virtual_network_side_car["hub1"].subnets["bastion"].resource_id &&
      module.virtual_network_side_car["hub1"].subnets["dns_resolver"].name == var.virtual_hubs.hub1.private_dns_resolver.subnet_name
    )
    error_message = "Subnet resource ID and name outputs consumed by Bastion and DNS resolver must remain compatible."
  }
}

run "multiple_sidecars" {
  command   = apply
  state_key = "multiple_sidecars"

  variables {
    virtual_hubs = {
      hub1 = var.virtual_hubs.hub1
      hub2 = merge(var.virtual_hubs.hub1, {
        sidecar_virtual_network = {
          name          = "vnet-sidecar-second"
          address_space = ["10.101.0.0/16"]
        }
      })
    }
  }

  override_resource {
    target = module.virtual_network_side_car["hub2"].azapi_resource.vnet
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar-second"
    }
  }

  assert {
    condition = (
      toset(keys(module.virtual_network_side_car)) == toset(["hub1", "hub2"]) &&
      module.virtual_network_side_car["hub1"].resource_id != module.virtual_network_side_car["hub2"].resource_id &&
      alltrue([
        for hub_key in ["hub1", "hub2"] :
        local.virtual_network_connections_side_car["private_dns_vnet_${hub_key}"].remote_virtual_network_id == module.virtual_network_side_car[hub_key].resource_id &&
        local.virtual_network_connections_side_car["private_dns_vnet_${hub_key}"].virtual_hub_key == hub_key
      ])
    )
    error_message = "Each sidecar must retain its own module key and connect to the corresponding virtual hub."
  }
}

run "sidecar_disabled" {
  command   = apply
  state_key = "sidecar_disabled"

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        enabled_resources = merge(var.virtual_hubs.hub1.enabled_resources, {
          sidecar_virtual_network = false
        })
      })
    }
  }

  assert {
    condition     = length(module.virtual_network_side_car) == 0 && length(local.virtual_network_connections_side_car) == 0
    error_message = "Disabling the sidecar must not create a VNet or a sidecar connection."
  }
}