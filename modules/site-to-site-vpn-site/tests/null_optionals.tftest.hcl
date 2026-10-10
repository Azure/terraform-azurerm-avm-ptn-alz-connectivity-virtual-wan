# Why this file exists
# --------------------
# An earlier test apply failed after a long gateway provisioning because
# `length(try(x, []))` lets a null reach `length()`. It got that far because
# `terraform validate` is a type check, not an evaluation, and `terraform plan` never
# evaluated the `for` body -- the collection was UNKNOWN at plan time, so the expression
# was deferred to apply.
#
# These tests close that hole by giving every input a KNOWN value. A known input forces
# the locals to evaluate at plan time, so a null-into-function fault is a test failure in
# seconds instead of an apply failure in hours.
#
# `mock_provider` means no Azure calls, no credentials and no cost: this runs anywhere.
#
# The load-bearing case is `all_optionals_null`. Every `optional()` attribute that has no
# default is left unset, which is the exact shape that broke an earlier apply.

mock_provider "azapi" {}

variables {
  resource_types = {
    network_vpn_sites = "Microsoft.Network/vpnSites@2025-07-01"
  }
}

# Every optional attribute omitted -- `address_cidrs`, `tags`, `device_*`, `o365_policy`,
# and the per-link `bgp`, `fqdn`, `ip_address`, `provider_name`, `speed_in_mbps`.
run "all_optionals_null" {
  command = plan

  variables {
    vpn_sites = {
      site_a = {
        location            = "eastus"
        name                = "vpnsite-null"
        resource_group_name = "rg-test"
        virtual_wan_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        links = [
          {
            name = "link-a"
          }
        ]
      }
    }
  }

  assert {
    condition     = azapi_resource.this["site_a"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    error_message = "parent_id must be reconstructed from the virtual_wan_id subscription and the module's resource_group_name."
  }

  # AzureRM's `expandVpnSiteAddressSpace` returns nil for an empty set, so a site without
  # CIDRs sends no `addressSpace` at all -- not `addressSpace: {}`.
  assert {
    condition     = !can(azapi_resource.this["site_a"].body.properties.addressSpace)
    error_message = "addressSpace must be absent when address_cidrs is null, matching expandVpnSiteAddressSpace returning nil."
  }

  assert {
    condition     = !can(azapi_resource.this["site_a"].body.properties.deviceProperties)
    error_message = "deviceProperties must be absent when both device_vendor and device_model are null."
  }

  assert {
    condition     = !can(azapi_resource.this["site_a"].body.properties.o365Policy)
    error_message = "o365Policy must be absent when o365_policy is null."
  }

  # AzureRM's schema defaults speed_in_mbps to 0 and sends it unconditionally.
  assert {
    condition     = azapi_resource.this["site_a"].body.properties.vpnSiteLinks[0].properties.linkProperties.linkSpeedInMbps == 0
    error_message = "linkSpeedInMbps must be the AzureRM schema default 0 when speed_in_mbps is unset."
  }

  assert {
    condition     = !can(azapi_resource.this["site_a"].body.properties.vpnSiteLinks[0].properties.bgpProperties)
    error_message = "bgpProperties must be absent when the link has no bgp block."
  }
}

# Every optional attribute supplied, so the opposite branch of each conditional evaluates.
run "all_optionals_set" {
  command = plan

  variables {
    vpn_sites = {
      site_a = {
        location            = "eastus"
        name                = "vpnsite-full"
        resource_group_name = "rg-test"
        virtual_wan_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        address_cidrs       = ["10.0.0.0/24", "10.0.1.0/24"]
        device_model        = "model-x"
        device_vendor       = "vendor-y"
        tags                = { env = "test" }
        links = [
          {
            name          = "link-a"
            fqdn          = "site-a.example.com"
            provider_name = "contoso"
            speed_in_mbps = 100
            bgp = {
              asn             = 65515
              peering_address = "10.0.0.4"
            }
          },
          {
            name       = "link-b"
            ip_address = "203.0.113.10"
          }
        ]
        o365_policy = {
          traffic_category = {
            allow_endpoint_enabled    = true
            default_endpoint_enabled  = true
            optimize_endpoint_enabled = true
          }
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["site_a"].body.properties.addressSpace.addressPrefixes == tolist(["10.0.0.0/24", "10.0.1.0/24"])
    error_message = "addressSpace.addressPrefixes must carry address_cidrs verbatim."
  }

  assert {
    condition     = azapi_resource.this["site_a"].body.properties.deviceProperties.deviceVendor == "vendor-y"
    error_message = "deviceProperties must be populated when device_vendor is set."
  }

  assert {
    condition     = azapi_resource.this["site_a"].body.properties.o365Policy.breakOutCategories.allow == true
    error_message = "o365Policy.breakOutCategories must carry the configured traffic_category booleans."
  }

  # Ordering is a contract: the parent module indexes `links` POSITIONALLY.
  assert {
    condition     = azapi_resource.this["site_a"].body.properties.vpnSiteLinks[0].name == "link-a" && azapi_resource.this["site_a"].body.properties.vpnSiteLinks[1].name == "link-b"
    error_message = "vpnSiteLinks must preserve the configured link order; the parent module indexes it positionally."
  }

  assert {
    condition     = azapi_resource.this["site_a"].body.properties.vpnSiteLinks[0].properties.bgpProperties.asn == 65515
    error_message = "bgpProperties must be emitted for a link that sets bgp."
  }

  # link-b has no bgp block, so only one of the two links carries bgpProperties.
  assert {
    condition     = !can(azapi_resource.this["site_a"].body.properties.vpnSiteLinks[1].properties.bgpProperties)
    error_message = "bgpProperties must stay absent on the link that does not set bgp, even when a sibling link sets one."
  }
}

# An empty map must produce no resources at all rather than failing on a null collection.
run "empty_map" {
  command = plan

  variables {
    vpn_sites = {}
  }

  assert {
    condition     = length(azapi_resource.this) == 0
    error_message = "An empty vpn_sites map must create no resources."
  }
}
