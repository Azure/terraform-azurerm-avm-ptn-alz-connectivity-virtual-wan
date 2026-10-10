module "vpn_gateway" {
  source = "../site-to-site-gateway"

  # TFFR6 / TFFR7 / TFFR8 interface cascade -- register and neutrality argument
  # are in `main.express_route_gateway.tf` on `module "express_route_gateways"`.
  ignore_body_changes = var.ignore_body_changes.network_vpn_gateways
  resource_types      = var.resource_types.network_vpn_gateways
  retry               = var.retry
  timeouts            = var.timeouts
  vpn_gateways = {
    for key, value in local.vpn_gateways : key => {
      name                                  = value.name
      resource_group_name                   = module.virtual_hubs.resource_object[value.virtual_hub_key].resource_group
      location                              = module.virtual_hubs.resource_object[value.virtual_hub_key].location
      virtual_hub_id                        = module.virtual_hubs.resource_object[value.virtual_hub_key].id
      bgp_route_translation_for_nat_enabled = value.bgp_route_translation_for_nat_enabled
      scale_unit                            = value.scale_unit
      routing_preference                    = value.routing_preference
      bgp_settings                          = value.bgp_settings
      tags                                  = value.tags
    }
  }
}

# The `moved` block that used to sit here was DELETED.
#
#   moved {
#     from = azurerm_vpn_gateway.vpn_gateway
#     to   = module.vpn_gateway.azurerm_vpn_gateway.vpn_gateway
#   }
#
# Its `to` address stopped existing when modules/site-to-site-gateway migrated to azapi.
# A `moved` whose `to` is not in configuration does NOT error and does NOT
# warn -- `terraform validate` stays clean. Terraform moves the state entry to
# the new address, finds nothing declaring it, and plans to DESTROY the live
# resource. Measured (dangling `moved` check).
#
# Safe to delete: the supported upgrade floor is v0.12.0 and docs/upgrade-guide.md
# covers anything older. Anyone upgrading across this boundary needs a `removed`
# + `import` pair, not a `moved`.
