mock_provider "modtm" {}
mock_provider "random" {}
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
}

variables {
  enable_telemetry = false
  name             = "fw-test"
  parent_id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test"
  location         = "eastus"
  virtual_hub_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
  ip_configurations = {
    primary = {
      name                 = "internet-primary"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
    }
  }
}

run "reject_existing_managed_firewall" {
  command = plan
  override_data {
    target = data.azapi_resource_list.firewalls
    values = {
      output = { firewalls = [{ name = "FW-TEST", id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/FW-TEST", properties = { ipConfigurations = [], hubIPAddresses = { publicIPs = { count = 1 } } } }] }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_another_firewall_association" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address     = "203.0.113.10", allocation_method = "Static"
        association = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test-other/azureFirewallIpConfigurations/internet-primary"
        ip_version  = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_non_firewall_association" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address     = "203.0.113.10", allocation_method = "Static"
        association = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/networkInterfaces/nic/ipConfigurations/ipconfig1"
        ip_version  = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_basic_public_ip" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address    = "203.0.113.10", allocation_method = "Static", association = null
        ip_version = "IPv4", location = "eastus", sku = "Basic", tier = "Regional"
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_dynamic_public_ip" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address    = "203.0.113.10", allocation_method = "Dynamic", association = null
        ip_version = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_ipv6" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address    = "2001:db8::1", allocation_method = "Static", association = null
        ip_version = "IPv6", location = "eastus", sku = "Standard", tier = "Regional"
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_zonal_firewall_with_non_zonal_public_ip" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address    = "203.0.113.10", allocation_method = "Static", association = null
        ip_version = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones      = []
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_global_tier" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address    = "203.0.113.10", allocation_method = "Static", association = null
        ip_version = "IPv4", location = "eastus", sku = "Standard", tier = "Global"
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_public_ip_region_mismatch" {
  command = plan
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address    = "203.0.113.10", allocation_method = "Static", association = null
        ip_version = "IPv4", location = "westus", sku = "Standard", tier = "Regional"
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_basic_hub" {
  command = plan
  override_data {
    target = data.azapi_resource.virtual_wan
    values = { output = { type = "Basic" } }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_hub_region_mismatch" {
  command = plan
  override_data {
    target = data.azapi_resource.virtual_hub
    values = {
      output = {
        location       = "westus"
        virtual_wan_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/wan-test"
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_hub_subscription_mismatch" {
  command = plan
  variables {
    virtual_hub_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
  }
  expect_failures = [azapi_resource.this]
}

run "reject_public_ip_subscription_mismatch" {
  command = plan
  variables {
    ip_configurations = {
      primary = {
        name                 = "internet-primary"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "reject_empty_customer_map" {
  command = plan
  variables { ip_configurations = {} }
  expect_failures = [var.ip_configurations]
}

run "reject_null_customer_entry" {
  command = plan
  variables { ip_configurations = { primary = null } }
  expect_failures = [var.ip_configurations]
}

run "reject_null_public_ip_id" {
  command = plan
  variables { ip_configurations = { primary = { name = "internet-primary", public_ip_address_id = null } } }
  expect_failures = [var.ip_configurations]
}

run "reject_malformed_public_ip_id" {
  command = plan
  variables { ip_configurations = { primary = { name = "internet-primary", public_ip_address_id = "not-an-arm-id" } } }
  expect_failures = [var.ip_configurations]
}

run "reject_invalid_configuration_name" {
  command = plan
  variables {
    ip_configurations = {
      primary = {
        name                 = " "
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
      }
    }
  }
  expect_failures = [var.ip_configurations]
}

run "reject_duplicate_names_ignoring_case" {
  command = plan
  variables {
    ip_configurations = {
      primary = {
        name                 = "PRIMARY"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
      }
      secondary = {
        name                 = "primary"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-secondary"
      }
    }
  }
  expect_failures = [var.ip_configurations]
}

run "reject_duplicate_ids_ignoring_case" {
  command = plan
  variables {
    ip_configurations = {
      primary = {
        name                 = "primary"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
      }
      secondary = {
        name                 = "secondary"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/RG-IPS/providers/Microsoft.Network/publicIPAddresses/PIP-PRIMARY"
      }
    }
  }
  expect_failures = [var.ip_configurations]
}

run "reject_basic_firewall" {
  command = plan
  variables { sku_tier = "Basic" }
  expect_failures = [var.sku_tier]
}

run "reject_ip_drift_suppression" {
  command = plan
  variables { ignore_body_changes = { network_azure_firewalls = ["properties.ipConfigurations"] } }
  expect_failures = [var.ignore_body_changes]
}
