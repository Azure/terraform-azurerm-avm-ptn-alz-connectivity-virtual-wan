# ---------------------------------------------------------------------------
# THE FORCENEW GUARD. `lifecycle.precondition` on `azapi_update_resource.fw`,
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
# fw_a is created WITH `sku_name` and WITH `zones`, so every later run has a
# non-null state half to diff against. The mirror case -- a state body that
# LACKS both, so the guard has to catch a ForceNew property being ADDED -- is
# `forcenew_additions.tftest.hcl`, which needs its own state and therefore its
# own file.
# ---------------------------------------------------------------------------
run "genesis" {
  command = apply

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "AZFW_Hub"
        sku_tier            = "Standard"
        name                = "fw-a"
        zones               = [1, 2, 3]
      }
    }
  }

  # The state body really does carry what the guard will read back. Without
  # these two, every later run could be comparing null against null and
  # passing vacuously, and the suite would be a false negative.
  assert {
    condition     = azapi_resource.fw["fw_a"].body.properties.sku.name == "AZFW_Hub"
    error_message = "Genesis must put sku.name in fw_a's body, otherwise every later run compares null against null and passes vacuously."
  }

  assert {
    condition     = toset([for z in azapi_resource.fw["fw_a"].body.zones : tostring(z)]) == toset(["1", "2", "3"])
    error_message = "Genesis must put the TOP-LEVEL zones member in fw_a's body (not under properties), otherwise the zones guard compares empty set against empty set and passes vacuously."
  }
}

# ---------------------------------------------------------------------------
# THE PASSING DIRECTION. Re-planning the genesis configuration unchanged must
# NOT fail -- a guard that fires on a no-op is worse than no guard.
# ---------------------------------------------------------------------------
run "unchanged_passes" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "AZFW_Hub"
        sku_tier            = "Standard"
        name                = "fw-a"
        zones               = [1, 2, 3]
      }
    }
  }

  # Mutable properties must still be free to move. `sku_tier`,
  # `firewall_policy_id`, `virtual_hub_id` and `vhub_public_ip_count` are NOT
  # ForceNew in AzureRM (FW L81-89, L91-95, L203-207, L208-213) and must not be
  # guarded; this asserts the merge writer still carries the new tier.
  assert {
    condition     = azapi_update_resource.fw["fw_a"].body.properties.sku.tier == "Standard"
    error_message = "The merge writer must still carry sku_tier; it is not ForceNew and must remain changeable in place."
  }
}

# A tier change alone must pass. This is the regression that a careless
# precondition on `properties.sku` (rather than `properties.sku.name`) would
# cause.
run "sku_tier_change_passes" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "AZFW_Hub"
        sku_tier            = "Premium"
        name                = "fw-a"
        zones               = [1, 2, 3]
      }
    }
  }

  assert {
    condition     = azapi_update_resource.fw["fw_a"].body.properties.sku.tier == "Premium"
    error_message = "Changing sku_tier must reach the merge writer and must not trip the sku_name guard."
  }
}

# A hub move must pass too: AzureRM does not mark `virtual_hub_id` ForceNew
# (FW L203-207) and the merge writer declares it precisely so it can change.
run "virtual_hub_change_passes" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-OTHER"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "AZFW_Hub"
        sku_tier            = "Standard"
        name                = "fw-a"
        zones               = [1, 2, 3]
      }
    }
  }

  assert {
    condition     = azapi_update_resource.fw["fw_a"].body.properties.virtualHub.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-OTHER"
    error_message = "virtual_hub_id is NOT ForceNew in AzureRM and must stay changeable in place; a precondition on it would break a supported operation."
  }
}

# Case alone must not fail: ARM echoes the SKU name back and nothing treats
# AZFW_Hub and azfw_hub as different firewalls. Both halves are `lower()`ed.
run "sku_name_case_only_passes" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "azfw_hub"
        sku_tier            = "Standard"
        name                = "fw-a"
        zones               = [1, 2, 3]
      }
    }
  }
}

# Re-ORDERING zones must not fail. ARM may return the array in any order, and
# AzureRM's schema was a TypeSet, so both halves are compared as `toset()`.
run "zones_reordered_passes" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "AZFW_Hub"
        sku_tier            = "Standard"
        name                = "fw-a"
        # Same SET as genesis, different order, plus a duplicate that
        # `toset()` collapses.
        zones = [3, 2, 1, 1]
      }
    }
  }
}

# ---------------------------------------------------------------------------
# THE FAILING DIRECTION. Each of these is a change AzureRM would have handled
# by DESTROYING and recreating the firewall.
# ---------------------------------------------------------------------------

# sku_name CHANGED: AZFW_Hub -> AZFW_VNet. Resolves to the sku_name
# precondition at `main.tf:344`.
run "sku_name_changed_fails" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "AZFW_VNet"
        sku_tier            = "Standard"
        name                = "fw-a"
        zones               = [1, 2, 3]
      }
    }
  }

  expect_failures = [azapi_update_resource.fw]
}

# sku_name REMOVED: "AZFW_Hub" -> "" omits `properties.sku.name` from the
# genesis body, so the config half goes null while the state half does not.
# This is the case the rejected `state == null || state == config` form would
# have let through in the other direction. Resolves to `main.tf:344`.
run "sku_name_removed_fails" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = ""
        sku_tier            = "Standard"
        name                = "fw-a"
        zones               = [1, 2, 3]
      }
    }
  }

  expect_failures = [azapi_update_resource.fw]
}

# zones CHANGED: {1,2,3} -> {1,2}. A genuinely different SET, so `toset()`
# equality is false and the guard fires. Verified individually to resolve to
# the zones precondition at `main.tf:356`, not the sku_name one at 344 --
# `expect_failures` names only the RESOURCE, so without that check a single
# over-broad precondition could satisfy every case in this file.
run "zones_changed_fails" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "AZFW_Hub"
        sku_tier            = "Standard"
        name                = "fw-a"
        zones               = [1, 2]
      }
    }
  }

  expect_failures = [azapi_update_resource.fw]
}

# zones REMOVED: {1,2,3} -> absent. AzureRM would have rebuilt the firewall as
# non-zonal. Resolves to the zones precondition at `main.tf:356`.
run "zones_removed_fails" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "AZFW_Hub"
        sku_tier            = "Standard"
        name                = "fw-a"
        zones               = []
      }
    }
  }

  expect_failures = [azapi_update_resource.fw]
}

# The ADDITION half of both guards -- a state body that LACKS `sku.name` and
# LACKS `zones`, with the configuration then supplying them -- needs its own
# genesis state and therefore its own file:
# `forcenew_additions.tftest.hcl`.
