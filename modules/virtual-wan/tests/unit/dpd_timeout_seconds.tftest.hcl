# Regression test for Azure/Azure-Landing-Zones#4092.
# Verifies the Virtual WAN module preserves dpd_timeout_seconds while mapping a
# VPN site connection into the site-to-site-gateway-connection submodule.

mock_provider "azapi" {}
mock_provider "azurerm" {
  mock_resource "azurerm_virtual_wan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
    }
  }
}
mock_provider "modtm" {}
mock_provider "random" {}

override_module {
  target = module.vpn_gateway
  outputs = {
    ip_configuration_ids = {}
    resource_object = {
      gateway1 = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/gateway1"
      }
    }
  }
}

override_module {
  target = module.vpn_site
  outputs = {
    resource_object = {
      site1 = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/site1"
        links = [
          {
            id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/site1/vpnSiteLinks/link1"
          }
        ]
      }
    }
  }
}

variables {
  location            = "eastus"
  resource_group_name = "rg-test"
  virtual_wan_name    = "vwan-test"

  virtual_hubs = {
    hub1 = {
      name                = "hub1"
      location            = "eastus"
      resource_group_name = "rg-test"
      address_prefix      = "10.0.0.0/24"
    }
  }

  vpn_gateways = {
    gateway1 = {
      name            = "gateway1"
      virtual_hub_key = "hub1"
    }
  }

  vpn_sites = {
    site1 = {
      name            = "site1"
      virtual_hub_key = "hub1"
      links = [
        {
          name          = "link1"
          ip_address    = "203.0.113.10"
          speed_in_mbps = 50
        }
      ]
    }
  }

  vpn_site_connections = {
    connection1 = {
      name                = "connection1"
      vpn_gateway_key     = "gateway1"
      remote_vpn_site_key = "site1"
      vpn_links = [
        {
          name                 = "link1"
          vpn_site_key         = "site1"
          vpn_site_link_number = 0
          dpd_timeout_seconds  = 30
        }
      ]
    }
  }
}

run "dpd_timeout_seconds_reaches_gateway_connection" {
  command = apply

  assert {
    condition     = module.vpn_site_connection.resource_object["connection1"].link[0].dpd_timeout_seconds == 30
    error_message = "dpd_timeout_seconds was dropped while mapping the Virtual WAN VPN site connection into the gateway connection submodule."
  }
}
