mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = { subscription_id = "00000000-0000-0000-0000-000000000001" }
  }
}
mock_provider "modtm" {}
mock_provider "random" {}

override_module {
  target  = module.regions
  outputs = { regions_by_name = { eastus = { zones = ["1", "2", "3"] } } }
}

variables {
  enable_telemetry = false
  virtual_wan_settings = {
    virtual_wan       = { office365_local_breakout_category = "OptimizeAndAllow" }
    enabled_resources = { ddos_protection_plan = false }
  }
  virtual_hubs = {
    hub = {
      location          = "eastus"
      default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test"
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

run "root_category_is_forwarded" {
  command = plan

  assert {
    condition     = local.virtual_wan.office365_local_breakout_category == "OptimizeAndAllow"
    error_message = "Root settings must retain the consumer's Office365 category."
  }
}
