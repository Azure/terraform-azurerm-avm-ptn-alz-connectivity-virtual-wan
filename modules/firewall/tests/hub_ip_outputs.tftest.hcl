# ---------------------------------------------------------------------------
# HUB IP ADDRESSES -- the restored `private_ip_address` and
# `public_ip_addresses` outputs.
#
# THE CONTRACT BEING PINNED is the PRE-MIGRATION one, read out of
# `modules/firewall/outputs.tf` at commit 589d10e^ -- the last azurerm-based
# revision of this module:
#
#   output "private_ip_address"  description "Azure Firewall IP addresses"
#     { for key, value in azurerm_firewall.fw : key => value.virtual_hub[0].private_ip_address }
#     -> map(string),        null when var.firewalls is null
#   output "public_ip_addresses" description "Azure Firewall IP addresses"
#     { for key, value in azurerm_firewall.fw : key => value.virtual_hub[0].public_ip_addresses }
#     -> map(list(string)),  null when var.firewalls is null
#
# The azurerm schema backs those types: `private_ip_address` is a Computed
# TypeString (FW L219-222) and `public_ip_addresses` a Computed TypeList of
# TypeString (FW L214-218).
#
# 🔴 WHY `command = apply`. The values come from a data source keyed off the
# firewall's `id`, which is unknown until the firewall exists. Under
# `command = plan` alone the outputs are unknown and an assertion on them is
# an error, not a failure. The genesis apply below makes them concrete.
#
# mock_provider means no Azure calls, no credentials and no cost. The mocked
# `output` is shaped like the REAL 2025-07-01 response -- verified against the
# type set embedded in azapi v2.12.0 at
# `internal/azure/generated/network/microsoft.network/2025-07-01/types.json`,
# nodes #1569 HubIPAddresses / #1570 HubPublicIPAddresses / #1571
# AzureFirewallPublicIPAddress.
# ---------------------------------------------------------------------------

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      # `azapi_update_resource.resource_id` rejects the mock provider's
      # 8-character token with `invalid resource ID: ... must start with '/'`.
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-mock"
    }
  }

  mock_data "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-mock"
      output = {
        properties = {
          hubIPAddresses = {
            privateIPAddress = "10.100.0.68"
            publicIPs = {
              count = 2
              # ARM returns a list of OBJECTS, each with an `address` member --
              # not a list of bare strings. AzureRM walked exactly this shape
              # at FW L812-818.
              addresses = [
                { address = "20.90.1.10" },
                { address = "20.90.1.11" },
              ]
            }
          }
        }
      }
    }
  }
}

variables {
  diagnostic_settings = {}
  firewalls = {
    fw_a = {
      virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
      location             = "uksouth"
      resource_group_name  = "rg-test"
      sku_tier             = "Standard"
      name                 = "fw-a"
      vhub_public_ip_count = "2"
    }
  }
}

run "hub_ip_outputs_resolve" {
  command = apply

  # --- the data source is wired to the firewall, narrowly ---

  assert {
    condition     = data.azapi_resource.fw_hub_ip_addresses["fw_a"].resource_id == azapi_resource.fw["fw_a"].id
    error_message = "The hub IP data source must read the firewall's own resource ID."
  }

  # 🔴 NOT ["*"]. A wildcard export would pull the entire firewall body --
  # including the child collections this module exists to avoid touching --
  # into state for no reason.
  assert {
    condition     = tolist(data.azapi_resource.fw_hub_ip_addresses["fw_a"].response_export_values) == tolist(["properties.hubIPAddresses"])
    error_message = "The hub IP data source must export only properties.hubIPAddresses."
  }

  # The NON-EMPTY export list is for the DATA SOURCE and nothing else. The
  # writer must declare the attribute -- TFFR4 is Severity-MUST -- but it must
  # declare the EMPTY list. Giving the writer a real export path is what
  # caused the stale PUT.
  assert {
    condition     = azapi_resource.fw["fw_a"].response_export_values != null && length(azapi_resource.fw["fw_a"].response_export_values) == 0
    error_message = "The full writer must declare response_export_values = [] -- present, per TFFR4 (Severity-MUST), and EMPTY. A non-empty export list on the writer is what caused the stale PUT; the data-source exemption does not extend to it."
  }

  # --- private_ip_address: map(string), NOT null ---

  assert {
    condition     = output.private_ip_address["fw_a"] == "10.100.0.68"
    error_message = "private_ip_address must carry properties.hubIPAddresses.privateIPAddress from the data source. ALZ consumers route on this value; null is a regression."
  }

  assert {
    condition     = output.private_ip_address["fw_a"] != null
    error_message = "private_ip_address must not be null on a healthy firewall."
  }

  # Pins the TYPE, not just the value: `tostring` succeeds only on a string,
  # and the pre-migration output was map(string).
  assert {
    condition     = can(tostring(output.private_ip_address["fw_a"]))
    error_message = "private_ip_address must be a map of STRING, matching the azurerm Computed TypeString at FW L219-222."
  }

  # --- public_ip_addresses: map(list(string)), NOT null ---

  assert {
    condition     = tolist(output.public_ip_addresses["fw_a"]) == tolist(["20.90.1.10", "20.90.1.11"])
    error_message = "public_ip_addresses must flatten properties.hubIPAddresses.publicIPs.addresses[*].address, in order. `tolist()` on both sides because a bare literal is a tuple."
  }

  assert {
    condition     = length(output.public_ip_addresses["fw_a"]) == 2
    error_message = "public_ip_addresses must contain one entry per ARM address object."
  }

  # Each element is a STRING, not the `{address = ...}` object ARM returns.
  assert {
    condition     = can(tostring(output.public_ip_addresses["fw_a"][0]))
    error_message = "public_ip_addresses elements must be plain address STRINGS, matching the azurerm Computed TypeList of TypeString at FW L214-218."
  }

  # --- resource_object keeps AzureRM's one-element virtual_hub shape, with
  #     all four members populated. modules/virtual-wan/outputs.tf indexes it
  #     positionally and reads both IP members. ---

  assert {
    condition     = output.resource_object["fw_a"].virtual_hub[0].private_ip_address == "10.100.0.68"
    error_message = "resource_object.virtual_hub[0].private_ip_address must be populated again; modules/virtual-wan/outputs.tf reads it."
  }

  assert {
    condition     = tolist(output.resource_object["fw_a"].virtual_hub[0].public_ip_addresses) == tolist(["20.90.1.10", "20.90.1.11"])
    error_message = "resource_object.virtual_hub[0].public_ip_addresses must be populated again; modules/virtual-wan/outputs.tf reads it."
  }

  # `virtual_hub_id` and `public_ip_count` still come from CONFIGURATION, so
  # they stay known at plan time even though their two siblings do not.
  assert {
    condition     = output.resource_object["fw_a"].virtual_hub[0].public_ip_count == 2
    error_message = "public_ip_count must still be derived from configuration, not from the response."
  }
}

# ---------------------------------------------------------------------------
# THE UNPROVISIONED FIREWALL. ARM returns `hubIPAddresses` absent or
# half-populated while a hub firewall is still deploying. The outputs must
# DEGRADE, not explode.
# ---------------------------------------------------------------------------
run "absent_hub_ip_addresses_degrade" {
  command = apply

  override_data {
    target = data.azapi_resource.fw_hub_ip_addresses["fw_a"]
    values = {
      # `properties` present, `hubIPAddresses` entirely absent.
      output = {
        properties = {}
      }
    }
  }

  assert {
    condition     = output.private_ip_address["fw_a"] == null
    error_message = "An absent hubIPAddresses must yield null rather than failing the plan."
  }

  assert {
    condition     = length(output.public_ip_addresses["fw_a"]) == 0
    error_message = "An absent hubIPAddresses must yield an empty list, matching the nil slice azurerm's flattener produced (FW L799-820)."
  }
}

# Half-populated: `privateIPAddress` assigned but no public IPs yet.
run "partial_hub_ip_addresses_degrade" {
  command = apply

  override_data {
    target = data.azapi_resource.fw_hub_ip_addresses["fw_a"]
    values = {
      output = {
        properties = {
          hubIPAddresses = {
            privateIPAddress = "10.100.0.68"
          }
        }
      }
    }
  }

  assert {
    condition     = output.private_ip_address["fw_a"] == "10.100.0.68"
    error_message = "A present privateIPAddress must be published even when publicIPs is absent."
  }

  assert {
    condition     = length(output.public_ip_addresses["fw_a"]) == 0
    error_message = "An absent publicIPs must yield an empty list, not an error."
  }
}
