module "firewalls" {
  source = "../firewall"

  diagnostic_settings = var.diagnostic_settings_azure_firewall
  enable_telemetry    = var.enable_telemetry
  firewalls = {
    for key, value in var.firewalls : key => {
      location             = module.virtual_hubs.resource_object[value.virtual_hub_key].location
      name                 = value.name
      resource_group_name  = local.virtual_hubs[value.virtual_hub_key].resource_group_name
      sku_name             = value.sku_name
      sku_tier             = value.sku_tier
      firewall_policy_id   = value.firewall_policy_id
      tags                 = value.tags
      virtual_hub_id       = module.virtual_hubs.resource_object[value.virtual_hub_key].id
      vhub_public_ip_count = value.vhub_public_ip_count
      ip_configurations    = value.ip_configurations
      zones                = value.zones
    }
  }
  # TFFR6 / TFFR7 / TFFR8 interface cascade -- register and neutrality argument
  # are in `main.express_route_gateway.tf` on `module "express_route_gateways"`.
  ignore_body_changes = var.ignore_body_changes.network_azure_firewalls
  resource_types      = var.resource_types.network_azure_firewalls
  retry               = var.retry
  timeouts            = var.timeouts
}

# The `moved` block that used to sit here was DELETED.
#
#   moved {
#     from = azurerm_firewall.fw
#     to   = module.firewalls.azurerm_firewall.fw
#   }
#
# Its `to` address stopped existing when modules/firewall migrated to azapi.
# A `moved` whose `to` is not in configuration does NOT error and does NOT
# warn -- `terraform validate` stays clean. Terraform moves the state entry to
# the new address, finds nothing declaring it, and plans to DESTROY the live
# resource. Measured (dangling `moved` check).
#
# Safe to delete: the supported upgrade floor is v0.12.0 and docs/upgrade-guide.md
# covers anything older. Anyone upgrading across this boundary needs a `removed`
# + `import` pair, not a `moved`.
