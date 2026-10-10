locals {
  # AzureRM exposed the `vpn_link` blocks back as a computed list, with every schema default
  # already materialised. AzAPI has no equivalent attribute, so the same shape is projected
  # from configuration plus the defaults recorded in `main.tf`. The list is built from the
  # CONFIGURED links, so its order matches `var.vpn_site_connection[key].vpn_links` exactly.
  #
  # 🔴 `shared_key` is deliberately NOT returned. It now travels through the write-only
  # `sensitive_body` argument, so it is not in state, and re-emitting it here from
  # configuration would put the secret straight back into state via this output. AzureRM
  # returned it; that is a deliberate, reported deviation.
  vpn_site_connection_links = {
    for key, value in local.vpn_site_connections : key => [
      for link in(try(value.vpn_links, null) != null ? value.vpn_links : []) : {
        name                                  = link.name
        vpn_site_link_id                      = link.vpn_site_link_id
        bandwidth_mbps                        = try(link.bandwidth_mbps, null) != null ? link.bandwidth_mbps : local.vpn_link_defaults.bandwidth_mbps
        bgp_enabled                           = try(link.bgp_enabled, null) != null ? link.bgp_enabled : local.vpn_link_defaults.bgp_enabled
        connection_mode                       = try(link.connection_mode, null) != null ? link.connection_mode : local.vpn_link_defaults.connection_mode
        dpd_timeout_seconds                   = try(link.dpd_timeout_seconds, null)
        egress_nat_rule_ids                   = try(link.egress_nat_rule_ids, null) != null ? link.egress_nat_rule_ids : []
        ingress_nat_rule_ids                  = try(link.ingress_nat_rule_ids, null) != null ? link.ingress_nat_rule_ids : []
        ipsec_policy                          = try(link.ipsec_policy, null) != null ? [link.ipsec_policy] : []
        local_azure_ip_address_enabled        = try(link.local_azure_ip_address_enabled, null) != null ? link.local_azure_ip_address_enabled : local.vpn_link_defaults.local_azure_ip_address_enabled
        policy_based_traffic_selector_enabled = try(link.policy_based_traffic_selector_enabled, null) != null ? link.policy_based_traffic_selector_enabled : local.vpn_link_defaults.policy_based_traffic_selector_enabled
        protocol                              = try(link.protocol, null) != null ? link.protocol : local.vpn_link_defaults.protocol
        ratelimit_enabled                     = try(link.ratelimit_enabled, null) != null ? link.ratelimit_enabled : local.vpn_link_defaults.ratelimit_enabled
        route_weight                          = try(link.route_weight, null) != null ? link.route_weight : local.vpn_link_defaults.route_weight
        shared_key                            = null
        custom_bgp_address = [
          for custom_bgp_address in(try(link.custom_bgp_addresses, null) != null ? link.custom_bgp_addresses : []) : {
            ip_address          = custom_bgp_address.ip_address
            ip_configuration_id = custom_bgp_address.ip_configuration_id
          }
        ]
      }
    ]
  }
}

output "resource" {
  description = "Azure VPN Connection resource"
  value       = var.vpn_site_connection != null ? { for key, value in azapi_resource.this : key => value } : {}
}

output "resource_id" {
  description = "Azure VPN Connection resource ID"
  value       = var.vpn_site_connection != null ? { for key, value in azapi_resource.this : key => value.id } : {}
}

output "resource_object" {
  description = "Azure VPN Connection resource object"
  value = var.vpn_site_connection != null ? {
    for key, value in azapi_resource.this : key => {
      id   = value.id
      name = value.name
      link = local.vpn_site_connection_links[key]
    }
  } : {}
}
