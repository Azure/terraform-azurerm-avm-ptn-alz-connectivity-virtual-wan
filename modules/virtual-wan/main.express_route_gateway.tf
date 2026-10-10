module "express_route_gateways" {
  source = "../expressroute-gateway"

  expressroute_gateways = {
    for key, gw in local.expressroute_gateways : key => {
      name                          = gw.name
      resource_group_name           = module.virtual_hubs.resource_object[gw.virtual_hub_key].resource_group
      virtual_hub_id                = module.virtual_hubs.resource_object[gw.virtual_hub_key].id
      location                      = module.virtual_hubs.resource_object[gw.virtual_hub_key].location
      scale_units                   = gw.scale_units
      allow_non_virtual_wan_traffic = gw.allow_non_virtual_wan_traffic
      tags                          = gw.tags
    }
  }
  # =========================================================================
  # TFFR6 / TFFR7 / TFFR8 INTERFACE CASCADE. Register for all eight submodule
  # calls this module makes; the other seven point back here.
  #
  # WHAT THE SPECS REQUIRE. All three are Severity-MUST and all three carry
  # Class-Resource, Class-Pattern and Class-Utility, so a pattern module is in
  # scope:
  #   - TFFR6 (priority 20060) -- `resource_types` MUST be exposed, one
  #     attribute per resource, keyed by the resource type.
  #   - TFFR7 (priority 20070) -- `retry` and `timeouts` MUST be exposed.
  #   - TFFR8 (priority 20080) -- `ignore_body_changes` MUST be exposed and
  #     MUST NOT be omitted from a supported AzAPI resource.
  # A pattern module does not own the resources its submodules declare, so the
  # only way it can satisfy these for those resources is to pass the consumer's
  # values through. That is what the four arguments below do.
  #
  # 🔴 NEUTRAL AT THE DEFAULTS, AND WHY. With all four variables unset this
  # plans byte-identically to the un-plumbed configuration:
  #   - `resource_types.<slot>` and `timeouts` carry `optional(...)` with NO
  #     default, so an unset consumer sends nulls, and Terraform substitutes
  #     the RECEIVING submodule's own declared default for a null it gets from
  #     a parent. MEASURED on Terraform 1.16.2. The submodule therefore stays
  #     the single source of truth for its own API versions and timeouts,
  #     which matters because they genuinely differ -- `../virtual-hub`
  #     defaults create to `60m`, `../site-to-site-gateway` to `90m`.
  #   - `ignore_body_changes.<slot>` defaults to `[]` per key, which is what
  #     each submodule already defaults to.
  #   - `retry` is `var.retry`, NOT `local.retry`. `local.retry` exists
  #     precisely so this distinction can be made: it carries THIS module's own
  #     defaults for THIS module's own resources, while `var.retry` stays
  #     all-null for the cascade. Passing `local.retry` would have narrowed
  #     `../expressroute-gateway-connection` and
  #     `../site-to-site-gateway-connection` from three retry regexes to one.
  #     See `locals.retry.tf`.
  #
  # An attribute the consumer DOES set overrides here and in every submodule
  # alike, which is the point of the cascade.
  # =========================================================================
  ignore_body_changes = var.ignore_body_changes.network_express_route_gateways
  resource_types      = var.resource_types.network_express_route_gateways
  retry               = var.retry
  timeouts            = var.timeouts
}

# The `moved` block that used to sit here was DELETED.
#
#   moved {
#     from = azurerm_express_route_gateway.express_route_gateway
#     to   = module.express_route_gateways.azurerm_express_route_gateway.express_route_gateway
#   }
#
# Its `to` address stopped existing when modules/expressroute-gateway migrated to azapi.
# A `moved` whose `to` is not in configuration does NOT error and does NOT
# warn -- `terraform validate` stays clean. Terraform moves the state entry to
# the new address, finds nothing declaring it, and plans to DESTROY the live
# resource. Measured (dangling `moved` check).
#
# Safe to delete: the supported upgrade floor is v0.12.0 and docs/upgrade-guide.md
# covers anything older. Anyone upgrading across this boundary needs a `removed`
# + `import` pair, not a `moved`.

# Create the Express Route Connection
module "er_connections" {
  source = "../expressroute-gateway-connection"

  er_circuit_connections = {
    for key, conn in local.er_circuit_connections : key => {
      name                                 = conn.name
      express_route_gateway_id             = module.express_route_gateways.resource_object[conn.express_route_gateway_key].id
      express_route_circuit_peering_id     = conn.express_route_circuit_peering_id
      authorization_key                    = try(conn.authorization_key, null)
      enable_internet_security             = try(conn.enable_internet_security, null)
      express_route_gateway_bypass_enabled = try(conn.express_route_gateway_bypass_enabled, null)
      routing                              = try(conn.routing, null)
      routing_weight                       = try(conn.routing_weight, null)
    }
  }
  # TFFR6 / TFFR7 / TFFR8 interface cascade -- register and neutrality argument
  # are in `main.express_route_gateway.tf` on `module "express_route_gateways"`.
  ignore_body_changes = var.ignore_body_changes.network_express_route_gateways_express_route_connections
  resource_types      = var.resource_types.network_express_route_gateways_express_route_connections
  retry               = var.retry
  timeouts            = var.timeouts
}

# 🔴 A `moved` BLOCK WAS DELETED HERE, and deleting it was the SAFE act.
#
#   moved {
#     from = azurerm_express_route_connection.er_connection
#     to   = module.er_connections.azurerm_express_route_connection.er_connection
#   }
#
# Its `to` address NO LONGER EXISTS: `modules/expressroute-gateway-connection` is now `azapi_resource.this`.
#
# A `moved` block whose `to` is not in configuration does NOT error and does NOT
# warn. `terraform validate` is clean. Terraform moves the state entry to the new
# address, finds nothing declaring it, and plans to DESTROY the live resource:
#
#     # <addr> will be destroyed
#     # (because <old> was moved to <new>, which is not in configuration)
#     Plan: 1 to add, 0 to change, 1 to destroy.
#
# MEASURED, the dangling-`moved` measurement, with a
# hand-written state and `-refresh=false` -- no Azure involved.
#
# Deleting it is safe because the module's supported floor is v0.12.0 and the
# upgrade guide covers anything older. A consumer still on a pre-v0.12.0 state
# follows the guide, not this block.
