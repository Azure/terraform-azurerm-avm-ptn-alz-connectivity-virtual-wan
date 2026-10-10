# BGP connection on the Virtual Hub built-in router. Used to peer Network Virtual
# Appliances (NVAs) deployed in spoke virtual networks directly with the vHub.

resource "azapi_resource" "bgp_connection" {
  for_each = var.bgp_connections

  name                = each.value.name
  parent_id           = module.virtual_hubs.resource_object[each.value.virtual_hub_key].id
  type                = var.resource_types.network_virtual_hubs_bgp_connections
  body                = local.bgp_connection_bodies[each.key]
  ignore_body_changes = length(var.ignore_body_changes.network_virtual_hubs_bgp_connections) > 0 ? var.ignore_body_changes.network_virtual_hubs_bgp_connections : null
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left
  # unset is absent from the request rather than sent as an explicit JSON null.
  ignore_null_property = true
  # `azurerm_virtual_hub_bgp_connection` registers Create, Read and Delete and NO Update,
  # and every schema attribute is ForceNew. `name` and `virtual_hub_id` (the parent scope)
  # are replacement triggers natively in AzAPI, which leaves these three.
  replace_triggers_refs = [
    "properties.hubVirtualNetworkConnection.id",
    "properties.peerAsn",
    "properties.peerIp",
  ]
  # ✅ `response_export_values` IS SET, per AVM spec TFFR4 (Severity-MUST, Class-Pattern):
  # an AzAPI resource MUST declare the attribute, "even if empty". `[]` is the right value --
  # nothing reads this resource's `.output`.
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
  response_export_values = []
  retry                  = local.retry

  timeouts {
    create = local.timeouts.network_virtual_hubs_bgp_connections.create
    delete = local.timeouts.network_virtual_hubs_bgp_connections.delete
    read   = local.timeouts.network_virtual_hubs_bgp_connections.read
    update = local.timeouts.network_virtual_hubs_bgp_connections.update
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
  from = azurerm_virtual_hub_bgp_connection.bgp_connection
  to   = azapi_resource.bgp_connection
}
