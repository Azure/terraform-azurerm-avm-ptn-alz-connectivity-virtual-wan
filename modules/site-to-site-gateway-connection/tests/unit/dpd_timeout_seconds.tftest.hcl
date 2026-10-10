# Regression test for Azure/Azure-Landing-Zones#4092.
# Verifies dpd_timeout_seconds reaches the VPN link connection in the AzAPI request body,
# and remains absent/null when callers omit it.
#
# ⭐ PORTED from `mock_provider "azurerm"` on. This module's `terraform.tf` has
# declared `azapi` ONLY since the migration, so the previous version of this file failed at
# load time with `unknown provider registry.terraform.io/hashicorp/azurerm` -- it was the one
# genuinely broken file of the six. The subject still exists (`dpd_timeout_seconds` is still
# an input, and `main.tf` L84-L86 still maps it onto `dpdTimeoutSeconds`), so the assertions
# were ported rather than the file deleted. The old addresses map as:
#   azurerm_vpn_gateway_connection.vpn_site_connection[k].vpn_link[0].dpd_timeout_seconds
#     -> azapi_resource.this[k].body.properties.vpnLinkConnections[0].properties.dpdTimeoutSeconds
#
# 🔴 THE NULL CASE CHANGES SHAPE, NOT MEANING. AzureRM's `vpn_link` block read back a
# computed `dpd_timeout_seconds` that was `null` when unset. AzAPI has no such attribute:
# `main.tf` merges in `{ dpdTimeoutSeconds = ... }` only when the input is non-null and
# non-zero, mirroring AzureRM's expander guard, so an omitted timeout is ABSENT from the
# request rather than sent as an explicit JSON null. `!can(...)` is therefore the faithful
# port of `== null`; asserting `== null` would pass vacuously on a missing key in some
# expressions and would not prove the key is absent from the PUT. The module OUTPUT still
# projects a literal `null`, and that half of the original contract is asserted separately.
#
# 🔴 BOTH RUNS STAY `command = apply`, as the AzureRM original was. A plan-only run that
# reads `azapi_resource.this[...].body` resolves the CONFIGURATION value and would pass
# whether or not the provider ever accepted the resource.
#
# 🔴 `mock_resource` IS NEEDED BECAUSE OF THE APPLY. The azapi mock provider invents an
# 8-character random token for every computed attribute including `id`; an apply that hands
# that to anything expecting an ARM resource ID fails with
# `invalid resource ID: resource id '...' must start with '/'`. Plan-only suites never hit
# this because `id` stays unknown. See the same note in `tests/retry_gateway_child_409.tftest.hcl`.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/gateway1/vpnConnections/connection1"
    }
  }
}

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
    condition     = azapi_resource.this["connection1"].body.properties.vpnLinkConnections[0].properties.dpdTimeoutSeconds == 30
    error_message = "dpd_timeout_seconds was not passed to properties.vpnLinkConnections[0].properties.dpdTimeoutSeconds in the AzAPI request body."
  }

  # The link projection in `outputs.tf` replaces AzureRM's computed `vpn_link` blocks, so it
  # carries the other half of the original contract: a consumer reading the timeout back.
  assert {
    condition     = output.resource_object["connection1"].link[0].dpd_timeout_seconds == 30
    error_message = "dpd_timeout_seconds must be readable back from the module's projected link output."
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

  # AzureRM guarded the timeout on `!= 0` and its schema carried no default, so an unset
  # timeout was never part of the request. The migrated body must not start sending one --
  # a `dpdTimeoutSeconds: 0` on the first post-migration apply would reset a live tunnel's
  # dead-peer detection.
  assert {
    condition     = !can(azapi_resource.this["connection1"].body.properties.vpnLinkConnections[0].properties.dpdTimeoutSeconds)
    error_message = "dpdTimeoutSeconds must be absent from the request body when callers omit dpd_timeout_seconds, not sent as 0 or as an explicit null."
  }

  # The link the caller omitted it on must still exist; otherwise the assertion above would
  # pass for the wrong reason (no link at all to carry the key).
  assert {
    condition     = length(azapi_resource.this["connection1"].body.properties.vpnLinkConnections) == 1
    error_message = "The configured link must still be present in the body; the absence assertion above is only meaningful if it is."
  }

  assert {
    condition     = output.resource_object["connection1"].link[0].dpd_timeout_seconds == null
    error_message = "dpd_timeout_seconds must remain null in the projected link output when callers omit it."
  }
}
