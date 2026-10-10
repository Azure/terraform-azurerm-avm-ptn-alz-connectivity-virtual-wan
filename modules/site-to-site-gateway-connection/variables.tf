variable "vpn_site_connection" {
  type = map(object({
    name               = string
    remote_vpn_site_id = string
    vpn_gateway_id     = string
    vpn_links = list(object({
      name                 = string
      egress_nat_rule_ids  = optional(list(string))
      ingress_nat_rule_ids = optional(list(string))
      # ID of the link to VPN site. Links are created in the VPN site module.
      vpn_site_link_id    = string
      bandwidth_mbps      = optional(number)
      bgp_enabled         = optional(bool)
      connection_mode     = optional(string)
      dpd_timeout_seconds = optional(number)

      ipsec_policy = optional(object({
        dh_group                 = string
        ike_encryption_algorithm = string
        ike_integrity_algorithm  = string
        encryption_algorithm     = string
        integrity_algorithm      = string
        pfs_group                = string
        sa_data_size_kb          = string
        sa_lifetime_sec          = string
      }))
      protocol                              = optional(string)
      ratelimit_enabled                     = optional(bool)
      route_weight                          = optional(number)
      shared_key                            = optional(string)
      local_azure_ip_address_enabled        = optional(bool)
      policy_based_traffic_selector_enabled = optional(bool)
      custom_bgp_addresses = optional(list(object({
        ip_address          = string
        ip_configuration_id = string
      })))
    }))
    internet_security_enabled = optional(bool)
    routing = optional(object({
      associated_route_table = string
      propagated_route_table = optional(object({
        route_table_ids = optional(list(string))
        labels          = optional(list(string))
      }))
      inbound_route_map_id  = optional(string)
      outbound_route_map_id = optional(string)
    }))
    traffic_selector_policy = optional(object({
      local_address_ranges  = list(string)
      remote_address_ranges = list(string)
    }))
  }))
  # See "Design notes -> Removed input: per-link `shared_key_version`" in `_header.md`.
  description = "S2S VPN Site Connections parameter"
}

variable "ignore_body_changes" {
  type = object({
    network_vpn_gateways_vpn_connections = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Body property paths whose changes the `azapi` provider ignores after creation, letting an out-of-band controller own those properties without producing perpetual `terraform plan` drift.

- `network_vpn_gateways_vpn_connections` - (Optional) Ignored body paths for the VPN gateway connection, in dot notation relative to the request body, for example `["properties.vpnLinkConnections"]`. Default `[]`.

While a path is ignored, configuration changes at that path are no longer sent to Azure. The value is write-only provider state, so a change only takes effect after an `apply`, and supplying a non-empty list requires Terraform 1.11 or later.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for path in var.ignore_body_changes.network_vpn_gateways_vpn_connections : length(trimspace(path)) > 0])
    error_message = "Every ignore_body_changes.network_vpn_gateways_vpn_connections entry must be a non-empty body path in dot notation, for example \"properties.vpnLinkConnections\"."
  }
}

variable "resource_types" {
  type = object({
    network_vpn_gateways_vpn_connections = optional(string, "Microsoft.Network/vpnGateways/vpnConnections@2025-07-01")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) The Azure resource type and API version used for each resource created by this module.

- `network_vpn_gateways_vpn_connections` - (Optional) The type and API version of the VPN gateway connection. Default `Microsoft.Network/vpnGateways/vpnConnections@2025-07-01`.
DESCRIPTION
  nullable    = false
}

# ---------------------------------------------------------------------------
# 🔴 THE SAME-APPLY 409 RACE.
#
# `azapi_resource.this` in this module writes `Microsoft.Network/vpnGateways/vpnConnections`
# -- a CHILD of the vpn gateway. The gateway's own writers return long before the RP is
# finished with it: a tags-only PUT at `Microsoft.Resources/tags/default` on a vpnGateway
# was measured returning immediately while the gateway sat in `provisioningState: Updating`
# for ~4m30s afterwards, dragging its `vpnConnections` and `vpnLinkConnections` into
# `Updating` with it. The activity log recorded exactly one write.
#
# So `terraform apply` can move on to this resource while the parent gateway is still busy,
# and the connection write then comes back `409 AnotherOperationInProgress` (or
# `OperationNotAllowed` citing a resource being updated). Both are transient: the retry
# below is what turns them into a wait instead of a failed apply.
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

The last two entries exist because this module writes a CHILD of a vpn gateway
(`Microsoft.Network/vpnGateways/vpnConnections`). A write to the parent gateway -- including a
tags-only change -- returns to Terraform while the RP keeps the gateway, and its connections, in
`provisioningState: Updating` for minutes afterwards. A connection write landing in that window
fails with a transient `409`. Retrying is the mitigation.

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
