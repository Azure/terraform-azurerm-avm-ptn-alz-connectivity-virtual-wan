mock_provider "azapi" {}
mock_provider "azurerm" {
  mock_resource "azurerm_virtual_wan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-vwan/providers/Microsoft.Network/virtualWans/vwan-test"
    }
  }
}
mock_provider "modtm" {}
mock_provider "random" {}

variables {
  enable_telemetry    = false
  location            = "eastus"
  resource_group_name = "rg-vwan"
  virtual_wan_name    = "vwan-test"

  virtual_hubs = {
    hub1 = {
      name           = "vhub-test"
      location       = "westus2"
      address_prefix = "10.0.0.0/23"
    }
  }
}

run "defaults_hub_resource_group_to_virtual_wan" {
  command = apply

  assert {
    condition     = module.virtual_hubs.resource_group_name["hub1"] == var.resource_group_name
    error_message = "A hub without an explicit resource group must use the Virtual WAN resource group."
  }
}