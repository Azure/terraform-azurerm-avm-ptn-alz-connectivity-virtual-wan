# Create a vpn site. Sites represent the Physical locations (On-Premises) you wish to connect.

resource "azapi_resource" "this" {
  for_each = local.vpn_sites

  location  = each.value.location
  name      = each.value.name
  parent_id = local.vpn_site_parent_ids[each.key]
  type      = var.resource_types.network_vpn_sites
  body      = local.vpn_site_bodies[each.key]
  # Reproduces AzureRM's nil-pointer/omitempty serialisation: an optional the consumer
  # left unset is absent from the request rather than sent as an explicit JSON null.
  # Note this prunes null VALUES only -- see the `vpn_site_bodies` comment above.
  ignore_body_changes  = length(var.ignore_body_changes.network_vpn_sites) > 0 ? var.ignore_body_changes.network_vpn_sites : null
  ignore_null_property = true
  # `virtual_wan_id` is ForceNew on azurerm_vpn_site; keeping it a replacement trigger
  # preserves that behaviour. `name` is handled natively by AzAPI and must not be listed.
  replace_triggers_refs = [
    "properties.virtualWan.id",
  ]
  # ✅ `response_export_values` IS SET, AND IT IS `[]`. AVM spec TFFR4 is Severity-MUST and
  # tagged Class-Pattern, so it binds this module: an AzAPI resource MUST declare the
  # attribute, "even if empty". See `docs/upgrade-guide.md`.
  #
  # WHY `[]` AND NOT `["properties.vpnSiteLinks"]`. It used to export the site links, because
  # the parent module indexes links positionally off `resource_object` and the per-link IDs
  # ARM assigns had to come back out of the response. That stopped being true at 6b4764c:
  # `outputs.tf` now CONSTRUCTS each link ID from `azapi_resource.this[key].id`, precisely so
  # it stays known at plan time. Nothing in this repository reads `.output` any
  # more -- verified repo-wide; the only remaining hits are under `.terraform/modules/`.
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
  # tflint-ignore: avm_azapi_resource_tags_required // the rule wants exactly `tags = var.tags`. These are PER-INSTANCE tags carried on a collection variable, which is the v0.17.2 public API; forcing a single module-wide `var.tags` is a BREAKING interface change. Tracked for the next major.
  tags = try(each.value.tags, {})

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
  from = azurerm_vpn_site.vpn_site
  to   = azapi_resource.this
}
