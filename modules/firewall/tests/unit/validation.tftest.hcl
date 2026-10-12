mock_provider "azapi" {}
mock_provider "azurerm" {}
mock_provider "modtm" {}
mock_provider "random" {}

run "reject_zero_without_customer_ips" {
  command = plan
  variables {
    firewalls = {
      hub = {
        name                 = "fw-test", location = "eastus", resource_group_name = "rg-test", sku_tier = "Standard"
        virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        vhub_public_ip_count = "0"
      }
    }
  }
  expect_failures = [var.firewalls]
}

run "reject_negative_count" {
  command = plan
  variables {
    firewalls = {
      hub = {
        name                 = "fw-test", location = "eastus", resource_group_name = "rg-test", sku_tier = "Standard"
        virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        vhub_public_ip_count = "-1"
      }
    }
  }
  expect_failures = [var.firewalls]
}

run "reject_fractional_count" {
  command = plan
  variables {
    firewalls = {
      hub = {
        name                 = "fw-test", location = "eastus", resource_group_name = "rg-test", sku_tier = "Standard"
        virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        vhub_public_ip_count = "1.5"
      }
    }
  }
  expect_failures = [var.firewalls]
}

run "reject_nonnumeric_count" {
  command = plan
  variables {
    firewalls = {
      hub = {
        name                 = "fw-test", location = "eastus", resource_group_name = "rg-test", sku_tier = "Standard"
        virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        vhub_public_ip_count = "not-a-count"
      }
    }
  }
  expect_failures = [var.firewalls]
}

run "reject_positive_count_with_customer_ips" {
  command = plan
  variables {
    firewalls = {
      hub = {
        name                 = "fw-test", location = "eastus", resource_group_name = "rg-test", sku_tier = "Standard"
        virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        vhub_public_ip_count = "1"
        ip_configurations = {
          primary = {
            name                 = "primary"
            public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-one"
          }
        }
      }
    }
  }
  expect_failures = [var.firewalls]
}

run "reject_cross_firewall_ip_reuse" {
  command = plan
  variables {
    firewalls = {
      first = {
        name           = "fw-first", location = "eastus", resource_group_name = "rg-test", sku_tier = "Standard"
        virtual_hub_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-first"
        ip_configurations = {
          primary = {
            name                 = "primary"
            public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-one"
          }
        }
      }
      second = {
        name           = "fw-second", location = "eastus", resource_group_name = "rg-test", sku_tier = "Premium"
        virtual_hub_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-second"
        ip_configurations = {
          other = {
            name                 = "other"
            public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/RG-IPS/providers/Microsoft.Network/publicIPAddresses/PIP-ONE"
          }
        }
      }
    }
  }
  expect_failures = [var.firewalls]
}

run "reject_duplicate_case_insensitive_names" {
  command = plan
  variables {
    firewalls = {
      hub = {
        name           = "fw-test", location = "eastus", resource_group_name = "rg-test", sku_tier = "Standard"
        virtual_hub_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        ip_configurations = {
          first = {
            name                 = "Primary"
            public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-one"
          }
          second = {
            name                 = "PRIMARY"
            public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-two"
          }
        }
      }
    }
  }
  expect_failures = [var.firewalls]
}

run "reject_non_public_ip_resource_id" {
  command = plan
  variables {
    firewalls = {
      hub = {
        name           = "fw-test", location = "eastus", resource_group_name = "rg-test", sku_tier = "Standard"
        virtual_hub_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        ip_configurations = {
          primary = {
            name                 = "primary"
            public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/virtualNetworks/not-a-pip"
          }
        }
      }
    }
  }
  expect_failures = [var.firewalls]
}

run "reject_null_configuration" {
  command = plan
  variables {
    firewalls = {
      hub = {
        name           = "fw-test", location = "eastus", resource_group_name = "rg-test", sku_tier = "Standard"
        virtual_hub_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        ip_configurations = {
          primary = null
        }
      }
    }
  }
  expect_failures = [var.firewalls]
}

run "reject_ignored_ip_drift" {
  command = plan
  variables {
    ignore_body_changes = { network_azure_firewalls = ["properties.ipConfigurations"] }
  }
  expect_failures = [var.ignore_body_changes]
}
