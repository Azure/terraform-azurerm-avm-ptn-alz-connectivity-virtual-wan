# The ForceNew guard on `virtual_hub_id`, exercised end to end.
#
# WHY THIS IS A SEPARATE FILE. The failing side of the precondition cannot be reached from a
# fresh plan: with no prior state the full writer's `body` comes straight from configuration,
# so both operands are the configured hub and the check always passes. It needs PRIOR STATE,
# which means a `command = apply` run first -- and a run file shares state across its runs, so
# introducing an apply into `null_optionals.tftest.hcl` would turn every later plan-only run
# there into a plan against an existing gateway. Hence its own file.
#
# `mock_provider` means no Azure calls, no credentials and no cost. The apply is entirely
# against the mock, so nothing is created anywhere.

# `mock_resource` is required, not decoration: the default mock generates an 8-character random
# string for every computed attribute, and `azapi_update_resource.resource_id` -- wired to
# `azapi_resource.this[...].id` -- is validated by the provider as an ARM resource ID and
# rejects anything that does not start with "/". A fixed ID is fine here; nothing in this file
# depends on the two gateways having distinct IDs.
mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-guard"
    }
  }
}

variables {
  resource_types = {
    network_express_route_gateways = "Microsoft.Network/expressRouteGateways@2025-07-01"
  }
}

# ---------------------------------------------------------------------------------------------
# Establish state. Everything after this run plans against a gateway that ARM (well, the mock)
# already holds on hub A.
#
# Hub A and hub B below deliberately share a subscription AND a resource group. If they did
# not, swapping the hub would also move `parent_id`, which is ForceNew on `azapi_resource`
# (azapi_resource.go L198), and the run would be testing replacement rather than the guard.
# The only thing that differs between the two IDs is the hub name.
run "create_on_hub_a" {
  command = apply

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-guard"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a"
        location            = "uksouth"
        resource_group_name = "rg-test"
        scale_units         = 2
      }
    }
  }

  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.virtualHub.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a"
    error_message = "The applied state body must carry hub A; every later run in this file depends on it."
  }
}

# ---------------------------------------------------------------------------------------------
# THE ONE THAT MATTERS. Same gateway, same name, same location, same resource group, same
# parent -- only the hub moves. Under `azurerm` this was a ForceNew and the gateway would have
# been destroyed and recreated, taking every ExpressRoute connection with it. azapi has no
# per-property ForceNew, so without the precondition this plan would be a silent no-op: `body`
# is in `lifecycle.ignore_changes`, so the new hub never reaches the provider at all.
run "hub_change_fails_at_plan" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-guard"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-b"
        location            = "uksouth"
        resource_group_name = "rg-test"
        scale_units         = 2
      }
    }
  }

  expect_failures = [
    azapi_update_resource.this,
  ]
}

# The same guard must NOT fire when nothing moved. A precondition that fails on a hub change is
# only useful if it is quiet otherwise; this run is what stops the guard from being tightened
# into something that blocks ordinary day-2 edits.
run "unchanged_hub_still_plans" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-guard"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a"
        location            = "uksouth"
        resource_group_name = "rg-test"
        scale_units         = 8
      }
    }
  }

  # A genuine day-2 change on a NON-ForceNew property still reaches the merge writer.
  assert {
    condition     = azapi_update_resource.this["gw_a"].body.properties.autoScaleConfiguration.bounds.min == 8
    error_message = "scale_units is not ForceNew (express_route_gateway_resource.go L65-L69), so the guard must let it through to the merge writer."
  }

  # And the full writer's body is still pinned to the create-time value -- which is precisely
  # the property that makes the precondition a reliable read of the live gateway.
  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.autoScaleConfiguration.bounds.min == 2
    error_message = "lifecycle.ignore_changes = [body] must pin the full writer's body to the create-time value; if this ever fails, the precondition is reading configuration rather than state and the guard is worthless."
  }
}

# ARM resource IDs are case-insensitive, so a hub ID that differs only in casing is the SAME
# hub. `lower()` on both sides of the precondition is what makes this pass; without it an
# AzureRM-era config that spelled the resource group differently would be rejected outright.
run "hub_case_difference_is_not_a_change" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-guard"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/RG-TEST/providers/Microsoft.Network/virtualHubs/VHUB-A"
        location            = "uksouth"
        resource_group_name = "rg-test"
        scale_units         = 2
      }
    }
  }

  assert {
    condition     = azapi_update_resource.this["gw_a"].resource_id == azapi_resource.this["gw_a"].id
    error_message = "The merge writer must still be wired to the full writer once the case-only hub difference has passed the guard."
  }
}

# THE ADDITION/REMOVAL DIRECTION. The precondition is SYMMETRIC and fail-closed -- both sides
# are `try(..., "")` and compared unconditionally -- specifically so that a null on one side
# cannot make it vacuous and let a ForceNew value be added or dropped unchecked. This run
# closes the CONFIG side of that: `virtual_hub_id` cannot be nulled out, because the variable's
# own regex validation rejects it before the precondition is ever reached. Together with the
# fail-closed comparison, that means neither "absent in state, present in config" nor "present
# in state, absent in config" can slip through silently.
run "hub_cannot_be_removed_from_config" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-guard"
        virtual_hub_id      = null
        location            = "uksouth"
        resource_group_name = "rg-test"
        scale_units         = 2
      }
    }
  }

  expect_failures = [
    var.expressroute_gateways,
  ]
}

# NOT TESTED HERE, AND THE REASONS ARE WORTH RECORDING.
#
# (1) The STATE side of the addition direction -- a prior body that does not carry
#     `properties.virtualHub.id` at all -- cannot be constructed under `mock_provider`.
#     `body` is a CONFIGURED attribute, and terraform test's mocking only ever fills in
#     UNKNOWN values (`mocking.ApplyComputedValuesForResource`), so neither `mock_resource`
#     defaults nor `override_resource` values can strip a key out of it. The fail-closed
#     comparison is what covers that case; azapi's own `ImportState` makes it unreachable in
#     practice by setting `state.Body` from the FULL live response
#     (`azapi_resource.go` L1408-L1413).
#
# (2) The `-replace` escape hatch named in the precondition's error message cannot be exercised
#     from `terraform test`: there is no way to pass `-replace` to a `run` block, and
#     `mock_provider` short-circuits `PlanResourceChange` entirely
#     (`node_resource_abstract_instance.go` L1222-L1233 takes the `n.override != nil` branch),
#     so the azapi plan modifiers that would otherwise force a replacement -- `name` L189,
#     `parent_id` L198, `location` ModifyPlan L734 -- never run either. The escape hatch is
#     instead verified by reading Terraform core: on `action.IsReplace()` the body is re-planned
#     from `origConfigVal`, the config with NO ignore_changes applied (L1207-L1220), so the
#     planned body carries the NEW hub and the precondition is satisfied. Anything stronger
#     than that needs a real provider.
