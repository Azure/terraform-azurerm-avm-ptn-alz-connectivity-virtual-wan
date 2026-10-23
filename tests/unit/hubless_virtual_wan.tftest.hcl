# Regression test for Azure/Azure-Landing-Zones#4289.
# A Virtual WAN should be creatable without Virtual Hubs when all standalone
# Virtual WAN settings are explicitly provided.

mock_provider "azapi" {}
mock_provider "azurerm" {}
mock_provider "modtm" {}
mock_provider "random" {}

override_module {
  target = module.virtual_wan
  outputs = {
    name                     = "vwan-hubless-test"
    resource_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hubless-test/providers/Microsoft.Network/virtualWans/vwan-hubless-test"
    virtual_hub_resource_ids = {}
  }
}

variables {
  enable_telemetry = false

  virtual_hubs = {}

  virtual_wan_settings = {
    enabled_resources = {
      ddos_protection_plan = false
    }
    virtual_wan = {
      name                = "vwan-hubless-test"
      location            = "eastus"
      resource_group_name = "rg-hubless-test"
    }
  }
}

run "explicit_virtual_wan_without_hubs" {
  command = apply

  assert {
    condition     = length(module.virtual_wan) == 1
    error_message = "Explicit Virtual WAN settings must instantiate the Virtual WAN module even when virtual_hubs is empty."
  }

  assert {
    condition     = length(module.virtual_wan[0].virtual_hub_resource_ids) == 0
    error_message = "A standalone Virtual WAN must contain no Virtual Hubs when virtual_hubs is empty."
  }

  assert {
    condition     = output.name == "vwan-hubless-test"
    error_message = "A standalone Virtual WAN must expose its name even when virtual_hubs is empty."
  }

  assert {
    condition     = output.resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hubless-test/providers/Microsoft.Network/virtualWans/vwan-hubless-test"
    error_message = "A standalone Virtual WAN must expose its resource ID even when virtual_hubs is empty."
  }
}


run "empty_hubs_without_standalone_wan_preserves_existing_behavior" {
  command = apply

  variables {
    virtual_hubs = {}

    virtual_wan_settings = {
      enabled_resources = {
        ddos_protection_plan = false
      }
    }
  }

  assert {
    condition     = length(module.virtual_wan) == 0
    error_message = "An empty virtual_hubs configuration without explicit standalone Virtual WAN settings must not instantiate the Virtual WAN module."
  }

  assert {
    condition     = output.name == null
    error_message = "Virtual WAN name must remain null when no hubs or standalone Virtual WAN are configured."
  }

  assert {
    condition     = output.resource_id == null
    error_message = "Virtual WAN resource ID must remain null when no hubs or standalone Virtual WAN are configured."
  }
}


