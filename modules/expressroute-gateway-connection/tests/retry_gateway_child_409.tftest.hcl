# Covers the same-apply 409 race on an ExpressRoute gateway CHILD. See the long note above
# `variable "retry"` in `variables.tf` for the measurement and the reasoning; this file is
# the executable half of it. Its twin is
# `modules/site-to-site-gateway-connection/tests/retry_gateway_child_409.tftest.hcl` -- the
# two modules share the failure mode and the fix, so they share the test shape.
#
# WHAT IS ACTUALLY AT RISK. `azapi_resource.this` here writes
# `Microsoft.Network/expressRouteGateways/expressRouteConnections`. A write to the PARENT
# gateway returns to Terraform while the RP keeps the gateway -- and its connections -- in
# `provisioningState: Updating` for minutes. The effect was measured on the vpn gateway side
# of the same pattern: a tags-only PUT returned immediately with the gateway busy for ~4m30s
# afterwards. `modules/expressroute-gateway` additionally uses a two-writer shape
# (`azapi_resource.this` then `azapi_update_resource.this`), so the parent takes two writes
# in one apply before this module's connection write is even attempted.
#
# 🔴 WHY THE FIRST RUN IS `command = apply` AND THE REST ARE `plan`.
# A suite whose runs are ALL `plan` can pass vacuously. The `apply` run is what proves the
# provider actually ACCEPTS this retry block: `error_message_regex` carries
# `myvalidator.StringIsValidRegex()` and `listvalidator.UniqueValues()`
# (`internal/retry/schema.go` L26-L30), so a malformed or duplicated pattern is rejected by
# the provider rather than by anything written here. A run file shares state across its
# runs, so `genesis` also gives every later `plan` run prior state to plan against.
#
# 🔴 WHY `mock_resource` IS NEEDED. The mock provider invents an 8-character random token
# for every computed attribute including `id`, and anything validating an ARM resource ID
# rejects it with `invalid resource ID: resource id '...' must start with '/'`. Plan-only
# suites never hit this because `id` stays unknown; the `apply` run above does.
#
# ⚠️ The override gives EVERY mocked `azapi_resource` in this file the SAME id. No assertion
# below may meaningfully read `.id`, and none does.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test/expressRouteConnections/erconn-mock"
    }
  }
}

variables {
  resource_types = {
    network_express_route_gateways_express_route_connections = "Microsoft.Network/expressRouteGateways/expressRouteConnections@2025-07-01"
  }
  er_circuit_connections = {
    conn_a = {
      name                             = "erconn-retry"
      express_route_gateway_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test"
      express_route_circuit_peering_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-test/peerings/AzurePrivatePeering"
    }
  }
}

# ---------------------------------------------------------------------------
# The provider must accept the shipped retry block end to end. If the defaults in
# `variables.tf` ever stop compiling as regexes, or pick up a duplicate, this run fails
# inside the provider and no assertion below is reached.
# ---------------------------------------------------------------------------
run "genesis" {
  command = apply

  assert {
    condition     = azapi_resource.this["conn_a"].retry != null
    error_message = "The retry block must survive a real apply: it is the only mitigation for the parent-gateway 409 race."
  }
}

# ---------------------------------------------------------------------------
# The mitigation is ON BY DEFAULT. A consumer who never mentions `retry` must still get
# both race patterns -- that is the whole point of putting them in the variable default
# rather than asking callers to opt in. `modules/virtual-wan` does not pass `retry` down to
# this module, so the default here is what the whole stack actually runs with.
# ---------------------------------------------------------------------------
run "race_regexes_are_on_by_default" {
  command = plan

  assert {
    condition     = contains(azapi_resource.this["conn_a"].retry.error_message_regex, "AnotherOperationInProgress")
    error_message = "The default error_message_regex must retry AnotherOperationInProgress: that is the 409 a busy parent gateway returns."
  }

  assert {
    condition     = contains(azapi_resource.this["conn_a"].retry.error_message_regex, "(?s)OperationNotAllowed.*Updating")
    error_message = "The default error_message_regex must retry OperationNotAllowed-while-Updating, and the pattern must keep its (?s) prefix. Without (?s) it cannot match a real ARM error -- see the regex_actually_matches_a_real_arm_409 run."
  }

  # The pre-existing pattern predates this change and is NOT ours to drop. Adding the race
  # patterns must be additive.
  assert {
    condition     = contains(azapi_resource.this["conn_a"].retry.error_message_regex, "ReferencedResourceNotProvisioned")
    error_message = "ReferencedResourceNotProvisioned must survive: the 409 mitigation is additive, not a replacement."
  }

  # Pinned because the provider would otherwise silently substitute its own defaults --
  # `interval_seconds` and `max_interval_seconds` are Optional+Computed with
  # `int64default.StaticInt64` of 10 and 180 (`internal/retry/schema.go` L41, L52). These
  # match, so the module is explicit about a value it agrees with rather than accidentally
  # depending on one it never chose.
  assert {
    condition     = azapi_resource.this["conn_a"].retry.interval_seconds == 10 && azapi_resource.this["conn_a"].retry.max_interval_seconds == 180
    error_message = "The retry backoff must stay 10s base / 180s cap, matching the provider defaults the module deliberately restates."
  }
}

# ---------------------------------------------------------------------------
# 🔴 THE REGRESSION THIS FILE EXISTS FOR, AND THE ONE CORRECTION TO THE ORIGINAL SPECIFICATION.
#
# The original specification used `OperationNotAllowed.*Updating`. That pattern CANNOT MATCH.
#
# azapi matches against `runtime.NewResponseError(resp).Error()`
# (`internal/clients/options.go` L166-L185), and azcore renders that multi-line: the code
# goes on its own `ERROR CODE:` line (`response_error.go` L145) and the body is then run
# through `json.Indent` (L157). `OperationNotAllowed` lands on the `ERROR CODE:` line and
# in `"code":`; `Updating` lands only in `"message":`. They never share a line, and Go's
# `.` does not cross a newline without the `s` flag.
#
# The literals below are that rendering. `regex()` is Terraform's binding of the SAME Go
# engine azapi uses, so this run is a real test of the pattern's semantics rather than a
# restatement of its text. The negative assertion is the important one: it fails if anyone
# "tidies" the `(?s)` away.
# ---------------------------------------------------------------------------
run "regex_actually_matches_a_real_arm_409" {
  command = plan

  # The literals below are azcore-shaped 409 renderings. They are inlined rather than
  # lifted into a variable because `terraform test` can only set variables the module
  # DECLARES, and neither of these is a module input.

  assert {
    condition     = anytrue([for p in azapi_resource.this["conn_a"].retry.error_message_regex : can(regex(p, "PUT https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test/expressRouteConnections/erconn-retry\n--------------------------------------------------------------------------------\nRESPONSE 409: 409 Conflict\nERROR CODE: AnotherOperationInProgress\n--------------------------------------------------------------------------------\n{\n  \"error\": {\n    \"code\": \"AnotherOperationInProgress\",\n    \"message\": \"Another operation on this or dependent resource is in progress.\"\n  }\n}\n--------------------------------------------------------------------------------\n"))])
    error_message = "No configured pattern matches a real AnotherOperationInProgress 409. The retry is inert and the race is unmitigated."
  }

  assert {
    condition     = anytrue([for p in azapi_resource.this["conn_a"].retry.error_message_regex : can(regex(p, "PUT https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-test/expressRouteConnections/erconn-retry\n--------------------------------------------------------------------------------\nRESPONSE 409: 409 Conflict\nERROR CODE: OperationNotAllowed\n--------------------------------------------------------------------------------\n{\n  \"error\": {\n    \"code\": \"OperationNotAllowed\",\n    \"message\": \"Operation 'PUT' is not allowed on resource 'erconn-retry' since it is in 'Updating' provisioningState.\"\n  }\n}\n--------------------------------------------------------------------------------\n"))])
    error_message = "No configured pattern matches a real OperationNotAllowed-while-Updating 409. This is what happens if the (?s) prefix is removed: the pattern still compiles, still looks right, and never fires."
  }

  # The proof that `(?s)` is the thing doing the work, not decoration. If this ever starts
  # passing, azcore has changed its rendering to single-line and the `(?s)` may be revisited.
  #
  # The resource name is interpolated rather than hard-coded because Terraform rejects an
  # assert whose condition is a pure constant ("must refer to at least one object from
  # elsewhere in the configuration"). It also makes the literal a closer copy of the real
  # message, which names the resource.
  assert {
    condition     = !can(regex("OperationNotAllowed.*Updating", "RESPONSE 409: 409 Conflict\nERROR CODE: OperationNotAllowed\n----\n{\n  \"error\": {\n    \"code\": \"OperationNotAllowed\",\n    \"message\": \"Operation 'PUT' is not allowed on resource '${azapi_resource.this["conn_a"].name}' since it is in 'Updating' provisioningState.\"\n  }\n}\n"))
    error_message = "The original literal pattern unexpectedly MATCHED. azcore's multi-line rendering is the premise for the (?s) prefix; if that changed, re-derive the defaults in variables.tf."
  }
}

# ---------------------------------------------------------------------------
# The documented sharp edge, pinned so it cannot be forgotten: `var.retry` is a WHOLE-LIST
# override, not a floor. A consumer who sets `error_message_regex` loses the mitigation.
# This run asserts the current behaviour so that changing it -- e.g. to union the race
# patterns back in -- is a deliberate act with a failing test attached, rather than drift.
# ---------------------------------------------------------------------------
run "consumer_override_replaces_the_list_and_drops_the_mitigation" {
  command = plan

  variables {
    retry = {
      error_message_regex = ["SomethingElseEntirely"]
    }
  }

  assert {
    condition     = azapi_resource.this["conn_a"].retry.error_message_regex == tolist(["SomethingElseEntirely"])
    error_message = "var.retry.error_message_regex must replace the default list wholesale. If this now unions in the race patterns, update the variable description in variables.tf: it documents the override as lossy."
  }

  # Backoff defaults must still apply when only the regex list is overridden.
  assert {
    condition     = azapi_resource.this["conn_a"].retry.interval_seconds == 10 && azapi_resource.this["conn_a"].retry.max_interval_seconds == 180
    error_message = "Overriding only error_message_regex must leave the backoff defaults intact."
  }
}
