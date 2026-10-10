# Virtual network connection from virtual hub
# Create a hub connection
module "virtual_network_connections" {
  source = "../virtual-network-connection"

  # TFFR6 / TFFR7 / TFFR8 interface cascade -- register and neutrality argument
  # are in `main.express_route_gateway.tf` on `module "express_route_gateways"`.
  ignore_body_changes = var.ignore_body_changes.network_virtual_hubs_hub_virtual_network_connections
  resource_types      = var.resource_types.network_virtual_hubs_hub_virtual_network_connections
  retry               = var.retry
  timeouts            = var.timeouts
  virtual_network_connections = {
    for key, vnet_conn in var.virtual_network_connections : key => {
      name                      = vnet_conn.name
      virtual_hub_id            = module.virtual_hubs.resource_id[vnet_conn.virtual_hub_key]
      remote_virtual_network_id = vnet_conn.remote_virtual_network_id
      internet_security_enabled = lookup(vnet_conn, "internet_security_enabled", false)
      routing = lookup(vnet_conn, "routing", null) == null ? null : {
        associated_route_table_id = vnet_conn.routing.associated_route_table_id
        propagated_route_table = lookup(vnet_conn.routing, "propagated_route_table", null) == null ? null : {
          route_table_ids = lookup(vnet_conn.routing.propagated_route_table, "route_table_ids", [])
          labels          = lookup(vnet_conn.routing.propagated_route_table, "labels", [])
        }
        static_vnet_route = lookup(vnet_conn.routing, "static_vnet_route", null) == null ? null : {
          name                = lookup(vnet_conn.routing.static_vnet_route, "name", null)
          address_prefixes    = lookup(vnet_conn.routing.static_vnet_route, "address_prefixes", [])
          next_hop_ip_address = lookup(vnet_conn.routing.static_vnet_route, "next_hop_ip_address", null)
        }
      }
    }
  }
}

# Routing intent
resource "azapi_resource" "routing_intent" {
  for_each = local.routing_intents != null ? local.routing_intents : {}

  name      = each.value.name
  parent_id = module.virtual_hubs.resource_object[each.value.virtual_hub_key].id
  type      = var.resource_types.network_virtual_hubs_routing_intent
  # `expandRoutingPolicy` allocates an empty slice and returns a pointer to it even for
  # empty input, so `routingPolicies: []` was part of every request AzureRM sent and stays
  # part of this one. `local.routing_intents` already collapses a null `routing_policies`
  # to `[]`. Verified against virtual_hub_routing_intent_resource.go at v4.81.0.
  body = {
    properties = {
      routingPolicies = [
        for routing_policy in each.value.routing_policies : {
          destinations = routing_policy.destinations
          name         = routing_policy.name
          nextHop      = module.firewalls.resource_object[routing_policy.next_hop_firewall_key].id
        }
      ]
    }
  }
  ignore_body_changes = length(var.ignore_body_changes.network_virtual_hubs_routing_intent) > 0 ? var.ignore_body_changes.network_virtual_hubs_routing_intent : null
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left
  # unset is absent from the request rather than sent as an explicit JSON null.
  ignore_null_property = true
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
    create = local.timeouts.network_virtual_hubs_routing_intent.create
    delete = local.timeouts.network_virtual_hubs_routing_intent.delete
    read   = local.timeouts.network_virtual_hubs_routing_intent.read
    update = local.timeouts.network_virtual_hubs_routing_intent.update
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
  from = azurerm_virtual_hub_routing_intent.routing_intent
  to   = azapi_resource.routing_intent
}
