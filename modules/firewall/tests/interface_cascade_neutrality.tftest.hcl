# TFFR6 / TFFR7 / TFFR8 interface cascade -- the CHILD half of the neutrality proof, third
# witness. Companion to `modules/virtual-hub/tests/interface_cascade_neutrality.tftest.hcl`; read
# that file's header for the full argument.
#
# THIS MODULE IS THE WITNESS THAT MATTERS MOST FOR `timeouts`, because its `timeouts` variable had
# to be RESHAPED to make the cascade possible and a reshape is exactly the kind of change that
# loses a value quietly. It used to be keyed per resource --
# `timeouts = { network_azure_firewalls = { create = ... }, insights_diagnostic_settings = { ... } }`
# -- which cannot receive `timeouts = var.timeouts` from a parent, because TFFR7's `timeouts` is
# the flat four-attribute object. It is now flat, and the per-resource fallbacks moved verbatim
# into `local.timeouts` in `locals.tf`. Nothing was published: v0.17.2 of this repository declared
# no `timeouts` on this submodule at all, so the reshape breaks no released consumer.
#
# The fallbacks this run pins come from `hashicorp/azurerm` v4.81.0 at
# `5782a75422c68a0d0804ac16d97dcaf3df5ee2fa`:
#   - the Azure Firewall           create 90m, read 5m, update 90m, delete 90m (FW L46-51)
#   - the diagnostic settings      create 30m, read 5m, update 30m, delete 60m (DIAG L43-48)
# 🔴 Note the 60m delete on the diagnostic setting. It is NOT the firewall's 90m and it is NOT the
# diagnostic setting's own 30m create. A single blanket fallback would have flattened it, which is
# the whole reason the fallbacks are per resource.
#
# 🔴 WHY `command = apply`: `timeouts` and `retry` are provider arguments rather than body content,
# so a plan-only run would report them straight back from configuration. Applying against
# `mock_provider "azapi"` -- no Azure call, no credentials, no cost -- puts them in state.

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      # `azapi_update_resource.resource_id` rejects the mock provider's 8-character token with
      # `invalid resource ID: ... must start with '/'`.
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
              count     = 1
              addresses = [{ address = "20.90.1.10" }]
            }
          }
        }
      }
    }
  }
}

variables {
  firewalls = {
    fw_a = {
      virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
      location            = "uksouth"
      resource_group_name = "rg-test"
      sku_tier            = "Standard"
      name                = "fw-a"
    }
  }

  # A diagnostic setting is declared so the SECOND per-resource fallback is actually exercised.
  # With `diagnostic_settings = {}` the 30m/5m/30m/60m row would go unchecked.
  diagnostic_settings = {
    fw_a = {
      to_law = {
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
      }
    }
  }

  # VERBATIM the payload `modules/virtual-wan` sends when its own inputs are unset.
  resource_types = {
    insights_diagnostic_settings = null
    network_azure_firewalls      = null
  }
  ignore_body_changes = {
    insights_diagnostic_settings = []
    network_azure_firewalls      = []
  }
  retry = {
    error_message_regex  = null
    interval_seconds     = null
    max_interval_seconds = null
  }
  timeouts = {
    create = null
    read   = null
    update = null
    delete = null
  }
}

run "an_all_null_cascade_payload_lands_on_this_modules_own_defaults" {
  command = apply

  assert {
    condition = (
      azapi_resource.fw["fw_a"].type == "Microsoft.Network/azureFirewalls@2025-07-01" &&
      azapi_update_resource.fw["fw_a"].type == "Microsoft.Network/azureFirewalls@2025-07-01" &&
      azapi_resource.diagnostic_setting["fw_a-to_law"].type == "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
    )
    error_message = "A null resource_types leaf from the parent must resolve to this module's own declared API versions on all three writers."
  }

  # The firewall's own 90m/5m/90m/90m, on BOTH writers. The two used to be emitted by a
  # `dynamic "timeouts"` block whose `for_each` could never be empty; they are plain static blocks
  # reading `local.timeouts` now, and this assertion is what says the swap kept the values.
  assert {
    condition = (
      azapi_resource.fw["fw_a"].timeouts.create == "90m" &&
      azapi_resource.fw["fw_a"].timeouts.read == "5m" &&
      azapi_resource.fw["fw_a"].timeouts.update == "90m" &&
      azapi_resource.fw["fw_a"].timeouts.delete == "90m" &&
      azapi_update_resource.fw["fw_a"].timeouts.create == "90m" &&
      azapi_update_resource.fw["fw_a"].timeouts.read == "5m" &&
      azapi_update_resource.fw["fw_a"].timeouts.update == "90m" &&
      azapi_update_resource.fw["fw_a"].timeouts.delete == "90m"
    )
    error_message = "A null timeouts payload must resolve to azurerm_firewall's own 90m/5m/90m/90m on both firewall writers."
  }

  # The diagnostic setting's own row, which is DIFFERENT -- and different from the firewall's on
  # three of the four attributes.
  assert {
    condition = (
      azapi_resource.diagnostic_setting["fw_a-to_law"].timeouts.create == "30m" &&
      azapi_resource.diagnostic_setting["fw_a-to_law"].timeouts.read == "5m" &&
      azapi_resource.diagnostic_setting["fw_a-to_law"].timeouts.update == "30m" &&
      azapi_resource.diagnostic_setting["fw_a-to_law"].timeouts.delete == "60m"
    )
    error_message = "A null timeouts payload must resolve to the diagnostic setting's own 30m/5m/30m/60m, not to the firewall's 90m and not to a blanket value."
  }

  # Null check on its own: `alltrue()` and `&&` chains still evaluate `length(null)`, which aborts
  # the run with an evaluation error rather than failing the assertion cleanly.
  assert {
    condition     = azapi_resource.fw["fw_a"].retry.error_message_regex != null
    error_message = "A null retry payload from the parent must not leave error_message_regex null."
  }

  assert {
    condition = (
      length(azapi_resource.fw["fw_a"].retry.error_message_regex) == 1 &&
      azapi_resource.fw["fw_a"].retry.error_message_regex[0] == "ReferencedResourceNotProvisioned" &&
      azapi_resource.fw["fw_a"].retry.interval_seconds == 10 &&
      azapi_resource.fw["fw_a"].retry.max_interval_seconds == 180
    )
    error_message = "A null retry payload from the parent must resolve to this module's own retry defaults."
  }
}

# A consumer-supplied value must still win everywhere, or the flat shape has quietly become
# write-only. One value set, and it has to land on BOTH per-resource rows.
run "a_set_timeout_overrides_every_per_resource_fallback" {
  command = apply

  variables {
    timeouts = {
      create = "11m"
      read   = null
      update = null
      delete = null
    }
  }

  assert {
    condition = (
      azapi_resource.fw["fw_a"].timeouts.create == "11m" &&
      azapi_update_resource.fw["fw_a"].timeouts.create == "11m" &&
      azapi_resource.diagnostic_setting["fw_a-to_law"].timeouts.create == "11m"
    )
    error_message = "A consumer-set timeouts.create must override the per-resource fallback on every resource in the module."
  }

  assert {
    condition = (
      azapi_resource.fw["fw_a"].timeouts.delete == "90m" &&
      azapi_resource.diagnostic_setting["fw_a-to_law"].timeouts.delete == "60m"
    )
    error_message = "Setting one timeouts attribute must not disturb the per-resource fallbacks for the others."
  }
}
