# Create a site to site vpn connection between a vpn gateway and a vpn site.

data "azapi_resource" "existing_vpn_connection" {
  for_each = {
    for key, value in local.vpn_site_connections : key => value
    if try(value.routing, null) == null
  }

  resource_id      = "${each.value.vpn_gateway_id}/vpnConnections/${each.value.name}"
  type             = var.resource_types.network_vpn_gateways_vpn_connections
  ignore_not_found = true
  response_export_values = [
    "properties.routingConfiguration",
  ]
}

resource "azapi_resource" "this" {
  for_each = local.vpn_site_connections

  name      = each.value.name
  parent_id = each.value.vpn_gateway_id
  type      = var.resource_types.network_vpn_gateways_vpn_connections
  body      = local.vpn_site_connection_bodies[each.key]
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left
  # unset is absent from the request rather than sent as an explicit JSON null. Null VALUES
  # only -- whole sub-objects are still built conditionally in `vpn_site_connection_bodies`.
  ignore_body_changes  = length(var.ignore_body_changes.network_vpn_gateways_vpn_connections) > 0 ? var.ignore_body_changes.network_vpn_gateways_vpn_connections : null
  ignore_null_property = true
  # `remote_vpn_site_id` is ForceNew on azurerm_vpn_gateway_connection, so it stays a
  # replacement trigger. `name` and `vpn_gateway_id` are the resource name and the parent
  # scope, both of which AzAPI already treats as replacement triggers natively.
  #
  # ⚠️ Not reproduced: AzureRM also marked the per-link `vpn_site_link_id` and `bgp_enabled`
  # ForceNew. Those live inside `properties.vpnLinkConnections[*]`, and the only path AzAPI
  # can address is the whole list -- which would destroy and rebuild every tunnel on the
  # gateway for an unrelated bandwidth change. Listing the list is worse than not listing it,
  # so it is omitted: ARM itself accepts both changes on a PUT.
  replace_triggers_refs = [
    "properties.remoteVpnSite.id",
  ]
  # ✅ `response_export_values` IS SET. AVM spec TFFR4 is Severity-MUST and tagged
  # Class-Pattern, so it binds this module: an AzAPI resource MUST declare the attribute,
  # "even if empty".
  #
  # `[]` is the right value: nothing downstream reads a response-only property. Consumers take
  # `.id` and `.name`, both of which AzAPI exposes natively, plus the link shape, which is
  # projected from configuration in `outputs.tf`.
  #
  # ⛔ NO `lifecycle { ignore_changes = [response_export_values] }` -- WITHDRAWN, AND IT MUST
  # NOT COME BACK. This site is "armed": `ignore_body_changes`/`ignore_null_property` leave
  # `body` free, so `skip.CanSkipExternalRequest` is false and a PUT does occur. Pinning
  # `response_export_values` here reproduces BUG 3: the pin freezes `plan.Output` to the stale
  # null-derived default projection while the writer still PUTs at adoption, so the applied
  # output disagrees with the planned one -> "Error: Provider produced inconsistent result
  # after apply" on first apply after upgrade. Do not copy this withdrawal onto a Class A
  # (fully silent) writer -- there, pinning costs nothing extra since no PUT happens, and BUG 3
  # cannot fire either way.
  #
  # `avm_azapi_response_export_values_required` fires on ABSENCE and is now satisfied. It runs
  # at `severity = "notice"` under the pinned AVM base tflint config, as do all eight enabled
  # `avm_*` rules, so a green `avm pr-check` is NOT evidence of MUST compliance.
  response_export_values = []
  retry                  = var.retry
  # Write-only. See `vpn_site_connection_shared_keys` above. Supplying a `shared_key` on any
  # link therefore requires Terraform 1.11 or later; leaving them unset does not.
  #
  # ⭐ `sensitive_body_version` is DELIBERATELY NOT SET HERE and NOT EXPOSED AS AN INPUT -- see
  # "Design notes -> `sensitive_body_version` is deliberately unset" in `_header.md`.
  sensitive_body = length(local.vpn_site_connection_shared_keys[each.key]) > 0 ? { properties = { vpnLinkConnections = local.vpn_site_connection_shared_keys[each.key] } } : null

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [local.timeouts]

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }
}

# =============================================================================
# AzureRM -> AzAPI state moves (`avm-tf-migration` SKILL.md L66-78)
#
# The provider migration is IN PLACE: same module, same `for_each`/`count`
# boundary, same keys, so every move is a whole-resource move and the consumer
# only bumps the module version. Plan with a normal refresh -- see
# `docs/upgrade-guide.md`; `-refresh=false` hits azapi#1227 and plans a replace.
# =============================================================================

moved {
  from = azurerm_vpn_gateway_connection.vpn_site_connection
  to   = azapi_resource.this
}
