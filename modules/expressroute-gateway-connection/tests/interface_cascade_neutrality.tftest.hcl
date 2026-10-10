# TFFR6 / TFFR7 / TFFR8 interface cascade -- the CHILD half of the neutrality proof, second
# witness. Companion to `modules/virtual-hub/tests/interface_cascade_neutrality.tftest.hcl`; read
# that file's header for the full argument.
#
# THIS MODULE IS THE WITNESS THAT MATTERS MOST FOR `retry`. It declares THREE retry regexes, not
# one, because it writes a child of an ExpressRoute gateway and a write landing while the parent
# gateway is still `provisioningState: Updating` fails with a transient 409. If a cascade from
# `modules/virtual-wan` were ever to overwrite that list with the parent's single-entry default,
# a retried 409 would become a failed apply -- silently, and only under load.
#
# That is not hypothetical. Before this work `modules/virtual-wan`'s `var.retry` carried its
# defaults INLINE, so an unset `var.retry` evaluated to `["ReferencedResourceNotProvisioned"]`
# rather than to null, and a plain `retry = var.retry` cascade would have narrowed this module to
# one regex. The defaults were moved to `modules/virtual-wan/locals.retry.tf` precisely so the
# cascade carries nulls. This run is what pins the consequence.
#
# 🔴 WHY `command = apply`: `retry` and `timeouts` are provider arguments rather than body content,
# so a plan-only run would report them straight back from configuration. Applying against
# `mock_provider "azapi"` -- no Azure call, no credentials, no cost -- puts them in state.

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test/expressRouteConnections/erconn-cascade"
    }
  }
}

variables {
  er_circuit_connections = {
    conn_a = {
      name                             = "erconn-cascade"
      express_route_gateway_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test"
      express_route_circuit_peering_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-test/peerings/AzurePrivatePeering"
    }
  }

  # VERBATIM the payload `modules/virtual-wan` sends with its own inputs unset.
  resource_types = {
    network_express_route_gateways_express_route_connections = null
  }
  ignore_body_changes = {
    network_express_route_gateways_express_route_connections = []
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
    condition     = azapi_resource.this["conn_a"].type == "Microsoft.Network/expressRouteGateways/expressRouteConnections@2025-07-01"
    error_message = "A null resource_types leaf from the parent must resolve to this module's own declared API version."
  }

  # Null check on its own: `alltrue()` does not short-circuit, and `length(null)` aborts the run
  # with an evaluation error instead of failing cleanly.
  assert {
    condition     = azapi_resource.this["conn_a"].retry.error_message_regex != null
    error_message = "A null retry payload from the parent must not leave error_message_regex null."
  }

  assert {
    condition = (
      length(azapi_resource.this["conn_a"].retry.error_message_regex) == 3 &&
      contains(azapi_resource.this["conn_a"].retry.error_message_regex, "ReferencedResourceNotProvisioned") &&
      contains(azapi_resource.this["conn_a"].retry.error_message_regex, "AnotherOperationInProgress") &&
      contains(azapi_resource.this["conn_a"].retry.error_message_regex, "(?s)OperationNotAllowed.*Updating")
    )
    error_message = "The cascade must not narrow this module's three-entry retry regex list; the 409 mitigation depends on all three."
  }

  assert {
    condition = (
      azapi_resource.this["conn_a"].retry.interval_seconds == 10 &&
      azapi_resource.this["conn_a"].retry.max_interval_seconds == 180
    )
    error_message = "A null retry payload from the parent must resolve to this module's own interval defaults."
  }

  assert {
    condition = (
      azapi_resource.this["conn_a"].timeouts.create == "30m" &&
      azapi_resource.this["conn_a"].timeouts.read == "5m" &&
      azapi_resource.this["conn_a"].timeouts.update == "30m" &&
      azapi_resource.this["conn_a"].timeouts.delete == "30m"
    )
    error_message = "A null timeouts payload from the parent must resolve to this module's local.timeouts fallbacks, not to a null."
  }
}
