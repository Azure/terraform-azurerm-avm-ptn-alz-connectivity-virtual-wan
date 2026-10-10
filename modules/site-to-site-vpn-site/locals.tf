locals {
  vpn_sites = var.vpn_sites != null ? var.vpn_sites : {}

  # AzAPI addresses the parent by resource ID; AzureRM took a name plus an implicit
  # subscription from the provider block. This is a provider migration in place, so the
  # module's public variable shape is preserved and the ID is reconstructed here instead:
  # the subscription comes from `virtual_wan_id`, because a VPN site must live in the same
  # subscription as the virtual WAN it attaches to. `variables.tf` validates the shape of
  # that ID, so the index below is checked rather than assumed.
  vpn_site_parent_ids = {
    for key, value in local.vpn_sites :
    key => format("/subscriptions/%s/resourceGroups/%s", split("/", value.virtual_wan_id)[2], value.resource_group_name)
  }

  # Each nested ARM object is emitted only where AzureRM's expander emitted one, because
  # `ignore_null_property` prunes null VALUES but leaves an emptied object behind, and
  # `"addressSpace": {}` is not the same request as no `addressSpace` at all.
  # - expandVpnSiteAddressSpace       returns nil for an empty set
  # - expandVpnSiteDeviceProperties   returns nil when both vendor and model are unset
  # - expandVpnSiteO365Policy         short-circuits to nil on an empty block
  # - expandVpnSiteVpnLinkBgpSettings short-circuits to nil on an empty block
  vpn_site_bodies = {
    for key, value in local.vpn_sites : key => {
      properties = merge(
        {
          virtualWan = { id = value.virtual_wan_id }
          vpnSiteLinks = [
            for link in(value.links != null ? value.links : []) : {
              name = link.name
              properties = merge(
                {
                  linkProperties = {
                    linkProviderName = try(link.provider_name, null)
                    # AzureRM's schema defaults speed_in_mbps to 0 and always sends it, so an
                    # unset value stays 0 here rather than becoming absent.
                    linkSpeedInMbps = try(link.speed_in_mbps, null) != null ? link.speed_in_mbps : 0
                  }
                  ipAddress = try(link.ip_address, null)
                  fqdn      = try(link.fqdn, null)
                },
                try(link.bgp, null) != null ? {
                  bgpProperties = {
                    asn               = link.bgp.asn
                    bgpPeeringAddress = link.bgp.peering_address
                  }
                } : {},
              )
            }
          ]
        },
        length(try(value.address_cidrs, null) != null ? value.address_cidrs : []) > 0 ? {
          addressSpace = { addressPrefixes = value.address_cidrs }
        } : {},
        try(value.device_vendor, null) != null || try(value.device_model, null) != null ? {
          deviceProperties = {
            deviceVendor = try(value.device_vendor, null)
            deviceModel  = try(value.device_model, null)
          }
        } : {},
        try(value.o365_policy, null) != null ? {
          o365Policy = {
            # AzureRM defaults each of these bools to false and always sends them.
            breakOutCategories = {
              allow    = try(value.o365_policy.traffic_category.allow_endpoint_enabled, null) != null ? value.o365_policy.traffic_category.allow_endpoint_enabled : false
              default  = try(value.o365_policy.traffic_category.default_endpoint_enabled, null) != null ? value.o365_policy.traffic_category.default_endpoint_enabled : false
              optimize = try(value.o365_policy.traffic_category.optimize_endpoint_enabled, null) != null ? value.o365_policy.traffic_category.optimize_endpoint_enabled : false
            }
          }
        } : {},
      )
    }
  }
}

locals {
  # Per-resource timeout defaults. `var.timeouts` keeps its published shape -- same name, same
  # four attributes, same types -- but its attributes no longer carry a blanket `30m`/`5m`
  # default. An attribute the consumer leaves unset now falls back to the default of the
  # AzureRM resource this module replaced, which is what the module's behaviour actually was
  # before the provider migration. A consumer who sets `var.timeouts` today is unaffected.
  #
  # Cited against terraform-provider-azurerm@5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0).
  #
  # azapi_resource.this -> azurerm_vpn_site
  #   vpn_site_resource.go L39-L44: Create 30m, Read 5m, Update 30m, Delete 30m
  timeouts = {
    create = try(var.timeouts.create, null) != null ? var.timeouts.create : "30m"
    read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
    update = try(var.timeouts.update, null) != null ? var.timeouts.update : "30m"
    delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "30m"
  }
}
