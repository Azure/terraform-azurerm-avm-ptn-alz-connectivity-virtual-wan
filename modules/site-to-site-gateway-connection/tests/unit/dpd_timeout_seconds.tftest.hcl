# Regression test for Azure/Azure-Landing-Zones#4092.
# Verifies dpd_timeout_seconds reaches the AzureRM VPN link and remains null
# when callers omit it.

mock_provider "azurerm" {}

variables {
  vpn_site_connection = {
    connection1 = {
      name               = "connection1"
      remote_vpn_site_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/site1"
      vpn_gateway_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/gateway1"
      vpn_links = [
        {
          name                = "link1"
          vpn_site_link_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/site1/vpnSiteLinks/link1"
          dpd_timeout_seconds = 30
        }
      ]
    }
  }
}

run "dpd_timeout_seconds_reaches_vpn_link" {
  command = apply

  assert {
    condition     = azurerm_vpn_gateway_connection.vpn_site_connection["connection1"].vpn_link[0].dpd_timeout_seconds == 30
    error_message = "dpd_timeout_seconds was not passed to the azurerm_vpn_gateway_connection VPN link."
  }
}

run "omitted_dpd_timeout_seconds_remains_null" {
  command = apply

  variables {
    vpn_site_connection = {
      connection1 = {
        name               = "connection1"
        remote_vpn_site_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/site1"
        vpn_gateway_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/gateway1"
        vpn_links = [
          {
            name             = "link1"
            vpn_site_link_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/site1/vpnSiteLinks/link1"
          }
        ]
      }
    }
  }

  assert {
    condition     = azurerm_vpn_gateway_connection.vpn_site_connection["connection1"].vpn_link[0].dpd_timeout_seconds == null
    error_message = "dpd_timeout_seconds must remain null when callers omit it."
  }
}