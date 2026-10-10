mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
    }
  }
}
mock_provider "random" {}

override_module {
  target = module.test
}

variables {
  enable_telemetry = false
}

run "resource_group_interface_is_preserved" {
  command = apply

  assert {
    condition = (
      module.resource_groups["hub_primary"].name == "rg-hub-primary-${random_string.suffix.result}" &&
      module.resource_groups["hub_secondary"].name == "rg-hub-secondary-${random_string.suffix.result}" &&
      module.resource_groups["hub_primary"].resource.location == "italynorth" &&
      module.resource_groups["hub_secondary"].resource.location == "swedencentral"
    )
    error_message = "The supporting provider migration must preserve resource group names and regions."
  }

  assert {
    condition     = tomap(module.resource_groups["hub_primary"].resource.tags) == tomap(local.common_tags)
    error_message = "Supporting resource groups must retain the example tags."
  }

  assert {
    condition     = startswith(try(module.resource_groups["hub_primary"].resource.type, ""), "Microsoft.Resources/resourceGroups@")
    error_message = "Supporting resource groups must use the AzAPI implementation."
  }

  assert {
    condition     = module.resource_groups["hub_primary"].resource_id == module.resource_groups["hub_primary"].resource.id
    error_message = "The supporting module must preserve the resource_id output consumed by the example."
  }
}
