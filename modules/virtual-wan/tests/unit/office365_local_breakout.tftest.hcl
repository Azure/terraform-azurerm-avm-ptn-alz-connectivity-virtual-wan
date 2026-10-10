mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = { subscription_id = "00000000-0000-0000-0000-000000000001" }
  }
}
mock_provider "modtm" {}
mock_provider "random" {}

variables {
  enable_telemetry    = false
  location            = "eastus"
  resource_group_name = "rg-test"
  virtual_wan_name    = "wan-test"
}

run "default_none_is_sent" {
  command = plan

  assert {
    condition     = try(azapi_resource.virtual_wan[0].body.properties.office365LocalBreakoutCategory, null) == "None"
    error_message = "The default Office365 category must reach the WAN request."
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].schema_validation_enabled == false
    error_message = "Only the WAN writer must bypass the incorrectly read-only Office365 schema."
  }
}

run "optimize_is_sent" {
  command = apply

  variables {
    office365_local_breakout_category = "Optimize"
  }

  assert {
    condition     = try(azapi_resource.virtual_wan[0].body.properties.office365LocalBreakoutCategory, null) == "Optimize"
    error_message = "Optimize must not be silently ignored."
  }
}

run "category_update_is_sent" {
  command = plan

  variables {
    office365_local_breakout_category = "OptimizeAndAllow"
  }

  assert {
    condition     = try(azapi_resource.virtual_wan[0].body.properties.office365LocalBreakoutCategory, null) == "OptimizeAndAllow"
    error_message = "An Office365 update must reach the existing WAN request."
  }

  assert {
    condition = (
      azapi_resource.virtual_wan[0].body.properties.allowBranchToBranchTraffic == true &&
      azapi_resource.virtual_wan[0].body.properties.disableVpnEncryption == false &&
      azapi_resource.virtual_wan[0].body.properties.type == "Standard"
    )
    error_message = "Changing the Office365 category must preserve the other WAN settings."
  }
}

run "all_is_sent" {
  command = plan

  variables {
    office365_local_breakout_category = "All"
  }

  assert {
    condition     = try(azapi_resource.virtual_wan[0].body.properties.office365LocalBreakoutCategory, null) == "All"
    error_message = "All must not be silently ignored."
  }
}

run "invalid_category_is_rejected" {
  command = plan

  variables {
    office365_local_breakout_category = "Invalid"
  }

  expect_failures = [var.office365_local_breakout_category]
}

run "existing_wan_is_not_written" {
  command = plan

  variables {
    virtual_wan_id                    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/existing"
    office365_local_breakout_category = "All"
  }

  assert {
    condition     = length(azapi_resource.virtual_wan) == 0
    error_message = "Referencing an existing WAN must not create a WAN writer."
  }
}
