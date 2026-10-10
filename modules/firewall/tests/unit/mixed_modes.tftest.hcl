mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_data "azapi_resource_list" {
    defaults = {
      output = { firewalls = [] }
    }
  }
  mock_data "azapi_resource" {
    defaults = {
      output = {
        address           = "203.0.113.10"
        allocation_method = "Static"
        association       = null
        ip_version        = "IPv4"
        location          = "eastus"
        sku               = "Standard"
        tier              = "Regional"
        type              = "Standard"
        virtual_wan_id    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/wan-test"
        zones             = ["1", "2", "3"]
      }
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
      output = {
        properties = {
          hubIPAddresses       = { privateIPAddress = "10.0.0.4" }
          threatIntelMode      = null
          additionalProperties = {}
        }
      }
    }
  }
}

# A managed firewall in one hub and a customer-IP firewall in another hub.
# Both element types must be identical, or the conditional in
# output.resource_object cannot unify with the empty-map branch.
variables {
  enable_telemetry    = false
  diagnostic_settings = {}
  firewalls = {
    managed = {
      name                 = "fw-managed"
      location             = "eastus2"
      resource_group_name  = "rg-test"
      virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-managed"
      sku_tier             = "Standard"
      vhub_public_ip_count = "1"
    }
    customer = {
      name                = "fw-customer"
      location            = "eastus"
      resource_group_name = "rg-test"
      virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-customer"
      sku_tier            = "Standard"
      ip_configurations = {
        primary = {
          name                 = "ip-primary"
          public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
        }
      }
    }
  }
}

run "mixed_modes_plan" {
  command = plan
  assert {
    condition     = length(azapi_resource.fw) == 1 && length(module.customer_firewalls) == 1
    error_message = "One managed firewall and one customer firewall must be planned."
  }
}

run "mixed_modes_resource_object" {
  command = apply
  assert {
    condition     = toset(keys(output.resource_object)) == toset(["managed", "customer"])
    error_message = "resource_object must contain both the managed and the customer firewall."
  }
  assert {
    condition     = output.resource_object["managed"].virtual_hub[0].public_ip_count == 1 && output.resource_object["customer"].virtual_hub[0].public_ip_count == 1
    error_message = "Both firewalls must keep the one-element virtual_hub shape."
  }
  assert {
    condition     = output.resource_object["customer"].virtual_hub[0].virtual_hub_id == var.firewalls["customer"].virtual_hub_id
    error_message = "The customer firewall must keep its virtual hub ID."
  }
}
