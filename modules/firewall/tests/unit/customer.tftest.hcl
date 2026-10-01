mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
    }
  }
}
mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = { firewalls = [] }
    }
  }
  mock_data "azapi_resource" {
    defaults = {
      output = {
        address           = "203.0.113.10"
        allocation_method = "Static"
        association       = null
        ip_version        = "IPv4"
        location          = "eastus"
        sku               = "Standard"
        tier              = "Regional"
        type              = "Standard"
        virtual_wan_id    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/wan-test"
        zones             = ["1", "2", "3"]
      }
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
      output = {
        properties = {
          hubIPAddresses       = { privateIPAddress = "10.0.0.4" }
          threatIntelMode      = null
          additionalProperties = {}
        }
      }
    }
  }
}

variables {
  enable_telemetry = false
  firewalls = {
    hub = {
      name                = "fw-test"
      location            = "eastus"
      resource_group_name = "rg-test"
      virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
      sku_tier            = "Standard"
      ip_configurations = {
        primary = {
          name                 = "explicit-primary"
          public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
        }
      }
    }
  }
  diagnostic_settings = {
    hub = {
      logs = {
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/logs"
      }
    }
  }
}

run "customer_optional_null_count" {
  command = apply
  assert {
    condition     = length(azurerm_firewall.fw) == 0 && length(module.customer_firewalls) == 1 && terraform_data.public_ip_mode["hub"].output == true
    error_message = "A nonempty map with omitted count must choose the singleton customer leaf, not AzureRM managed allocation."
  }
  assert {
    condition     = output.public_ip_addresses["hub"] == tolist(["203.0.113.10"]) && output.resource_object["hub"].virtual_hub[0].public_ip_count == 1
    error_message = "Customer output must contain address strings and retain the legacy virtual-hub shape."
  }
  assert {
    condition     = output.resource["hub"].ip_configuration[0].name == "explicit-primary" && output.resource["hub"].ip_configuration[0].public_ip_address_id == var.firewalls["hub"].ip_configurations["primary"].public_ip_address_id
    error_message = "The map must reach the real customer child without renaming explicit configurations."
  }
  assert {
    condition     = output.diagnostic_settings_resource_ids["hub-logs"] == "${output.resource_ids["hub"]}|diag-fw-test"
    error_message = "Diagnostic output keys, default names and composite legacy IDs must remain compatible."
  }
}

run "customer_explicit_zero_count" {
  command = apply
  variables {
    firewalls = {
      hub = {
        name                 = "fw-test"
        location             = "eastus"
        resource_group_name  = "rg-test"
        virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        sku_tier             = "Premium"
        vhub_public_ip_count = "0"
        ip_configurations = {
          primary = {
            name                 = "explicit-primary"
            public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
          }
        }
      }
    }
  }
  assert {
    condition     = length(azurerm_firewall.fw) == 0 && output.resource["hub"].sku_tier == "Premium"
    error_message = "Zero is allowed only in customer mode, including Premium."
  }
}

run "last_ip_cannot_change_mode" {
  command = plan
  variables {
    firewalls = {
      hub = {
        name                = "fw-test"
        location            = "eastus"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        sku_tier            = "Premium"
      }
    }
  }
  expect_failures = [terraform_data.public_ip_mode]
}

run "customer_reapply_after_rejected_conversion" {
  command = apply
  assert {
    condition     = output.resource_ids["hub"] == run.customer_optional_null_count.resource_ids["hub"] && terraform_data.public_ip_mode["hub"].output == true
    error_message = "A rejected mode change must leave the original customer instance and its recorded mode intact."
  }
}

run "ordinary_customer_removal" {
  command = apply
  variables {
    firewalls           = {}
    diagnostic_settings = {}
  }
  assert {
    condition     = length(module.customer_firewalls) == 0 && length(terraform_data.public_ip_mode) == 0 && length(data.azapi_resource_list.firewalls) == 0
    error_message = "Removing a customer firewall must remove its marker and diagnostics without acquiring or deleting the supplied IPs."
  }
}

run "first_adoption_managed_conversion_rejected" {
  command = plan
  override_data {
    target = data.azapi_resource_list.firewalls[0]
    values = {
      output = {
        firewalls = [{
          id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
          name = "fw-test"
          properties = {
            ipConfigurations = []
            hubIPAddresses   = { publicIPs = { count = 2, addresses = [{ address = "198.51.100.10" }, { address = "198.51.100.11" }] } }
          }
        }]
      }
    }
  }
  expect_failures = [terraform_data.public_ip_mode]
}

run "same_name_different_group_is_not_same_identity" {
  command = apply
  override_data {
    target = data.azapi_resource_list.firewalls[0]
    values = {
      output = {
        firewalls = [{
          id         = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/another-group/providers/Microsoft.Network/azureFirewalls/fw-test"
          name       = "FW-TEST"
          properties = { ipConfigurations = [] }
        }]
      }
    }
  }
  assert {
    condition     = local.existing_firewalls["hub"] == null && length(module.customer_firewalls) == 1
    error_message = "Inventory must match exact normalized RG identity, not just a reused firewall name."
  }
}
