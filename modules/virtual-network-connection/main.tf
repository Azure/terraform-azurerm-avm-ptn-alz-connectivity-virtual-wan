data "azapi_resource_list" "virtual_network_connections" {
  for_each = local.virtual_network_connections

  parent_id              = each.value.virtual_hub_id
  type                   = var.resource_types.network_virtual_hubs_hub_virtual_network_connections
  response_export_values = ["value"]
  retry                  = var.retry
}

resource "azapi_resource" "this" {
  for_each = local.virtual_network_connections

  name      = each.value.name
  parent_id = each.value.virtual_hub_id
  type      = var.resource_types.network_virtual_hubs_hub_virtual_network_connections
  body      = local.virtual_network_connection_bodies[each.key]
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left
  # unset is absent from the request rather than sent as an explicit JSON null. Null
  # VALUES only -- whole sub-objects are still built conditionally above.
  ignore_body_changes  = length(var.ignore_body_changes.network_virtual_hubs_hub_virtual_network_connections) > 0 ? var.ignore_body_changes.network_virtual_hubs_hub_virtual_network_connections : null
  ignore_null_property = true
  # `remote_virtual_network_id` is ForceNew on azurerm_virtual_hub_connection; a hub
  # connection cannot be repointed at a different VNet in place. `virtual_hub_id` is the
  # parent scope, which AzAPI already treats as a replacement trigger.
  replace_triggers_refs = [
    "properties.remoteVirtualNetwork.id",
  ]
  # ✅ `response_export_values` IS SET. AVM spec TFFR4 is Severity-MUST and tagged
  # Class-Pattern, so it binds this module: an AzAPI resource MUST declare the attribute,
  # "even if empty".
  #
  # `[]` is the right value: nothing downstream reads a response-only property. Consumers
  # take `.id` and `.name`, both of which AzAPI exposes natively, and the computed-output rule keeps a
  # computed `.output` out of a module output.
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
  # `avm_azapi_response_export_values_required` fires on ABSENCE and is now satisfied. It
  # runs at `severity = "notice"` under the pinned AVM base tflint config, as do all eight
  # enabled `avm_*` rules, so a green `avm pr-check` is NOT evidence of MUST compliance.
  response_export_values = []
  retry                  = var.retry

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
  from = azurerm_virtual_hub_connection.hub_connection
  to   = azapi_resource.this
}
