mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      # azapi_update_resource.resource_id rejects the mock provider's short token, so give it a real-looking ID.
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
    }
  }
  mock_data "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
      output = {
        properties = {
          hubIPAddresses = {
            privateIPAddress = "10.0.0.4"
            publicIPs        = { count = 1, addresses = [{ address = "198.51.100.10" }] }
          }
        }
      }
    }
  }
}
mock_provider "modtm" {}
mock_provider "random" {}

variables {
  enable_telemetry = false
  firewalls = {
    hub = {
      name                = "fw-test"
      location            = "eastus"
      resource_group_name = "rg-test"
      virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
      sku_tier            = "Standard"
    }
  }
}

run "managed_defaults_need_no_inventory" {
  command = apply

  assert {
    condition     = local.firewall_public_ip_counts["hub"] == 1 && local.firewall_update_bodies["hub"].properties.hubIPAddresses.publicIPs.count == 1
    error_message = "An omitted string count must still produce the numeric managed default of one."
  }
  assert {
    condition     = length(data.azapi_resource_list.firewalls) == 0 && length(data.azapi_client_config.current) == 0 && length(module.customer_firewalls) == 0
    error_message = "Managed-only consumers must not need new inventory reads or customer resources."
  }
  assert {
    condition     = output.resource == azapi_resource.fw && output.resource_object["hub"].virtual_hub[0].public_ip_count == 1 && output.resource_object["hub"].virtual_hub[0].private_ip_address == "10.0.0.4"
    error_message = "Managed mode must keep the AzAPI resource output and the legacy resource_object virtual_hub shape."
  }
  assert {
    condition     = terraform_data.public_ip_mode["hub"].output == false && length(var.firewalls["hub"].ip_configurations) == 0 && var.firewalls["hub"].vhub_public_ip_count == null
    error_message = "Default inputs must remain managed with an empty map and a null string count."
  }
}

run "managed_count_increase" {
  command = apply
  variables {
    firewalls = {
      hub = {
        name                 = "fw-test"
        location             = "eastus"
        resource_group_name  = "rg-test"
        virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        sku_tier             = "Standard"
        vhub_public_ip_count = "3"
      }
    }
  }
  assert {
    condition     = var.firewalls["hub"].vhub_public_ip_count == "3" && local.firewall_public_ip_counts["hub"] == 3 && local.firewall_update_bodies["hub"].properties.hubIPAddresses.publicIPs.count == 3
    error_message = "The published count stays a string, while the managed writers receive an integer."
  }
  assert {
    condition     = length(data.azapi_resource_list.firewalls) == 0 && output.resource == azapi_resource.fw
    error_message = "Managed count increases must stay on the managed writers and output path."
  }
}

run "managed_count_decrease" {
  command = apply
  variables {
    firewalls = {
      hub = {
        name                 = "fw-test"
        location             = "eastus"
        resource_group_name  = "rg-test"
        virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        sku_tier             = "Standard"
        vhub_public_ip_count = "2"
      }
    }
  }
  assert {
    condition     = local.firewall_public_ip_counts["hub"] == 2 && length(module.customer_firewalls) == 0
    error_message = "Count decreases must stay on the managed merge writer."
  }
}

run "managed_harmless_update" {
  command = apply
  variables {
    firewalls = {
      hub = {
        name                 = "fw-test"
        location             = "eastus"
        resource_group_name  = "rg-test"
        virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
        sku_tier             = "Premium"
        vhub_public_ip_count = "2"
        tags                 = { maintenance = "metadata-only" }
      }
    }
  }
  assert {
    condition     = local.firewall_tags["hub"].maintenance == "metadata-only" && local.firewall_update_bodies["hub"].properties.sku.tier == "Premium" && terraform_data.public_ip_mode["hub"].output == false
    error_message = "Harmless updates and Premium must preserve the managed mode record."
  }
}

run "ordinary_firewall_removal" {
  command = apply
  variables {
    firewalls = {}
  }
  assert {
    condition     = length(azapi_resource.fw) == 0 && length(terraform_data.public_ip_mode) == 0 && length(module.customer_firewalls) == 0
    error_message = "The mode guard must not prevent an explicitly removed firewall from being destroyed."
  }
  assert {
    condition     = output.resource_ids == {} && output.public_ip_addresses == {} && output.diagnostic_settings_resource_ids == {}
    error_message = "An empty map must preserve the old empty-map outputs."
  }
}

run "null_firewalls_preserves_output_contract" {
  command = apply
  variables {
    firewalls = null
  }
  assert {
    condition     = output.private_ip_address == null && output.public_ip_addresses == null && output.resource_ids == null && output.resource_names == null
    error_message = "Null firewall input must preserve null map outputs."
  }
  assert {
    condition     = output.resource == {} && output.resource_object == {} && length(output.resource_id) == 0 && length(output.azure_firewall_resource_names) == 0
    error_message = "Null firewall input must preserve empty resource objects and ID/name lists."
  }
}
