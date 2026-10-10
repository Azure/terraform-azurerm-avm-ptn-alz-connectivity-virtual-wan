# ---------------------------------------------------------------------------
# THE FORCENEW GUARD, ADDITION HALF. `lifecycle.precondition` on `azapi_update_resource.fw`,
# one per AzureRM `ForceNew: true` field that lives inside the request body:
# `sku_name` (FW L73 -> properties.sku.name) and `zones` (FW L227 -> TOP-LEVEL
# body.zones). See the audit block in `main.tf` for why those are the only two.
#
# 🔴 WHY THE FIRST RUN IS `command = apply` AND EVERY LATER ONE IS `plan`.
# The precondition compares `azapi_resource.fw[k].body` -- the STATE body,
# pinned by `ignore_changes = [body]` -- against the genesis body built from
# today's configuration. Inside a single plan-only run there IS no prior
# state, so that expression resolves to the CONFIG body and the check compares
# the configuration against itself: it passes unconditionally and proves
# NOTHING. A green plan-only suite here would be a false negative. `terraform
# test` carries state across runs within a file, so the `genesis` apply below
# lays down the state body that every later run diffs against.
#
# 🔴 WHY `mock_resource` IS NEEDED. The mock provider invents an 8-character
# token for the computed `azapi_resource.fw.id`, and `azapi_update_resource`
# rejects it at apply with `invalid resource ID: resource id 'ac7hrm78' must
# start with '/'`. Plan-only suites never hit this because `id` stays unknown.
#
# mock_provider means no Azure calls, no credentials and no cost.
# ---------------------------------------------------------------------------

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-mock"
    }
  }

  # The hub IP data source is read during the genesis apply. Its values are
  # asserted in `hub_ip_outputs.tftest.hcl`; here it only has to not explode.
  mock_data "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-mock"
      output = {
        properties = {
          hubIPAddresses = {
            privateIPAddress = "10.0.0.4"
            publicIPs = {
              count     = 1
              addresses = [{ address = "20.0.0.1" }]
            }
          }
        }
      }
    }
  }
}

variables {
  diagnostic_settings = {}
}

# ---------------------------------------------------------------------------
# GENESIS. Lays down the state body the preconditions diff against.
#
# ONE firewall, `fw_b`, created with BOTH ForceNew body properties ABSENT:
#   sku_name "" -- FW L325-330: an empty name omits `properties.sku.name`
#   zones    [] -- FW L279-282: an empty set omits the top-level `zones`
#
# That absent state is the whole point of this file, and it is why it cannot
# live in `forcenew_preconditions.tftest.hcl`: that file's genesis creates
# `fw_a` WITH both properties, and `terraform test` carries one state per
# file. The change/removal half lives there; the ADDITION half lives here.
# ---------------------------------------------------------------------------
run "genesis" {
  command = apply

  variables {
    firewalls = {
      fw_b = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = ""
        sku_tier            = "Standard"
        name                = "fw-b"
        zones               = []
      }
    }
  }

  # The state body really does LACK what the guard will read back. Without
  # these two, the addition cases below would be comparing an absent state
  # half against an absent config half and passing vacuously.

  assert {
    condition     = !can(azapi_resource.fw["fw_b"].body.properties.sku.name)
    error_message = "Genesis must OMIT sku.name for fw_b (empty sku_name, FW L325-330); the addition case depends on it being absent."
  }

  assert {
    condition     = !can(azapi_resource.fw["fw_b"].body.zones)
    error_message = "Genesis must OMIT zones for fw_b (empty zones, FW L279-282); the addition case depends on it being absent."
  }
}

# ---------------------------------------------------------------------------
# THE PASSING DIRECTION, absent against absent. Re-planning the genesis
# configuration unchanged must NOT fail -- a guard that fires on a no-op is
# worse than no guard, and for THIS state both halves are absent, so this is
# precisely the `null == null` / `{} == {}` case.
#
# It also proves the two failures below are not vacuous: if the guard simply
# always fired on fw_b, this run would fail too.
# ---------------------------------------------------------------------------
run "absent_unchanged_passes" {
  command = plan

  variables {
    firewalls = {
      fw_b = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = ""
        sku_tier            = "Standard"
        name                = "fw-b"
        zones               = []
      }
    }
  }

  # Mutable properties must still be free to move even on this firewall.
  assert {
    condition     = azapi_update_resource.fw["fw_b"].body.properties.sku.tier == "Standard"
    error_message = "The merge writer must still carry sku_tier; it is not ForceNew and must remain changeable in place."
  }
}

# ---------------------------------------------------------------------------
# THE FAILING DIRECTION, the ADDITION of a ForceNew property.
# ---------------------------------------------------------------------------

# sku_name ADDED: fw_b's state body has NO `properties.sku.name`, and the
# configuration now supplies one. A guard written as the rejected
# `state == null || state == config` would skip on the null state half and
# wave this straight through. Verified individually to resolve to the sku_name
# precondition at `main.tf:344`.
run "sku_name_added_fails" {
  command = plan

  variables {
    firewalls = {
      fw_b = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "AZFW_Hub"
        sku_tier            = "Standard"
        name                = "fw-b"
        zones               = []
      }
    }
  }

  expect_failures = [azapi_update_resource.fw]
}

# zones ADDED: fw_b's state body has NO top-level `zones`, and the
# configuration now supplies [1,2,3]. Absence normalises to the EMPTY SET on
# both halves, so this is `{} != {1,2,3}` and fails -- it is not skipped.
# Verified individually to resolve to the zones precondition at `main.tf:356`.
run "zones_added_fails" {
  command = plan

  variables {
    firewalls = {
      fw_b = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = ""
        sku_tier            = "Standard"
        name                = "fw-b"
        zones               = [1, 2, 3]
      }
    }
  }

  expect_failures = [azapi_update_resource.fw]
}
