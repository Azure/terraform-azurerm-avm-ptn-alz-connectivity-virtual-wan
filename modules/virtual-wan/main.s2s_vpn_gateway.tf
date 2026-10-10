# Create a vpn site. Sites represent the Physical locations (On-Premises) you wish to connect.
module "vpn_site" {
  source = "../site-to-site-vpn-site"

  vpn_sites = {
    for key, value in local.vpn_sites : key => {
      name                = value.name
      resource_group_name = module.virtual_hubs.resource_object[value.virtual_hub_key].resource_group
      location            = module.virtual_hubs.resource_object[value.virtual_hub_key].location
      virtual_wan_id      = local.effective_virtual_wan_id
      address_cidrs       = value.address_cidrs
      device_vendor       = value.device_vendor
      device_model        = value.device_model
      links               = value.links
      o365_policy         = value.o365_policy
      tags                = value.tags
    }
  }
  # TFFR6 / TFFR7 / TFFR8 interface cascade -- register and neutrality argument
  # are in `main.express_route_gateway.tf` on `module "express_route_gateways"`.
  ignore_body_changes = var.ignore_body_changes.network_vpn_sites
  resource_types      = var.resource_types.network_vpn_sites
  retry               = var.retry
  timeouts            = var.timeouts
}

# 🔴 A `moved` BLOCK WAS DELETED HERE, and deleting it was the SAFE act.
#
#   moved {
#     from = azurerm_vpn_site.vpn_site
#     to   = module.vpn_site.azurerm_vpn_site.vpn_site
#   }
#
# Its `to` address NO LONGER EXISTS: `modules/site-to-site-vpn-site` is now `azapi_resource.this`.
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

# Create a site to site vpn connection between a vpn gateway and a vpn site.
module "vpn_site_connection" {
  source = "../site-to-site-gateway-connection"

  vpn_site_connection = {
    for key, conn in local.vpn_site_connections : key => {
      name                      = conn.name
      remote_vpn_site_id        = module.vpn_site.resource_object[conn.remote_vpn_site_key].id
      vpn_gateway_id            = module.vpn_gateway.resource_object[conn.vpn_gateway_key].id
      internet_security_enabled = try(conn.internet_security_enabled, null)
      vpn_links = [
        for link in conn.vpn_links : {
          name                                  = link.name
          vpn_site_link_id                      = module.vpn_site.resource_object[link.vpn_site_key].links[link.vpn_site_link_number].id
          bandwidth_mbps                        = try(link.bandwidth_mbps, null)
          bgp_enabled                           = try(link.bgp_enabled, null)
          connection_mode                       = try(link.connection_mode, null)
          dpd_timeout_seconds                   = try(link.dpd_timeout_seconds, null)
          egress_nat_rule_ids                   = try(link.egress_nat_rule_ids, null)
          ingress_nat_rule_ids                  = try(link.ingress_nat_rule_ids, null)
          ipsec_policy                          = try(link.ipsec_policy, null)
          protocol                              = try(link.protocol, null)
          ratelimit_enabled                     = try(link.ratelimit_enabled, null)
          route_weight                          = try(link.route_weight, null)
          shared_key                            = try(link.shared_key, null)
          local_azure_ip_address_enabled        = try(link.local_azure_ip_address_enabled, null)
          policy_based_traffic_selector_enabled = try(link.policy_based_traffic_selector_enabled, null)
          custom_bgp_addresses = try(link.custom_bgp_addresses, null) == null ? [] : [
            for custom_bgp_address in link.custom_bgp_addresses : {
              ip_address          = custom_bgp_address.ip_address
              ip_configuration_id = module.vpn_gateway.ip_configuration_ids[conn.vpn_gateway_key][custom_bgp_address.instance]
            }
          ]
        }
      ]
      routing                 = try(conn.routing, null)
      traffic_selector_policy = try(conn.traffic_selector_policy, null)
    }

  }
  # TFFR6 / TFFR7 / TFFR8 interface cascade -- register and neutrality argument
  # are in `main.express_route_gateway.tf` on `module "express_route_gateways"`.
  ignore_body_changes = var.ignore_body_changes.network_vpn_gateways_vpn_connections
  resource_types      = var.resource_types.network_vpn_gateways_vpn_connections
  retry               = var.retry
  timeouts            = var.timeouts
}

# 🔴 A `moved` BLOCK WAS DELETED HERE, and deleting it was the SAFE act.
#
#   moved {
#     from = azurerm_vpn_gateway_connection.vpn_site_connection
#     to   = module.vpn_site_connection.azurerm_vpn_gateway_connection.vpn_site_connection
#   }
#
# Its `to` address NO LONGER EXISTS: `modules/site-to-site-gateway-connection` is now `azapi_resource.this`.
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
