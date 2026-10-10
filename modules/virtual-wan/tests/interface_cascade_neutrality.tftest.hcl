# TFFR6 / TFFR7 / TFFR8 interface cascade -- the PARENT half of the neutrality proof.
#
# WHAT IS BEING PROVEN. `modules/virtual-wan` now passes `resource_types`, `retry`, `timeouts` and
# `ignore_body_changes` down to all eight submodules it calls. The requirement on that change is
# that it be BEHAVIOUR-NEUTRAL at the defaults: with all four inputs unset, every submodule must
# still plan exactly as it did before the arguments existed.
#
# That splits into three independently checkable parts:
#
#   (1) PARENT -- with the inputs unset, the values this module hands to its submodules carry no
#       information: every `resource_types` and `timeouts` leaf is null, every `retry` leaf is
#       null, every `ignore_body_changes` leaf is an empty list. THIS FILE, first run.
#   (2) CHILD -- a submodule receiving exactly that payload falls back to its OWN declared
#       defaults. Proven end-to-end against real resources in the three
#       `interface_cascade_neutrality.tftest.hcl` files under `modules/virtual-hub`,
#       `modules/expressroute-gateway-connection` and `modules/firewall`.
#   (3) CALL SITE -- the eight `module` blocks really do pass `var.retry` and friends rather than
#       this module's own values. THIS FILE, last run, read back through
#       `module.er_connections.resource`.
#
# 🔴 WHAT THIS EVIDENCE DOES NOT COVER. It is not a byte-for-byte diff of two `terraform plan`
# outputs with and without the plumbing. Producing one would need a provider-configured plan, which
# is an Azure call, and there are none in this work. The argument is: the parent sends nulls and
# empty lists (measured here), a null on an `optional(T, default)` attribute is replaced by that
# default (measured in half (2), and independently on Terraform 1.16.2), and an empty
# `ignore_body_changes` list is what every submodule already defaulted to -- therefore every leaf
# resource receives the same values it received before. Each link is measured; the conjunction is
# reasoned.
#
# 🔴 ALSO NOT COVERED: `ignore_body_changes` cannot be asserted on a resource at all. It is a
# write-only argument (`azapi_resource.go` L255 `WriteOnly: true`), so its state value is
# permanently null and `terraform test` has nothing to read. The parent-side assertion below --
# that the list is present and empty -- is the whole of the available evidence for it.
#
# WHY `command = plan` IS ENOUGH FOR THE FIRST TWO RUNS, given the house rule that plan-time
# checks can pass vacuously. That rule is about `precondition` and `lifecycle` blocks, which
# resolve against configuration. A test `assert` reads the PLANNED value, and the things asserted
# in those runs -- variable defaults and `local.retry` -- are known at plan time by construction.
# There is no prior state for them to be compared against, so an apply would add nothing. The
# third run applies, because a submodule's outputs are not resolvable otherwise.

mock_provider "azapi" {
  # Needed only by the end-to-end run at the bottom of this file, which applies:
  # `azapi_update_resource.resource_id` rejects the mock provider's generated 8-character token
  # with "resource id '...' must start with '/'".
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-cascade"
    }
  }

  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "11111111-1111-1111-1111-111111111111"
    }
  }
}

mock_provider "modtm" {}

mock_provider "random" {}

variables {
  enable_telemetry    = false
  location            = "eastus"
  resource_group_name = "rg-test"
  virtual_wan_name    = "vwan-test"
  # `resource_types`, `retry`, `timeouts` and `ignore_body_changes` are deliberately NOT set.
  # Their absence is the condition under test.
}

run "unset_inputs_produce_an_empty_cascade_payload" {
  command = plan

  # ---------------------------------------------------------------------------------------------
  # `resource_types`: every submodule slot is an all-null object, so the submodule stays the single
  # source of truth for its own API version.
  # ---------------------------------------------------------------------------------------------
  assert {
    condition = (
      var.resource_types.network_azure_firewalls.insights_diagnostic_settings == null &&
      var.resource_types.network_azure_firewalls.network_azure_firewalls == null &&
      var.resource_types.network_express_route_gateways.network_express_route_gateways == null &&
      var.resource_types.network_express_route_gateways_express_route_connections.network_express_route_gateways_express_route_connections == null &&
      var.resource_types.network_virtual_hubs.network_virtual_hubs == null &&
      var.resource_types.network_virtual_hubs_hub_virtual_network_connections.network_virtual_hubs_hub_virtual_network_connections == null &&
      var.resource_types.network_vpn_gateways.network_vpn_gateways == null &&
      var.resource_types.network_vpn_gateways_vpn_connections.network_vpn_gateways_vpn_connections == null &&
      var.resource_types.network_vpn_sites.network_vpn_sites == null
    )
    error_message = "With resource_types unset every submodule slot must be null, or the cascade would override a submodule's own API version."
  }

  # This module's OWN seven types keep their inline defaults -- they are not part of the cascade
  # and must not have been stripped along with the submodule slots.
  assert {
    condition = (
      var.resource_types.network_virtual_wans == "Microsoft.Network/virtualWans@2025-07-01" &&
      var.resource_types.resources_resource_groups == "Microsoft.Resources/resourceGroups@2025-04-01"
    )
    error_message = "This module's own resource_types keys must keep their inline defaults."
  }

  # ---------------------------------------------------------------------------------------------
  # `timeouts`: all four attributes null, so each submodule applies its own per-resource fallback.
  # ---------------------------------------------------------------------------------------------
  assert {
    condition = (
      var.timeouts.create == null &&
      var.timeouts.read == null &&
      var.timeouts.update == null &&
      var.timeouts.delete == null
    )
    error_message = "With timeouts unset all four attributes must be null; a non-null value would overwrite every submodule's per-resource timeout."
  }

  # ---------------------------------------------------------------------------------------------
  # `retry`: all three attributes null. This is the assertion that would have caught the real bug
  # -- while the defaults lived on the variable, an unset `var.retry` was
  # `["ReferencedResourceNotProvisioned"]`, and cascading it would have narrowed
  # `../expressroute-gateway-connection` and `../site-to-site-gateway-connection` from three retry
  # regexes to one.
  # ---------------------------------------------------------------------------------------------
  assert {
    condition = (
      var.retry.error_message_regex == null &&
      var.retry.interval_seconds == null &&
      var.retry.max_interval_seconds == null
    )
    error_message = "With retry unset all three attributes must be null; a non-null value would narrow the connection submodules' retry regex lists."
  }

  # ...and `local.retry` restores this module's own historical defaults for its own resources, so
  # moving them off the variable changed nothing here. Asserted on the resource, not the local, so
  # it pins the wiring too.
  assert {
    condition = (
      azapi_resource.virtual_wan[0].retry.error_message_regex != null &&
      length(azapi_resource.virtual_wan[0].retry.error_message_regex) == 1 &&
      azapi_resource.virtual_wan[0].retry.error_message_regex[0] == "ReferencedResourceNotProvisioned" &&
      azapi_resource.virtual_wan[0].retry.interval_seconds == 10 &&
      azapi_resource.virtual_wan[0].retry.max_interval_seconds == 180
    )
    error_message = "This module's own resources must still receive the historical retry defaults, now supplied by local.retry."
  }

  # ---------------------------------------------------------------------------------------------
  # `ignore_body_changes`: every submodule slot present and EMPTY.
  #
  # 🔴 `!= null` AND `length(...) == 0` as two separate clauses, never `tolist(x) == tolist([])`.
  # The empty tuple literal converts to `list(dynamic)` while the attribute is `list(string)`, and
  # cty refuses to compare them -- the assertion fails with "LHS and RHS values are of different
  # types" while printing a value that plainly looks like `[]`.
  # ---------------------------------------------------------------------------------------------
  assert {
    condition = alltrue([
      for paths in [
        var.ignore_body_changes.network_azure_firewalls.insights_diagnostic_settings,
        var.ignore_body_changes.network_azure_firewalls.network_azure_firewalls,
        var.ignore_body_changes.network_express_route_gateways.network_express_route_gateways,
        var.ignore_body_changes.network_express_route_gateways_express_route_connections.network_express_route_gateways_express_route_connections,
        var.ignore_body_changes.network_virtual_hubs.network_virtual_hubs,
        var.ignore_body_changes.network_virtual_hubs_hub_virtual_network_connections.network_virtual_hubs_hub_virtual_network_connections,
        var.ignore_body_changes.network_vpn_gateways.network_vpn_gateways,
        var.ignore_body_changes.network_vpn_gateways_vpn_connections.network_vpn_gateways_vpn_connections,
        var.ignore_body_changes.network_vpn_sites.network_vpn_sites,
      ] : paths != null
    ])
    error_message = "Every ignore_body_changes submodule slot must be a present list, never null -- a null would fail the submodule's own validation."
  }

  # Separate assert, not another clause of the one above: `alltrue()` does not short-circuit, so a
  # null-check and a length-check in the same list comprehension would still evaluate `length(null)`
  # and abort with an evaluation error instead of a clean assertion failure.
  assert {
    condition = alltrue([
      for paths in [
        var.ignore_body_changes.network_azure_firewalls.insights_diagnostic_settings,
        var.ignore_body_changes.network_azure_firewalls.network_azure_firewalls,
        var.ignore_body_changes.network_express_route_gateways.network_express_route_gateways,
        var.ignore_body_changes.network_express_route_gateways_express_route_connections.network_express_route_gateways_express_route_connections,
        var.ignore_body_changes.network_virtual_hubs.network_virtual_hubs,
        var.ignore_body_changes.network_virtual_hubs_hub_virtual_network_connections.network_virtual_hubs_hub_virtual_network_connections,
        var.ignore_body_changes.network_vpn_gateways.network_vpn_gateways,
        var.ignore_body_changes.network_vpn_gateways_vpn_connections.network_vpn_gateways_vpn_connections,
        var.ignore_body_changes.network_vpn_sites.network_vpn_sites,
      ] : length(paths) == 0
    ])
    error_message = "With ignore_body_changes unset every submodule slot must be empty, matching each submodule's own default."
  }
}

# A consumer who DOES set something must still reach the submodules -- otherwise the cascade is
# neutral by being inert, which is not the same thing.
run "a_set_input_reaches_the_submodule_slot" {
  command = plan

  variables {
    resource_types = {
      network_virtual_hubs = {
        network_virtual_hubs = "Microsoft.Network/virtualHubs@2024-05-01"
      }
    }
    retry = {
      interval_seconds = 42
    }
    timeouts = {
      create = "7m"
    }
    ignore_body_changes = {
      network_virtual_hubs = {
        network_virtual_hubs = ["properties.sku"]
      }
    }
  }

  assert {
    condition     = var.resource_types.network_virtual_hubs.network_virtual_hubs == "Microsoft.Network/virtualHubs@2024-05-01"
    error_message = "A resource_types value set by the consumer must survive into the submodule slot."
  }

  assert {
    condition     = var.timeouts.create == "7m" && var.timeouts.read == null
    error_message = "A timeouts attribute set by the consumer must survive; the others must stay null."
  }

  assert {
    condition     = length(var.ignore_body_changes.network_virtual_hubs.network_virtual_hubs) == 1
    error_message = "An ignore_body_changes path set by the consumer must survive into the submodule slot."
  }

  # `local.retry` fills only the attributes the consumer left null, so a partial override does not
  # silently drop the regex list for this module's own resources.
  assert {
    condition = (
      azapi_resource.virtual_wan[0].retry.interval_seconds == 42 &&
      length(azapi_resource.virtual_wan[0].retry.error_message_regex) == 1 &&
      azapi_resource.virtual_wan[0].retry.max_interval_seconds == 180
    )
    error_message = "A partial retry override must apply, and must not blank the attributes local.retry still supplies."
  }
}

# ---------------------------------------------------------------------------------------------
# END-TO-END, THROUGH A REAL CALL SITE.
#
# The two runs above pin the payload and the two `interface_cascade_neutrality.tftest.hcl` files
# under `modules/virtual-hub`, `modules/expressroute-gateway-connection` and `modules/firewall`
# pin what a submodule does with it. Neither says the CALL SITES are wired correctly. This run
# does, by reaching through `module.er_connections`'s `resource` output -- which is the whole
# `azapi_resource` object, provider arguments included -- and reading the values that actually
# landed on the resource inside the submodule.
#
# `../expressroute-gateway-connection` is the right submodule to look through. It declares THREE
# retry regexes where this module declares one, so it is the call site where a wrong source
# expression is visible rather than invisible. Passing `local.retry` instead of `var.retry` here
# would drop `AnotherOperationInProgress` and `(?s)OperationNotAllowed.*Updating` and turn a
# retried 409 into a failed apply.
# ---------------------------------------------------------------------------------------------
run "the_call_sites_pass_the_consumer_value_not_this_modules_own" {
  command = apply

  variables {
    virtual_hubs = {
      hub_a = {
        name                = "vhub-cascade"
        location            = "eastus"
        resource_group_name = "rg-test"
        address_prefix      = "10.0.0.0/23"
      }
    }
    expressroute_gateways = {
      ergw_a = {
        name            = "ergw-cascade"
        virtual_hub_key = "hub_a"
      }
    }
    er_circuit_connections = {
      conn_a = {
        name                             = "erconn-cascade"
        express_route_gateway_key        = "ergw_a"
        express_route_circuit_peering_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-test/peerings/AzurePrivatePeering"
      }
    }
  }

  # Own assert, because `&&` still evaluates its right-hand side and `length(null)` aborts the run
  # with an evaluation error rather than a clean failure.
  assert {
    condition     = module.er_connections.resource[0].retry.error_message_regex != null
    error_message = "The er_connections call site must not deliver a null retry.error_message_regex."
  }

  assert {
    condition     = length(module.er_connections.resource[0].retry.error_message_regex) == 3
    error_message = "The er_connections call site must leave the submodule on its OWN three-entry retry regex list. One entry means this module cascaded local.retry instead of var.retry."
  }

  # `timeouts` reaches the submodule as nulls too, so the submodule's own 30m/5m/30m/30m stands
  # rather than anything of this module's.
  assert {
    condition = (
      module.er_connections.resource[0].timeouts.create == "30m" &&
      module.er_connections.resource[0].timeouts.read == "5m" &&
      module.er_connections.resource[0].timeouts.update == "30m" &&
      module.er_connections.resource[0].timeouts.delete == "30m"
    )
    error_message = "The er_connections call site must leave the submodule on its own per-resource timeout fallbacks."
  }

  assert {
    condition     = module.er_connections.resource[0].type == "Microsoft.Network/expressRouteGateways/expressRouteConnections@2025-07-01"
    error_message = "The er_connections call site must leave the submodule on its own declared API version."
  }
}
