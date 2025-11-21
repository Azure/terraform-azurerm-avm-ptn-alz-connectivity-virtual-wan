locals {
  private_dns_zones_enabled = { for key, value in var.virtual_hubs : key => value.enabled_resources.private_dns_zones }
}

locals {
  private_dns_zones = { for key, value in var.virtual_hubs : key => {
    location  = value.location
    parent_id = coalesce(value.private_dns_zones.parent_id, value.hub.parent_id, value.default_parent_id)
    private_link_private_dns_zones_regex_filter = coalesce(value.private_dns_zones.private_link_private_dns_zones_regex_filter, {
      enabled = key != local.primary_region_key
    })
    private_link_excluded_zones                                = value.private_dns_zones.private_link_excluded_zones
    private_link_private_dns_zones                             = value.private_dns_zones.private_link_private_dns_zones
    private_link_private_dns_zones_additional                  = value.private_dns_zones.private_link_private_dns_zones_additional
    virtual_network_link_default_virtual_networks              = coalesce(value.private_dns_zones.virtual_network_link_default_virtual_networks, local.private_dns_zones_virtual_network_link_default_virtual_networks)
    virtual_network_link_additional_virtual_networks           = value.private_dns_zones.virtual_network_link_additional_virtual_networks
    virtual_network_link_by_zone_and_virtual_network           = value.private_dns_zones.virtual_network_link_by_zone_and_virtual_network
    virtual_network_link_overrides_by_virtual_network          = value.private_dns_zones.virtual_network_link_overrides_by_virtual_network
    virtual_network_link_overrides_by_zone                     = value.private_dns_zones.virtual_network_link_overrides_by_zone
    virtual_network_link_overrides_by_zone_and_virtual_network = value.private_dns_zones.virtual_network_link_overrides_by_zone_and_virtual_network
    virtual_network_link_name_template                         = value.private_dns_zones.virtual_network_link_name_template
    virtual_network_link_resolution_policy_default             = value.private_dns_zones.virtual_network_link_resolution_policy_default
    tags                                                       = coalesce(value.private_dns_zones.tags, var.tags, {})
  } if local.private_dns_zones_enabled[key] }
  private_dns_zones_auto_registration = { for key, value in var.virtual_hubs : key => {
    location    = value.location
    domain_name = coalesce(value.private_dns_zones.auto_registration_zone_name, "${value.location}.azure.local")
    parent_id   = coalesce(value.private_dns_zones.auto_registration_zone_parent_id, value.private_dns_zones.parent_id, value.hub.parent_id, value.default_parent_id)
    virtual_network_links = {
      auto_registration = {
        name                 = "vnet-link-${key}-auto-registration"
        virtual_network_id   = module.virtual_network_side_car[key].resource_id
        registration_enabled = true
        tags                 = var.tags
      }
    }
  } if local.private_dns_zones_enabled[key] && value.private_dns_zones.auto_registration_zone_enabled }
  private_dns_zones_virtual_network_link_default_virtual_networks = {
    for key, value in module.virtual_network_side_car : key => {
      virtual_network_resource_id                 = value.resource_id
      virtual_network_link_name_template_override = var.virtual_hubs[key].private_dns_zones.virtual_network_link_name_template
      resolution_policy                           = var.virtual_hubs[key].private_dns_zones.virtual_network_link_resolution_policy_default
    }
  }
}
