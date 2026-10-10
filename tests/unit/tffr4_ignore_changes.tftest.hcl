# TFFR4 -- `response_export_values` is declared everywhere, and `ignore_changes` is what makes that
# safe.
#
# AVM spec TFFR4 is `Severity-MUST` and `Class-Pattern`:
#
#   > Authors MUST specify the `response_export_values` argument when using the AzAPI provider:
#   > `response_export_values = []` -- must be specified, even if empty.
#
# An earlier change in this repository removed the attribute from every AzAPI
# resource. That breached a MUST and has been retracted. The attribute is back on all of them.
#
# The hazard that change was reacting to is real. `response_export_values` carries no `skip_on`
# struct tag (azapi v2.12.0, `internal/services/azapi_resource.go` L77), so
# `skip.CanSkipExternalRequest` (`internal/skip/skip.go` L14-56, called from `azapi_resource.go`
# L826) returns false as soon as plan and state differ on it -- which produces `actions: ["update"]`
# and a full PUT of the stale `state.body`. At ADOPTION the imported state holds `null` and the
# configuration holds `[]`, and `[]` is not `null`.
#
# `lifecycle.ignore_changes` is the half of the change that defuses it: Terraform substitutes the
# prior state value for the configured one, so the planned value stays `null` and there is nothing
# to act on. Every `azapi_resource` in this repository names `response_export_values` in its
# `ignore_changes`.
#
# WHY THIS TEST USES A FIXTURE AND `command = apply`:
#
#   * `terraform test` cannot introspect a `lifecycle` block. A `contains(local.mirror, "...")`
#     assertion against a hand-maintained list -- the pattern used in
#     `modules/site-to-site-gateway/tests/null_optionals.tftest.hcl` and
#     `modules/virtual-wan/tests/p2s_vpn_gateway.tftest.hcl` -- pins the documentation of the list,
#     not the list itself. This test pins the BEHAVIOUR instead.
#   * The real modules hard-code `response_export_values = []`, so no input can vary it between two
#     runs. Demonstrating `ignore_changes` requires a value that changes, so the mechanism is
#     exercised on a fixture that takes the list as a variable, with a CONTROL resource that is
#     identical except for the missing `lifecycle` block.
#   * `command = plan` alone would prove nothing: with no prior state, a planned attribute simply
#     equals its configuration whether or not `ignore_changes` names it. The discriminating run has
#     to sit on top of state written by a real `apply`, hence `command = apply` against
#     `mock_provider "azapi"` and a shared `state_key`.
#
# 🔴 DO NOT REWRITE THESE ASSERTIONS AS `tolist(x) == tolist([])`. It looks tidier and it is
# broken: the empty tuple literal converts to `list(dynamic)`, the attribute is `list(string)`,
# and cty refuses to compare them -- the assertion fails with "LHS and RHS values are of different
# types" while the reported value is plainly `[]`. Measured here on. The two conditions
# below, `!= null` and `length(...) == 0`, are also a more faithful statement of what TFFR4
# requires: the attribute must be PRESENT, and it must be EMPTY.

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-tffr4"
    }
  }
}

# ---------------------------------------------------------------------------------------------
# 1. Seed state the way an adoption does: the attribute declared, and empty.
# ---------------------------------------------------------------------------------------------
run "seed_state_with_an_empty_export_list" {
  command   = apply
  state_key = "tffr4"

  module {
    source = "./tests/unit/fixtures/tffr4_ignore_changes"
  }

  variables {
    export_values = []
  }

  assert {
    condition = (
      azapi_resource.guarded.response_export_values != null && length(azapi_resource.guarded.response_export_values) == 0 &&
      azapi_resource.unguarded.response_export_values != null && length(azapi_resource.unguarded.response_export_values) == 0
    )
    error_message = "Both fixture resources must start from a declared, empty response_export_values -- the state this repository's modules produce."
  }
}

# ---------------------------------------------------------------------------------------------
# 2. The discriminating run. Change the export list and re-plan on top of that state.
#
#    `guarded` must keep the prior `[]`, because its `lifecycle.ignore_changes` names the
#    attribute. `unguarded` must move to the new list. If `ignore_changes` ever stopped covering
#    `response_export_values`, `guarded` would track `unguarded` and the first assertion fails --
#    and that is precisely the configuration that reopens the adoption PUT.
# ---------------------------------------------------------------------------------------------
run "ignore_changes_pins_the_prior_export_list" {
  command   = plan
  state_key = "tffr4"

  module {
    source = "./tests/unit/fixtures/tffr4_ignore_changes"
  }

  variables {
    export_values = ["properties.provisioningState"]
  }

  assert {
    condition     = azapi_resource.guarded.response_export_values != null && length(azapi_resource.guarded.response_export_values) == 0
    error_message = "lifecycle.ignore_changes must contain response_export_values: the planned value has to stay at the prior state value, not follow the configuration. Without this, an adoption's null-vs-[] difference alone forces a full PUT of the stale state.body."
  }

  assert {
    condition     = join("|", azapi_resource.unguarded.response_export_values) == "properties.provisioningState"
    error_message = "The control resource must follow its configuration. If it does not, this test is no longer discriminating and the assertion above proves nothing."
  }
}

# ---------------------------------------------------------------------------------------------
# 3. The consequence, pinned so it cannot be forgotten: editing an export list is a NO-OP.
#
#    `ignore_changes` keeps the prior value through apply as well as plan. A future change to any
#    `response_export_values` list in this repository therefore needs its own migration -- a
#    `terraform state rm` plus a re-import, or `-replace`. It is a breaking change with an
#    upgrade-guide entry, not a cosmetic edit.
# ---------------------------------------------------------------------------------------------
run "editing_the_export_list_alone_does_not_take_effect" {
  command   = apply
  state_key = "tffr4"

  module {
    source = "./tests/unit/fixtures/tffr4_ignore_changes"
  }

  variables {
    export_values = ["properties.provisioningState"]
  }

  assert {
    condition     = azapi_resource.guarded.response_export_values != null && length(azapi_resource.guarded.response_export_values) == 0
    error_message = "Applying a changed export list must NOT update a resource that ignores the attribute. If this ever passes through, the 'a future export-list change needs its own migration' warning in docs/upgrade-guide.md and in every writer comment is wrong and must be rewritten."
  }
}

# ---------------------------------------------------------------------------------------------
# 4. A real repository module, to prove the declaration itself is present and empty.
#
#    `modules/route-map` is the smallest module in the repository that owns an `azapi_resource`,
#    so it is the cheapest place to assert the TFFR4 declaration against real module code rather
#    than a fixture. The per-module suites carry the same assertion for the firewall, the
#    site-to-site gateway and the P2S gateway writers.
# ---------------------------------------------------------------------------------------------
run "route_map_declares_an_empty_export_list" {
  command   = apply
  state_key = "tffr4_route_map"

  module {
    source = "./modules/route-map"
  }

  variables {
    name           = "rm-tffr4"
    virtual_hub_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
  }

  assert {
    condition     = azapi_resource.route_map.response_export_values != null && length(azapi_resource.route_map.response_export_values) == 0
    error_message = "modules/route-map must declare response_export_values -- TFFR4 is Severity-MUST -- and must declare it EMPTY, because nothing in outputs.tf reads .output and the computed-output rule keeps a computed .output out of a module output."
  }
}
