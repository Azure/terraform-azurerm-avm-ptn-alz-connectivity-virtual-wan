mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id          = "00000000-0000-0000-0000-000000000000"
      subscription_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
      tenant_id                = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_data "azapi_resource_action" {
    defaults = {
      output = {
        value = [
          {
            name        = "testrecommendedwithzones"
            displayName = "Test Recommended With Zones"
            metadata = {
              geography      = "Test Geography"
              geographyGroup = "Test Geography Group"
              pairedRegion   = [{ name = "testpairedregion" }]
              regionCategory = "Recommended"
              regionType     = "Physical"
            }
            availabilityZoneMappings = [
              { logicalZone = "1" },
              { logicalZone = "2" },
              { logicalZone = "3" }
            ]
          },
          {
            name        = "testrecommendedwithoutzones"
            displayName = "Test Recommended Without Zones"
            metadata = {
              geography      = "Test Geography"
              geographyGroup = "Test Geography Group"
              pairedRegion   = [{ name = "testpairedregion" }]
              regionCategory = "Recommended"
              regionType     = "Physical"
            }
            availabilityZoneMappings = null
          },
          {
            name        = "testnonrecommendedwithzones"
            displayName = "Test Non Recommended With Zones"
            metadata = {
              geography      = "Test Geography"
              geographyGroup = "Test Geography Group"
              pairedRegion   = [{ name = "testpairedregion" }]
              regionCategory = "Other"
              regionType     = "Physical"
            }
            availabilityZoneMappings = [
              { logicalZone = "1" },
              { logicalZone = "2" },
              { logicalZone = "3" }
            ]
          },
          {
            name        = "testnonrecommendedwithoutzones"
            displayName = "Test Non Recommended Without Zones"
            metadata = {
              geography      = "Test Geography"
              geographyGroup = "Test Geography Group"
              pairedRegion   = [{ name = "testpairedregion" }]
              regionCategory = "Other"
              regionType     = "Physical"
            }
            availabilityZoneMappings = null
          }
        ]
      }
    }
  }
}

mock_provider "azurerm" {}

mock_provider "modtm" {}

mock_provider "random" {}

override_module {
  target = module.virtual_wan
}

variables {
  enable_telemetry = false

  virtual_wan_settings = {
    enabled_resources = {
      ddos_protection_plan = false
    }
  }

  virtual_hubs = {
    for region_key, region_name in {
      recommended_with_zones        = "testrecommendedwithzones"
      recommended_without_zones     = "testrecommendedwithoutzones"
      non_recommended_with_zones    = "testnonrecommendedwithzones"
      non_recommended_without_zones = "testnonrecommendedwithoutzones"
      } : region_key => {
      location          = region_name
      default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
      enabled_resources = {
        firewall                              = false
        firewall_policy                       = false
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }
    }
  }
}

run "unfiltered_regions_with_telemetry_disabled" {
  command = apply

  assert {
    condition = jsonencode(local.availability_zones) == jsonencode({
      recommended_with_zones        = [1, 2, 3]
      recommended_without_zones     = []
      non_recommended_with_zones    = [1, 2, 3]
      non_recommended_without_zones = []
    })
    error_message = "The real regions utility must retain recommended and non-recommended regions, preserve zones, and normalize missing zones to an empty list."
  }
  providers = {
    azapi   = azapi
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }
}

run "unfiltered_regions_with_telemetry_enabled" {
  command = apply

  variables {
    enable_telemetry = true
    location         = "eastus"
  }

  assert {
    condition = jsonencode(local.availability_zones) == jsonencode({
      recommended_with_zones        = [1, 2, 3]
      recommended_without_zones     = []
      non_recommended_with_zones    = [1, 2, 3]
      non_recommended_without_zones = []
    })
    error_message = "Enabling telemetry must keep the regions lookup valid with its required location input and preserve the same unfiltered zone results."
  }
  providers = {
    azapi   = azapi
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }
}
