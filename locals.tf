locals {
  has_regions                               = length(var.virtual_hubs) > 0
  hub_virtual_networks_resource_group_names = { for key, value in var.virtual_hubs : key => provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", coalesce(value.default_parent_id, value.hub.parent_id)).resource_group_name }
  primary_location                          = local.has_regions ? var.virtual_hubs[local.primary_region_key].location : null
  primary_region_key                        = local.has_regions ? keys(var.virtual_hubs)[0] : null
  virtual_hubs = { for virtual_hub_key, virtual_hub_value in var.virtual_hubs : virtual_hub_key => merge(virtual_hub_value.hub, {
    name                = coalesce(virtual_hub_value.hub.name, local.default_names[virtual_hub_key].virtual_hub_name)
    location            = virtual_hub_value.location
    resource_group_name = virtual_hub_value.hub.parent_id != null ? provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", virtual_hub_value.hub.parent_id).resource_group_name : local.hub_virtual_networks_resource_group_names[virtual_hub_key]
    address_prefix      = coalesce(virtual_hub_value.hub.address_prefix, local.virtual_network_default_ip_prefixes[virtual_hub_key]["virtual_hub"])
    tags                = coalesce(virtual_hub_value.hub.tags, var.tags, {})
  }) }
  virtual_wan = local.has_regions ? {
    name                              = coalesce(var.virtual_wan_settings.virtual_wan.name, local.default_names[local.primary_region_key].virtual_wan_name)
    location                          = coalesce(var.virtual_wan_settings.virtual_wan.location, local.primary_location)
    resource_group_name               = coalesce(var.virtual_wan_settings.virtual_wan.resource_group_name, local.hub_virtual_networks_resource_group_names[local.primary_region_key])
    type                              = var.virtual_wan_settings.virtual_wan.type
    allow_branch_to_branch_traffic    = var.virtual_wan_settings.virtual_wan.allow_branch_to_branch_traffic
    disable_vpn_encryption            = var.virtual_wan_settings.virtual_wan.disable_vpn_encryption
    office365_local_breakout_category = var.virtual_wan_settings.virtual_wan.office365_local_breakout_category
    tags                              = coalesce(var.virtual_wan_settings.virtual_wan.tags, var.tags, {})
  } : null
}
