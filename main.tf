module "firewall_policy" {
  source   = "Azure/avm-res-network-firewallpolicy/azurerm"
  version  = "0.3.3"
  for_each = local.firewall_policies

  location                                          = each.value.location
  name                                              = each.value.name
  resource_group_name                               = each.value.resource_group_name
  enable_telemetry                                  = var.enable_telemetry
  firewall_policy_auto_learn_private_ranges_enabled = try(each.value.auto_learn_private_ranges_enabled, null)
  firewall_policy_base_policy_id                    = try(each.value.base_policy_id, null)
  firewall_policy_dns                               = each.value.dns
  firewall_policy_explicit_proxy                    = try(each.value.explicit_proxy, null)
  firewall_policy_identity                          = try(each.value.identity, null)
  firewall_policy_insights                          = try(each.value.insights, null)
  firewall_policy_intrusion_detection               = try(each.value.intrusion_detection, null)
  firewall_policy_private_ip_ranges                 = try(each.value.private_ip_ranges, null)
  firewall_policy_sku                               = try(each.value.sku, "Standard")
  firewall_policy_sql_redirect_allowed              = try(each.value.sql_redirect_allowed, null)
  firewall_policy_threat_intelligence_allowlist     = try(each.value.threat_intelligence_allowlist, null)
  firewall_policy_threat_intelligence_mode          = try(each.value.threat_intelligence_mode, "Alert")
  firewall_policy_timeouts                          = try(each.value.timeouts, null)
  firewall_policy_tls_certificate                   = try(each.value.tls_certificate, null)
  tags                                              = try(each.value.tags, var.tags)
}

module "virtual_wan" {
  source  = "Azure/avm-ptn-virtualwan/azurerm"
  version = "0.12.3"

  location                              = var.virtual_wan_settings.location
  resource_group_name                   = var.virtual_wan_settings.resource_group_name
  virtual_wan_name                      = var.virtual_wan_settings.name
  allow_branch_to_branch_traffic        = try(var.virtual_wan_settings.allow_branch_to_branch_traffic, null)
  create_resource_group                 = false
  disable_vpn_encryption                = try(var.virtual_wan_settings.disable_vpn_encryption, false)
  enable_telemetry                      = var.enable_telemetry
  er_circuit_connections                = try(var.virtual_wan_settings.er_circuit_connections, {})
  expressroute_gateways                 = local.virtual_network_gateways_express_route
  firewalls                             = local.firewalls
  office365_local_breakout_category     = try(var.virtual_wan_settings.office365_local_breakout_category, "None")
  p2s_gateway_vpn_server_configurations = try(var.virtual_wan_settings.p2s_gateway_vpn_server_configurations, {})
  p2s_gateways                          = try(var.virtual_wan_settings.p2s_gateways, {})
  resource_group_tags                   = try(var.virtual_wan_settings.resource_group_tags, null)
  routing_intents                       = try(var.virtual_wan_settings.routing_intents, null)
  tags                                  = try(var.virtual_wan_settings.tags, var.tags)
  type                                  = try(var.virtual_wan_settings.type, "Standard")
  virtual_hubs                          = local.virtual_hubs
  virtual_network_connections           = local.virtual_network_connections
  virtual_wan_tags                      = try(var.virtual_wan_settings.virtual_wan_tags, null)
  vpn_gateways                          = local.virtual_network_gateways_vpn
  vpn_site_connections                  = try(var.virtual_wan_settings.vpn_site_connections, {})
  vpn_sites                             = try(var.virtual_wan_settings.vpn_sites, {})
}

module "virtual_network_side_car" {
  source   = "Azure/avm-res-network-virtualnetwork/azurerm"
  version  = "0.9.3"
  for_each = local.side_car_virtual_networks

  address_space        = each.value.address_space
  location             = each.value.location
  resource_group_name  = each.value.resource_group_name
  ddos_protection_plan = each.value.ddos_protection_plan
  enable_telemetry     = var.enable_telemetry
  name                 = each.value.name
  subnets              = local.subnets[each.key]
  tags                 = var.tags
}

module "dns_resolver" {
  source   = "Azure/avm-res-network-dnsresolver/azurerm"
  version  = "0.7.3"
  for_each = local.private_dns_resolver

  location                    = each.value.location
  name                        = each.value.name
  resource_group_name         = each.value.resource_group_name
  virtual_network_resource_id = module.virtual_network_side_car[each.key].resource_id
  enable_telemetry            = var.enable_telemetry
  inbound_endpoints           = each.value.inbound_endpoints
  outbound_endpoints          = try(each.value.outbound_endpoints, null)
  tags                        = var.tags
}

module "private_dns_zones" {
  source   = "Azure/avm-ptn-network-private-link-private-dns-zones/azurerm"
  version  = "0.15.0"
  for_each = local.private_dns_zones

  location                                    = each.value.location
  resource_group_name                         = each.value.resource_group_name
  enable_telemetry                            = var.enable_telemetry
  private_link_excluded_zones                 = try(each.value.private_link_excluded_zones, [])
  private_link_private_dns_zones              = try(each.value.private_link_private_dns_zones, null)
  private_link_private_dns_zones_additional   = try(each.value.private_link_private_dns_zones_additional, null)
  private_link_private_dns_zones_regex_filter = try(each.value.private_link_private_dns_zones_regex_filter, null)
  resource_group_creation_enabled             = false
  tags                                        = var.tags
  virtual_network_resource_ids_to_link_to     = local.private_dns_zones_virtual_network_links
}

module "private_dns_zone_auto_registration" {
  source   = "Azure/avm-res-network-privatednszone/azurerm"
  version  = "0.3.3"
  for_each = local.private_dns_zones_auto_registration

  domain_name           = each.value.domain_name
  resource_group_name   = each.value.resource_group_name
  enable_telemetry      = var.enable_telemetry
  tags                  = var.tags
  virtual_network_links = each.value.virtual_network_links
}

module "ddos_protection_plan" {
  source  = "Azure/avm-res-network-ddosprotectionplan/azurerm"
  version = "0.3.0"
  count   = local.ddos_protection_plan_enabled ? 1 : 0

  location            = local.ddos_protection_plan.location
  name                = local.ddos_protection_plan.name
  resource_group_name = local.ddos_protection_plan.resource_group_name
  enable_telemetry    = var.enable_telemetry
  tags                = var.tags
}

module "bastion_public_ip" {
  source   = "Azure/avm-res-network-publicipaddress/azurerm"
  version  = "0.2.0"
  for_each = local.bastion_host_public_ips

  location                = each.value.location
  name                    = try(each.value.name, "pip-bastion-${each.key}")
  resource_group_name     = each.value.resource_group_name
  allocation_method       = try(each.value.allocation_method, "Static")
  ddos_protection_mode    = try(each.value.ddos_protection_mode, "VirtualNetworkInherited")
  ddos_protection_plan_id = try(each.value.ddos_protection_plan_id, null)
  diagnostic_settings     = try(each.value.diagnostic_settings, null)
  domain_name_label       = try(each.value.domain_name_label, null)
  edge_zone               = try(each.value.edge_zone, null)
  enable_telemetry        = var.enable_telemetry
  idle_timeout_in_minutes = try(each.value.idle_timeout_in_minutes, 4)
  ip_tags                 = try(each.value.ip_tags, null)
  ip_version              = try(each.value.ip_version, "IPv4")
  lock                    = try(each.value.lock, null)
  public_ip_prefix_id     = try(each.value.public_ip_prefix_id, null)
  reverse_fqdn            = try(each.value.reverse_fqdn, null)
  role_assignments        = try(each.value.role_assignments, {})
  sku                     = try(each.value.sku, "Standard")
  sku_tier                = try(each.value.sku_tier, "Regional")
  tags                    = try(each.value.tags, var.tags)
  zones                   = try(each.value.zones, [1, 2, 3])
}

module "bastion_host" {
  source   = "Azure/avm-res-network-bastionhost/azurerm"
  version  = "0.6.0"
  for_each = local.bastion_hosts

  location               = each.value.location
  name                   = try(each.value.name, "snap-bastion-${each.key}")
  resource_group_name    = each.value.resource_group_name
  copy_paste_enabled     = try(each.value.copy_paste_enabled, false)
  diagnostic_settings    = try(each.value.diagnostic_settings, null)
  enable_telemetry       = var.enable_telemetry
  file_copy_enabled      = try(each.value.file_copy_enabled, false)
  ip_configuration       = each.value.ip_configuration
  ip_connect_enabled     = try(each.value.ip_connect_enabled, false)
  kerberos_enabled       = try(each.value.kerberos_enabled, false)
  lock                   = try(each.value.lock, null)
  role_assignments       = try(each.value.role_assignments, {})
  scale_units            = try(each.value.scale_units, 2)
  shareable_link_enabled = try(each.value.shareable_link_enabled, false)
  sku                    = try(each.value.sku, "Standard")
  tags                   = try(each.value.tags, var.tags)
  tunneling_enabled      = try(each.value.tunneling_enabled, false)
  virtual_network_id     = try(each.value.virtual_network_id, null)
  zones                  = try(each.value.zones, try(local.bastion_host_public_ips[each.key].zones, null))
}
