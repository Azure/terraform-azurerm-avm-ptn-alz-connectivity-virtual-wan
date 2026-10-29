# Regression tests for Azure/Azure-Landing-Zones#4289 item 4.
# Verifies Azure Bastion can use an existing AzureBastionSubnet outside the sidecar virtual network,
# and that the default (subnet_id unset) behaviour is unchanged.
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

override_module {
  target = module.virtual_network_side_car
  outputs = {
    resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar"
    subnets = {
      bastion = {
        name        = "AzureBastionSubnet"
        resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar/subnets/AzureBastionSubnet"
      }
    }
  }
}

override_module {
  target = module.bastion_public_ip
  outputs = {
    public_ip_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-bastion"
    public_ip_address = "203.0.113.10"
  }
}

override_module {
  target = module.bastion_host
}

variables {
  enable_telemetry = false
  virtual_wan_settings = {
    enabled_resources = {
      ddos_protection_plan = false
    }
  }
}

run "default_uses_generated_sidecar_subnet" {
  command = apply
  variables {
    virtual_hubs = {
      hub1 = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        enabled_resources = {
          firewall                              = false
          firewall_policy                       = false
          bastion                               = true
          virtual_network_gateway_express_route = false
          virtual_network_gateway_vpn           = false
          private_dns_zones                     = false
          private_dns_resolver                  = false
          sidecar_virtual_network               = true
        }
      }
    }
  }
  assert {
    condition     = contains(keys(local.subnets["hub1"]), "bastion")
    error_message = "Default behaviour must still generate the AzureBastionSubnet in the sidecar virtual network."
  }
  assert {
    condition     = local.bastion_hosts["hub1"].ip_configuration.subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-sidecar/subnets/AzureBastionSubnet"
    error_message = "Default behaviour must place Bastion in the sidecar subnet."
  }
}

run "existing_subnet_with_sidecar_enabled" {
  command = apply
  variables {
    virtual_hubs = {
      hub1 = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        enabled_resources = {
          firewall                              = false
          firewall_policy                       = false
          bastion                               = true
          virtual_network_gateway_express_route = false
          virtual_network_gateway_vpn           = false
          private_dns_zones                     = false
          private_dns_resolver                  = false
          sidecar_virtual_network               = true
        }
        bastion = {
          subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-svc/providers/Microsoft.Network/virtualNetworks/vnet-bastion/subnets/AzureBastionSubnet"
        }
      }
    }
  }
  assert {
    condition     = !contains(keys(local.subnets["hub1"]), "bastion")
    error_message = "The sidecar must not get an AzureBastionSubnet when bastion.subnet_id is supplied."
  }
  assert {
    condition     = local.bastion_hosts["hub1"].ip_configuration.subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-svc/providers/Microsoft.Network/virtualNetworks/vnet-bastion/subnets/AzureBastionSubnet"
    error_message = "Bastion must use the supplied subnet."
  }
}

run "existing_subnet_with_sidecar_disabled" {
  command = apply
  variables {
    virtual_hubs = {
      hub1 = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        enabled_resources = {
          firewall                              = false
          firewall_policy                       = false
          bastion                               = true
          virtual_network_gateway_express_route = false
          virtual_network_gateway_vpn           = false
          private_dns_zones                     = false
          private_dns_resolver                  = false
          sidecar_virtual_network               = false
        }
        bastion = {
          subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-svc/providers/Microsoft.Network/virtualNetworks/vnet-bastion/subnets/AzureBastionSubnet"
        }
      }
    }
  }
  assert {
    condition     = length(local.sidecar_virtual_networks) == 0
    error_message = "No sidecar virtual network should be created."
  }
  assert {
    condition     = local.bastions_enabled["hub1"]
    error_message = "Bastion must be enabled without the sidecar when bastion.subnet_id is supplied."
  }
  assert {
    condition     = local.bastion_hosts["hub1"].ip_configuration.subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-svc/providers/Microsoft.Network/virtualNetworks/vnet-bastion/subnets/AzureBastionSubnet"
    error_message = "Bastion must use the supplied subnet when the sidecar is disabled."
  }
  assert {
    condition     = local.bastion_hosts["hub1"].resource_group_name == "rg-test"
    error_message = "Bastion resource group must still default from default_parent_id when the sidecar is disabled."
  }
}

run "sidecar_disabled_without_subnet_keeps_bastion_off" {
  command = apply
  variables {
    virtual_hubs = {
      hub1 = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        enabled_resources = {
          firewall                              = false
          firewall_policy                       = false
          bastion                               = true
          virtual_network_gateway_express_route = false
          virtual_network_gateway_vpn           = false
          private_dns_zones                     = false
          private_dns_resolver                  = false
          sidecar_virtual_network               = false
        }
      }
    }
  }
  assert {
    condition     = !local.bastions_enabled["hub1"] && length(local.bastion_hosts) == 0
    error_message = "Without bastion.subnet_id, disabling the sidecar must still disable Bastion (unchanged behaviour)."
  }
}

run "rejects_subnet_not_named_azurebastionsubnet" {
  command = plan
  variables {
    virtual_hubs = {
      hub1 = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        bastion = {
          subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-svc/providers/Microsoft.Network/virtualNetworks/vnet-bastion/subnets/snet-bastion"
        }
      }
    }
  }
  expect_failures = [var.virtual_hubs]
}

run "rejects_subnet_id_with_subnet_address_prefix" {
  command = plan
  variables {
    virtual_hubs = {
      hub1 = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        bastion = {
          subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-svc/providers/Microsoft.Network/virtualNetworks/vnet-bastion/subnets/AzureBastionSubnet"
          subnet_address_prefix = "10.0.1.0/26"
        }
      }
    }
  }
  expect_failures = [var.virtual_hubs]
}