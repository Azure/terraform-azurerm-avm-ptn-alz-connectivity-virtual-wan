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
  ignore_body_changes = var.ignore_body_changes.network_azure_firewalls
  resource_types      = var.resource_types.network_azure_firewalls
  retry               = var.retry
  timeouts            = var.timeouts
}

moved {
  from = azurerm_firewall.fw
  to   = module.firewalls.azurerm_firewall.fw
}
