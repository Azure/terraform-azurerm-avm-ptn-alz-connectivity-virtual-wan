mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
    }
  }
  mock_data "azapi_resource_action" {
    defaults = {
      output = {
        value = [for name in ["eastus", "eastus2", "westus2", "centralus", "italynorth", "swedencentral", "uksouth", "ukwest"] : {
          name        = name
          displayName = name
          metadata = {
            geography      = "Mock"
            regionCategory = "Recommended"
            regionType     = "Physical"
          }
          availabilityZoneMappings = [for zone in ["1", "2", "3"] : { logicalZone = zone }]
        }]
      }
    }
  }
  mock_data "azapi_resource_list" {
    defaults = {
      output = { value = [], firewalls = [] }
    }
  }
}
mock_provider "random" {}

variables {
  enable_telemetry = false
}

run "example_plan" {
  command = plan
}
