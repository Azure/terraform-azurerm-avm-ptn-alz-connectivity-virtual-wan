variable "er_circuit_connections" {
  type = map(object({
    name                                 = string
    express_route_gateway_id             = string
    express_route_circuit_peering_id     = string
    authorization_key                    = optional(string)
    enable_internet_security             = optional(bool)
    express_route_gateway_bypass_enabled = optional(bool)
    routing = optional(object({
      associated_route_table_id = string
      propagated_route_table = optional(object({
        route_table_ids = optional(list(string))
        labels          = optional(list(string))
      }))
      inbound_route_map_id  = optional(string)
      outbound_route_map_id = optional(string)
    }))
    routing_weight = optional(number)
  }))
  default     = {}
  description = <<DESCRIPTION
Map of objects for ExpressRoute Circuit connections to connect to the Virtual WAN ExpressRoute Gateways.

The key is deliberately arbitrary to avoid issues with known after apply values. The value is an object, of which there can be multiple in the map:

- `name`: Name for the ExpressRoute Circuit connection.
- `express_route_gateway_key`: The arbitrary key specified in the map of objects variable called `expressroute_gateways` for the object specifying the ExpressRoute Gateway you wish to connect this circuit to.
- `express_route_circuit_peering_id`: The Resource ID of the ExpressRoute Circuit Peering to connect to.
- `authorization_key`: Optional authorization key for the connection.
- `enable_internet_security`: Optional boolean to enable internet security for the connection, e.g. allow `0.0.0.0/0` route to be propagated to this connection. See: https://learn.microsoft.com/azure/virtual-wan/virtual-wan-expressroute-portal#to-advertise-default-route-00000-to-endpoints
- `express_route_gateway_bypass_enabled`: Optional boolean to enable bypass for the ExpressRoute Gateway, a.k.a. Fast Path.
- `routing`: Optional routing configuration object for the connection, which includes:
  - `associated_route_table_id`: The resource ID of the Virtual Hub Route Table you wish to associate with this connection.
  - `propagated_route_table`: Optional configuration objection of propagated route table configuration, which includes:
    - `route_table_ids`: Optional list of resource IDs of the Virtual Hub Route Tables you wish to propagate this connection to. ()
    - `labels`: Optional list of labels you wish to propagate this connection to.
  - `inbound_route_map_id`: Optional resource ID of the Virtual Hub inbound route map.
  - `outbound_route_map_id`: Optional resource ID of the Virtual Hub outbound route map.
- `routing_weight`: Optional routing weight for the connection. Values between `0` and `32000` are allowed.

> Note: There can be multiple objects in this map, one for each ExpressRoute Circuit connection to the Virtual WAN ExpressRoute Gateway you wish to connect together.
  
  DESCRIPTION
}

variable "ignore_body_changes" {
  type = object({
    network_express_route_gateways_express_route_connections = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Body property paths whose changes the `azapi` provider ignores after creation, letting an out-of-band controller own those properties without producing perpetual `terraform plan` drift.

- `network_express_route_gateways_express_route_connections` - (Optional) Ignored body paths for the ExpressRoute connection, in dot notation relative to the request body, for example `["properties.routingConfiguration"]`. Default `[]`.

While a path is ignored, configuration changes at that path are no longer sent to Azure. The value is write-only provider state, so a change only takes effect after an `apply`, and supplying a non-empty list requires Terraform 1.11 or later.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for path in var.ignore_body_changes.network_express_route_gateways_express_route_connections : length(trimspace(path)) > 0])
    error_message = "Every ignore_body_changes.network_express_route_gateways_express_route_connections entry must be a non-empty body path in dot notation, for example \"properties.routingConfiguration\"."
  }
}

variable "resource_types" {
  type = object({
    network_express_route_gateways_express_route_connections = optional(string, "Microsoft.Network/expressRouteGateways/expressRouteConnections@2025-07-01")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) The Azure resource type and API version used for each resource created by this module.

- `network_express_route_gateways_express_route_connections` - (Optional) The type and API version of the ExpressRoute connection. Default `Microsoft.Network/expressRouteGateways/expressRouteConnections@2025-07-01`.
DESCRIPTION
  nullable    = false
}

# ---------------------------------------------------------------------------
# 🔴 THE SAME-APPLY 409 RACE.
#
# `azapi_resource.this` in this module writes
# `Microsoft.Network/expressRouteGateways/expressRouteConnections` -- a CHILD of the
# ExpressRoute gateway. The gateway's own writers return long before the RP is finished with
# it. The effect was measured on the vpn gateway side of the same pattern: a tags-only PUT at
# `Microsoft.Resources/tags/default` returned immediately while the gateway stayed in
# `provisioningState: Updating` for ~4m30s, carrying its child connections with it, and the
# activity log recorded exactly one write.
#
# `modules/expressroute-gateway` uses the same two-writer shape (`azapi_resource.this` then
# `azapi_update_resource.this`), so a create and a merge PUT hit the same gateway inside one
# apply before this module's connection write is attempted. A connection write landing in
# that window comes back `409 AnotherOperationInProgress`, or `OperationNotAllowed` citing a
# resource being updated. Both are transient; the retry below turns them into a wait.
#
# The two regexes are matched against the ERROR MESSAGE, not a code field
# (`internal/retry/schema.go` L21-L31, azapi v2.12.0). What azapi actually matches is
# `runtime.NewResponseError(resp).Error()` (`internal/clients/options.go` L166-L185), and
# azcore renders that as a MULTI-LINE block -- `ERROR CODE: <code>` on its own line
# (`vendor/.../azcore/internal/exported/response_error.go` L145) and then the response body
# run through `json.Indent` (L157). The ARM error CODE is therefore in the matched string,
# which is why the bare `AnotherOperationInProgress` works.
#
# 🔴 `(?s)` IS LOAD-BEARING AND WAS NOT IN THE ORIGINAL SPECIFICATION. Go's `regexp` leaves `.`
# NOT matching `\n` by default. In the pretty-printed block above, `OperationNotAllowed`
# appears on the `ERROR CODE:` line and in `"code":`, while `Updating` appears only in the
# `"message":` line -- never the same line. So the original literal
# `OperationNotAllowed.*Updating` CANNOT MATCH a real ARM 409; verified against Terraform's
# own (Go) regex engine, which returned false for the bare pattern and true for this one.
# `(?s)` makes `.` span the newlines and is what makes the second regex do anything at all.
# Dropping it silently disarms half this mitigation.
#
# ⚠️ These are DEFAULTS, not floors. A consumer who sets `var.retry.error_message_regex`
# replaces this list wholesale and loses the mitigation; the module does not union them back
# in. That is deliberate -- `var.retry` has always been a full override -- but it means the
# guarantee is "safe by default", not "safe always".
#
# ⚠️ `retry` carries `skip_on:"update"` (`internal/services/azapi_resource.go` L78), so
# editing this list on an ALREADY-APPLIED resource is state-only: `CanSkipExternalRequest`
# excludes the field from the plan-vs-state diff and the provider returns without an ARM
# call (`azapi_resource.go` L826-L830). The new value still lands in state and is live for
# the next real write, so this is a no-op apply, not a lost setting.
# ---------------------------------------------------------------------------
variable "retry" {
  type = object({
    error_message_regex = optional(list(string), [
      "ReferencedResourceNotProvisioned",
      "AnotherOperationInProgress",
      "(?s)OperationNotAllowed.*Updating",
    ])
    interval_seconds     = optional(number, 10)
    max_interval_seconds = optional(number, 180)
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Retry configuration for the resource operations.

`error_message_regex` is matched against the ARM error MESSAGE. It defaults to
`["ReferencedResourceNotProvisioned", "AnotherOperationInProgress", "(?s)OperationNotAllowed.*Updating"]`.

The last two entries exist because this module writes a CHILD of an ExpressRoute gateway
(`Microsoft.Network/expressRouteGateways/expressRouteConnections`). A write to the parent gateway --
including a tags-only change -- returns to Terraform while the RP keeps the gateway, and its
connections, in `provisioningState: Updating` for minutes afterwards. A connection write landing in
that window fails with a transient `409`. Retrying is the mitigation.

The `(?s)` prefix is required, not stylistic: the provider matches against a multi-line rendering of
the error in which the code and the `Updating` state never share a line, and Go's `.` does not cross
a newline without it.

Setting this attribute REPLACES the whole list rather than adding to it, so an override that drops
those entries also drops the mitigation.
DESCRIPTION
}

variable "timeouts" {
  type = object({
    create = optional(string)
    read   = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Timeouts for the resource operations.

Any attribute left unset falls back, per resource, to the timeout default of the `azurerm` resource this module replaced, rather than to a single blanket value. The fallbacks and their source lines are in `local.timeouts` in `main.tf`. See "Design notes -> Per-resource timeout defaults" in `_header.md`.
DESCRIPTION
}
