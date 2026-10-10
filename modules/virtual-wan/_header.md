# Terraform Verified Module for Azure Virtual WAN Hub Networking

[![Average time to resolve an issue](http://isitmaintained.com/badge/resolution/Azure/terraform-azurerm-vwan.svg)](http://isitmaintained.com/project/Azure/terraform-azurerm-vwan "Average time to resolve an issue")
[![Percentage of issues still open](http://isitmaintained.com/badge/open/Azure/terraform-azurerm-vwan.svg)](http://isitmaintained.com/project/Azure/terraform-azurerm-vwan "Percentage of issues still open")

This module is designed to simplify the creation of virtual wan based networks in Azure.

The Office365 local breakout category supports `None`, `Optimize`,
`OptimizeAndAllow` and `All`, matching the AzureRM interface. AzAPI's embedded
schema marks this property read-only, although the recorded ARM 2025-07-01 probe
accepted and persisted `OptimizeAndAllow`. Schema validation is therefore disabled
only for the Virtual WAN resource. This disables validation of its entire body,
not just the Office365 property; other resources retain their existing validation.
See [migration deviations](../../docs/MIGRATION-DEVIATIONS.md) for evidence and limits.

## Features

- Virtual WAN:
- Virtual WAN Hub:
  - Virtual WAN Hub.
  - Secured Virtual Hub.
  - Routing intent
- Azure Firewall
  - Secured Virtual Hub
  - AzureFirewallSubnet.
- Site-to-Site Virtual Network Gateway:
  - S2S VPN Gateway.
  - Active-Active or Single.
  - VPN Site
  - VPN Site Connection
  - Deployment of `GatewaySubnet`.
- Point-to-Site Virtual Network Gateway:
  - P2S VPN Gateway.
  - P2S server configuration.
  - Active-Active or Single.
  - Deployment of `GatewaySubnet`.
- ER Gateway:
  - ER Gateway.
  - ER Gateway Connection.
  - Active-Active or Single.
  - Deployment of `GatewaySubnet`.

## Example

```terraform
module "vwan_with_vhub" {
  source                         = "../../"
  resource_group_name            = "tvmVwanRg"
  location                       = "australiaeast"
  virtual_wan_name               = "tvmVwan"
  disable_vpn_encryption         = false
  allow_branch_to_branch_traffic = true
  bgp_community                  = "12076:51010"
  type                           = "Standard"
  virtual_wan_tags = {
    environment = "dev"
    deployment  = "terraform"
  }
  virtual_hubs = {
    aue-vhub = {
      name           = "aue_vhub"
      location       = "australiaeast"
      resource_group = "demo-vwan-rsg"
      address_prefix = "10.0.0.0/24"
      tags = {
        "location" = "AUE"
      }
    }
  }
  vpn_gateways = {
    "aue-vhub-vpn-gw" = {
      name            = "aue-vhub-vpn-gw"
      virtual_hub_key = "aue-vhub"
    }
  }
  vpn_sites = {
    "aue-vhub-vpn-site" = {
      name            = "aue-vhub-vpn-site"
      virtual_hub_key = "aue-vhub"
      links = [{
        name          = "link1"
        provider_name = "Cisco"
        bgp = {
          asn             = 65001
          peering_address = "172.16.1.254"
        }
        ip_address    = "20.28.182.157"
        speed_in_mbps = "20"
      }]
    }
  }
  vpn_site_connections = {
    "onprem1" = {
      name                = "aue-vhub-vpn-conn01"
      vpn_gateway_key     = "aue-vhub-vpn-gw"
      remote_vpn_site_key = "aue-vhub-vpn-site"

      vpn_links = [{
        name                                  = "link1"
        bandwidth_mbps                        = 10
        bgp_enabled                           = true
        local_azure_ip_address_enabled        = false
        policy_based_traffic_selector_enabled = false
        ratelimit_enabled                     = false
        route_weight                          = 1
        shared_key                            = "AzureA1b2C3"
        vpn_site_link_number                  = 0
      }]
    }
  }
}

```

## Design notes

### Per-resource timeout defaults

`var.timeouts` keeps its published shape -- same variable name, same four attributes, same
types, still `nullable = false` with `default = {}` -- but its attributes no longer carry a
blanket `"30m"`/`"5m"` default. Each is now `optional(string)` (null when unset) and falls back
**per resource** to the timeout default of the `azurerm` resource that resource replaced. A
consumer that sets `var.timeouts` today keeps working unchanged: whatever they set still wins
for every resource in the module. Only the *unset* attributes changed meaning.

The blanket `30m` was measurably wrong here: `azurerm_resource_group` defaulted
create/update/delete to **90 minutes**.

The fallbacks live in `local.timeouts` in `locals.timeouts.tf`, cited against
`terraform-provider-azurerm@5782a75422c68a0d0804ac16d97dcaf3df5ee2fa` (v4.81.0):

| `azapi_resource` | AzureRM resource | Source | Create | Read | Update | Delete |
| --- | --- | --- | --- | --- | --- | --- |
| `rg` | `azurerm_resource_group` | `resource_group_resource.go` L41-L46 | 90m | 5m | 90m | 90m |
| `virtual_wan` | `azurerm_virtual_wan` | `virtual_wan_resource.go` L36-L41 | 30m | 5m | 30m | 30m |
| `virtual_hub_route_table` | `azurerm_virtual_hub_route_table` | `virtual_hub_route_table_resource.go` L36-L41 | 30m | 5m | 30m | 30m |
| `bgp_connection` | `azurerm_virtual_hub_bgp_connection` | `virtual_hub_bgp_connection_resource.go` L33-L37 | 30m | 5m | *(none declared)* | 30m |
| `routing_intent` | `azurerm_virtual_hub_routing_intent` | `virtual_hub_routing_intent_resource.go` L111-L113, L155-L157, L194-L196, L234-L236 | 30m | 5m | 30m | 30m |

⚠️ `azurerm_virtual_hub_bgp_connection` declares **no Update timeout**, because the AzureRM
resource registers no Update at all -- every schema attribute is ForceNew. AzAPI does issue a PUT
for an in-place change, so an update timeout still has to be supplied. The create timeout (30m)
is reused for it. That is the one fallback in this module that is not a direct transcription of
a provider default, and it is called out in `locals.timeouts.tf` as such.

`azurerm_virtual_hub_routing_intent` is a typed (`sdk.ResourceFunc`) resource, so its timeouts
are declared per CRUD method rather than in one `ResourceTimeout` block; all four lines are cited
above.
