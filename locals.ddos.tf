locals {
  ddos_protection_plan = local.ddos_protection_plan_enabled ? {
    location            = coalesce(var.virtual_wan_settings.ddos_protection_plan.location, local.primary_location)
    name                = coalesce(var.virtual_wan_settings.ddos_protection_plan.name, local.default_names[local.primary_region_key].ddos_protection_plan_name)
    resource_group_name = coalesce(var.virtual_wan_settings.ddos_protection_plan.resource_group_name, local.hub_virtual_networks_resource_group_names[local.primary_region_key])
    tags                = coalesce(var.virtual_wan_settings.ddos_protection_plan.tags, var.tags, {})
  } : null
  ddos_protection_plan_enabled = var.virtual_wan_settings.enabled_resources.ddos_protection_plan && local.has_regions
}
