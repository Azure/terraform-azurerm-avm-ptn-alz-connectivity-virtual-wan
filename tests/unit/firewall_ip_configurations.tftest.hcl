mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = { subscription_id = "00000000-0000-0000-0000-000000000001" }
  }
  mock_resource "azurerm_virtual_hub" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test" }
  }
  mock_resource "azurerm_virtual_wan" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/wan-test" }
  }
  mock_resource "azurerm_firewall_policy" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/firewallPolicies/policy-test" }
  }
  mock_resource "azurerm_firewall" {
    defaults = {
      virtual_hub = {
        private_ip_address  = "10.0.0.4"
        public_ip_addresses = ["198.51.100.10"]
      }
    }
  }
}
mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = { output = { firewalls = [] } }
  }
  mock_data "azapi_resource" {
    defaults = {
      output = {
        address        = "203.0.113.10", allocation_method = "Static", association = null
        ip_version     = "IPv4", location = "eastus", sku = "Standard", tier = "Regional", type = "Standard"
        virtual_wan_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/wan-test"
        zones          = ["1", "2", "3"]
      }
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
      output = {
        properties = {
          hubIPAddresses = { privateIPAddress = "10.0.0.4" }, threatIntelMode = null, additionalProperties = {}
        }
      }
    }
  }
}

override_module {
  target  = module.regions
  outputs = { regions_by_name = { eastus = { zones = ["1", "2", "3"] } } }
}

variables {
  enable_telemetry     = false
  virtual_wan_settings = { enabled_resources = { ddos_protection_plan = false } }
  virtual_hubs = {
    hub = {
      location          = "eastus"
      default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test"
      enabled_resources = {
        firewall                              = true, firewall_policy = false, bastion = false
        virtual_network_gateway_express_route = false, virtual_network_gateway_vpn = false
        private_dns_zones                     = false, private_dns_resolver = false, sidecar_virtual_network = false
      }
      firewall = {
        name               = "fw-test"
        firewall_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/firewallPolicies/policy-test"
        ip_configurations = {
          primary = {
            name                 = "explicit-primary"
            public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
          }
        }
      }
    }
  }
}

run "root_to_real_customer_leaf" {
  command = apply
  assert {
    condition     = local.firewalls["hub"].ip_configurations == var.virtual_hubs["hub"].firewall.ip_configurations
    error_message = "The root's existing merge must preserve the typed keyed map."
  }
  assert {
    condition     = output.firewall_public_ip_addresses["hub"] == tolist(["203.0.113.10"]) && output.firewall_private_ip_address["hub"] == "10.0.0.4"
    error_message = "The actual intermediate and customer leaf must return IP strings through the original root outputs."
  }
  assert {
    condition     = output.firewall_resource_ids["hub"] == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
    error_message = "The firewall identity must pass through the actual children unchanged."
  }
}

run "zero_hubs_keep_null_contract" {
  command = apply
  variables {
    virtual_hubs = {}
  }
  assert {
    condition     = output.firewall_public_ip_addresses == null && output.firewall_private_ip_address == null && output.firewall_resource_ids == null && output.firewall_resource_names == null && output.resource_id == null
    error_message = "No hubs must retain the old null outputs without invalid child indexing."
  }
}

run "disabled_firewall_keep_empty_contract" {
  command = apply
  variables {
    virtual_hubs = {
      hub = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test"
        enabled_resources = {
          firewall                              = false, firewall_policy = false, bastion = false
          virtual_network_gateway_express_route = false, virtual_network_gateway_vpn = false
          private_dns_zones                     = false, private_dns_resolver = false, sidecar_virtual_network = false
        }
      }
    }
  }
  assert {
    condition     = output.firewall_public_ip_addresses == {} && output.firewall_resource_ids == {} && length(var.virtual_hubs["hub"].firewall.ip_configurations) == 0
    error_message = "Disabled firewalls and default empty IP maps must retain the existing empty outputs."
  }
}

run "base_policy_id_survives_customer_path" {
  command = apply
  variables {
    virtual_hubs = {
      hub = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test"
        enabled_resources = {
          firewall                              = true, firewall_policy = true, bastion = false
          virtual_network_gateway_express_route = false, virtual_network_gateway_vpn = false
          private_dns_zones                     = false, private_dns_resolver = false, sidecar_virtual_network = false
        }
        firewall_policy = {
          base_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-policy/providers/Microsoft.Network/firewallPolicies/base-policy"
        }
        firewall = {
          name = "fw-test"
          ip_configurations = {
            primary = {
              name                 = "explicit-primary"
              public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
            }
          }
        }
      }
    }
  }
  assert {
    condition     = module.firewall_policy["hub"].resource.base_policy_id == var.virtual_hubs["hub"].firewall_policy.base_policy_id
    error_message = "The real firewall-policy module must still receive base_policy_id unchanged."
  }
  assert {
    condition     = output.firewall_public_ip_addresses["hub"] == tolist(["203.0.113.10"])
    error_message = "A generated child policy with a base policy must still support the real customer-IP leaf."
  }
}
