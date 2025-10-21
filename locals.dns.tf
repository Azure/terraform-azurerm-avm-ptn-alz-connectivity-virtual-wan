locals {
  private_dns_zones_enabled = { for key, value in var.virtual_hubs : key => value.enabled_resources.private_dns_zones }
}

locals {
  private_dns_zones = { for key, value in var.virtual_hubs : key => {
    location            = value.location
    resource_group_name = coalesce(value.private_dns_zones.resource_group_name, local.hub_virtual_networks_resource_group_names[key])
    private_link_private_dns_zones_regex_filter = value.private_dns_zones.private_link_private_dns_zones_regex_filter != null ? value.private_dns_zones.private_link_private_dns_zones_regex_filter : {
      enabled = key != local.primary_region_key
    }
    private_dns_settings = value.private_dns_zones
    tags                 = coalesce(value.private_dns_zones.tags, var.tags, {})
  } if local.private_dns_zones_enabled[key] }
  private_dns_zones_auto_registration = { for key, value in var.virtual_hubs : key => {
    location            = value.location
    domain_name         = coalesce(value.private_dns_zones.auto_registration_zone_name, "${value.location}.azure.local")
    resource_group_name = coalesce(value.private_dns_zones.auto_registration_zone_resource_group_name, local.private_dns_zones[key].resource_group_name)
    virtual_network_links = {
      auto_registration = {
        vnetlinkname     = "vnet-link-${key}-auto-registration"
        vnetid           = module.side_car_virtual_network[key].resource_id
        autoregistration = true
        tags             = var.tags
      }
    }
  } if local.private_dns_zones_enabled[key] && value.private_dns_zones.auto_registration_zone_enabled }
  private_dns_zones_virtual_network_links = {
    for key, value in module.side_car_virtual_network : key => {
      vnet_resource_id                            = value.resource_id
      virtual_network_link_name_template_override = var.virtual_hubs[key].private_dns_zones.private_dns_zone_network_link_name_template
    }
  }
}
