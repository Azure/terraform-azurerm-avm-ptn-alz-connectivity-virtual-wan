locals {
  private_dns_zones_enabled = { for key, value in var.virtual_hubs : key => try(value.private_dns_zones.enabled, try(value.private_dns_zones, null) != null) }
}

locals {
  private_dns_zones = { for key, value in var.virtual_hubs : key => merge({
    location            = value.hub.location
    resource_group_name = value.hub.resource_group
  }, value.private_dns_zones.dns_zones) if local.private_dns_zones_enabled[key] }
  private_dns_zones_auto_registration = { for key, value in var.virtual_hubs : key => {
    location            = value.hub.location
    domain_name         = value.private_dns_zones.auto_registration_zone_name
    resource_group_name = try(value.auto_registration_zone_resource_group_name, local.private_dns_zones[key].resource_group_name)
    virtual_network_links = local.side_car_virtual_networks_enabled[key] ? {
      auto_registration = {
        vnetlinkname     = "vnet-link-${key}-auto-registration"
        vnetid           = module.virtual_network_side_car[key].resource_id
        autoregistration = true
        tags             = var.tags
      }
    } : {}
  } if local.private_dns_zones_enabled[key] && try(value.private_dns_zones.auto_registration_zone_enabled, false) }
  private_dns_zones_virtual_network_links = {
    for key, value in module.virtual_network_side_car : key => {
      vnet_resource_id                            = value.resource_id
      virtual_network_link_name_template_override = try(var.virtual_hubs[key].private_dns_zones.dns_zones.private_dns_zone_network_link_name_template, null)
    }
  }
}
