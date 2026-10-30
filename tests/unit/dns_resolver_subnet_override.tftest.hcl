# Contract tests for Azure/Azure-Landing-Zones#4289 (Request 5).
# A user subnet under the same key as a generated subnet (sidecar_virtual_network.subnets["dns_resolver"])
# replaces the generated entry as a whole object (shallow replacement). The default inbound endpoint
# follows the key, and custom endpoints reference the subnet by name.

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar-test"
    }
  }
}

mock_provider "azurerm" {
  mock_resource "azurerm_private_dns_resolver" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/dnsResolvers/pdr-test"
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

override_resource {
  target = module.virtual_network_side_car["hub1"].module.subnet["dns_resolver"].azapi_resource.subnet[0]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar-test/subnets/snet-dns-custom"
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
        private_dns_resolver                  = true
        sidecar_virtual_network               = true
      }

      private_dns_resolver = {
        subnet_address_prefix            = "10.100.251.0/28"
        default_inbound_endpoint_enabled = false
      }

      sidecar_virtual_network = {
        name          = "vnet-sidecar-test"
        address_space = ["10.100.0.0/16"]
        subnets = {
          dns_resolver = {
            name             = "snet-dns-custom"
            address_prefixes = ["10.100.252.0/28"]
            network_security_group = {
              id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkSecurityGroups/nsg-dns"
            }
            delegations = [{
              name = "Microsoft.Network.dnsResolvers"
              service_delegation = {
                name = "Microsoft.Network/dnsResolvers"
              }
            }]
          }
        }
      }
    }
  }
}

run "same_key_override_replaces_generated" {
  command = apply

  assert {
    condition = (
      toset(keys(module.virtual_network_side_car["hub1"].subnets)) == toset(["dns_resolver"]) &&
      module.virtual_network_side_car["hub1"].subnets["dns_resolver"].name == "snet-dns-custom" &&
      toset(module.virtual_network_side_car["hub1"].subnets["dns_resolver"].resource.body.properties.addressPrefixes) == toset(["10.100.252.0/28"])
    )
    error_message = "A same-key subnet must replace the generated dns_resolver subnet: one subnet, with the user's name and prefix, not the generated ones."
  }

  assert {
    condition = (
      module.virtual_network_side_car["hub1"].subnets["dns_resolver"].resource.body.properties.networkSecurityGroup.id == var.virtual_hubs.hub1.sidecar_virtual_network.subnets.dns_resolver.network_security_group.id &&
      module.virtual_network_side_car["hub1"].subnets["dns_resolver"].resource.body.properties.delegations[0].properties.serviceName == "Microsoft.Network/dnsResolvers"
    )
    error_message = "The overridden subnet must carry the user's NSG association and the restated DNS resolver delegation."
  }
}

run "override_is_shallow" {
  command = apply

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        sidecar_virtual_network = merge(var.virtual_hubs.hub1.sidecar_virtual_network, {
          subnets = {
            dns_resolver = {
              name             = "snet-dns-custom"
              address_prefixes = ["10.100.252.0/28"]
            }
          }
        })
      })
    }
  }

  assert {
    condition     = length(try(module.virtual_network_side_car["hub1"].subnets["dns_resolver"].resource.body.properties.delegations, [])) == 0
    error_message = "The override is a whole-object replacement: generated fields such as the delegation must not be deep-merged into it."
  }
}

run "subnet_generated_when_default_inbound_disabled" {
  command = apply

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        sidecar_virtual_network = merge(var.virtual_hubs.hub1.sidecar_virtual_network, {
          subnets = {}
        })
      })
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
      contains(keys(module.virtual_network_side_car["hub1"].subnets), "dns_resolver") &&
      toset(module.virtual_network_side_car["hub1"].subnets["dns_resolver"].resource.body.properties.addressPrefixes) == toset(["10.100.251.0/28"]) &&
      length(local.private_dns_resolver["hub1"].inbound_endpoints) == 0
    )
    error_message = "Current behaviour: the resolver subnet is generated whenever the resolver is enabled, even with no inbound endpoint."
  }
}

run "custom_endpoint_uses_overridden_subnet" {
  command = apply

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        private_dns_resolver = merge(var.virtual_hubs.hub1.private_dns_resolver, {
          inbound_endpoints = {
            custom = {
              name        = "in-custom"
              subnet_name = "snet-dns-custom"
            }
          }
        })
      })
    }
  }

  assert {
    condition = (
      toset(keys(local.private_dns_resolver["hub1"].inbound_endpoints)) == toset(["custom"]) &&
      local.private_dns_resolver["hub1"].inbound_endpoints["custom"].subnet_name == module.virtual_network_side_car["hub1"].subnets["dns_resolver"].name
    )
    error_message = "With the default endpoint disabled, a custom inbound endpoint must be the only endpoint and must land in the overridden subnet by name."
  }
}

run "default_inbound_endpoint_follows_override" {
  command = apply
  override_module {
    target = module.private_dns_zones
    outputs = {
      private_link_private_dns_zones_map = {}
    }
  }

  override_module {
    target = module.private_dns_zone_auto_registration
  }

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        enabled_resources = merge(var.virtual_hubs.hub1.enabled_resources, {
          private_dns_zones = true
        })
        private_dns_resolver = merge(var.virtual_hubs.hub1.private_dns_resolver, {
          default_inbound_endpoint_enabled = true
        })
      })
    }
  }

  assert {
    condition     = local.private_dns_resolver["hub1"].inbound_endpoints["dns"].subnet_name == "snet-dns-custom"
    error_message = "The default inbound endpoint is resolved by the dns_resolver key, so it must follow a same-key override."
  }
}

run "override_key_without_resolver" {
  command = apply

  variables {
    virtual_hubs = {
      hub1 = merge(var.virtual_hubs.hub1, {
        enabled_resources = merge(var.virtual_hubs.hub1.enabled_resources, {
          private_dns_resolver = false
        })
      })
    }
  }

  assert {
    condition = (
      length(module.dns_resolver) == 0 &&
      module.virtual_network_side_car["hub1"].subnets["dns_resolver"].name == "snet-dns-custom"
    )
    error_message = "With the resolver disabled, a dns_resolver key is an ordinary user subnet and no resolver is created."
  }
}