mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = { subscription_id = "00000000-0000-0000-0000-000000000001", tenant_id = "00000000-0000-0000-0000-000000000002" }
  }
  mock_data "azapi_resource_list" {
    defaults = { output = { value = [] } }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/dnsResolvers/pdr-test"
    }
  }
}
mock_provider "modtm" {}
mock_provider "random" {}

run "baseline" {
  command = apply
}

run "sidecar_update" {
  command = plan

  variables {
    revision = "updated"
  }
}
