mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = { subscription_id = "00000000-0000-0000-0000-000000000001" }
  }
}
mock_provider "modtm" {}
mock_provider "random" {}

variables {
  location            = "eastus"
  resource_group_name = "rg-test"
  virtual_wan_name    = "wan-test"
}

run "omitted_uses_azurerm_default" {
  command = plan

  module {
    source = "./modules/virtual-wan"
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].body.properties.allowBranchToBranchTraffic == true
    error_message = "An omitted branch-to-branch flag must send the AzureRM default of true."
  }
}

run "explicit_null_uses_azurerm_default" {
  command = plan

  module {
    source = "./modules/virtual-wan"
  }

  variables {
    allow_branch_to_branch_traffic = null
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].body.properties.allowBranchToBranchTraffic == true
    error_message = "The pattern's explicit null must resolve to the AzureRM default of true."
  }
}

run "explicit_false_is_preserved" {
  command = plan

  module {
    source = "./modules/virtual-wan"
  }

  variables {
    allow_branch_to_branch_traffic = false
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].body.properties.allowBranchToBranchTraffic == false
    error_message = "A caller explicitly disabling branch-to-branch traffic must not be overridden."
  }
}

run "explicit_true_is_preserved" {
  command = plan

  module {
    source = "./modules/virtual-wan"
  }

  variables {
    allow_branch_to_branch_traffic = true
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].body.properties.allowBranchToBranchTraffic == true
    error_message = "A caller explicitly enabling branch-to-branch traffic must be preserved."
  }
}
