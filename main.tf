module "firewall_policy" {
  source   = "Azure/avm-res-network-firewallpolicy/azurerm"
  version  = "0.3.3"
  for_each = local.firewall_policies

  location                                          = each.value.location
  name                                              = each.value.name
  resource_group_name                               = each.value.resource_group_name
  enable_telemetry                                  = var.enable_telemetry
  firewall_policy_auto_learn_private_ranges_enabled = each.value.auto_learn_private_ranges_enabled
  firewall_policy_base_policy_id                    = each.value.base_policy_id
  firewall_policy_dns                               = each.value.dns
  firewall_policy_explicit_proxy                    = each.value.explicit_proxy
  firewall_policy_identity                          = each.value.identity
  firewall_policy_insights                          = each.value.insights
  firewall_policy_intrusion_detection               = each.value.intrusion_detection
  firewall_policy_private_ip_ranges                 = each.value.private_ip_ranges
  firewall_policy_sku                               = each.value.sku
  firewall_policy_sql_redirect_allowed              = each.value.sql_redirect_allowed
  firewall_policy_threat_intelligence_allowlist     = each.value.threat_intelligence_allowlist
  firewall_policy_threat_intelligence_mode          = each.value.threat_intelligence_mode
  firewall_policy_timeouts                          = var.timeouts
  firewall_policy_tls_certificate                   = each.value.tls_certificate
  tags                                              = each.value.tags
}

module "virtual_wan" {
  source = "./modules/virtual-wan"
  count  = local.has_regions ? 1 : 0

  location                              = local.virtual_wan.location
  resource_group_name                   = local.virtual_wan.resource_group_name
  virtual_wan_name                      = local.virtual_wan.name
  allow_branch_to_branch_traffic        = local.virtual_wan.allow_branch_to_branch_traffic
  disable_vpn_encryption                = local.virtual_wan.disable_vpn_encryption
  enable_telemetry                      = var.enable_telemetry
  er_circuit_connections                = local.express_route_circuit_connections
  expressroute_gateways                 = local.virtual_network_gateways_express_route
  firewalls                             = local.firewalls
  office365_local_breakout_category     = local.virtual_wan.office365_local_breakout_category
  p2s_gateway_vpn_server_configurations = local.p2s_gateway_vpn_server_configurations
  p2s_gateways                          = local.p2s_gateways
  routing_intents                       = local.routing_intents
  tags                                  = var.tags
  type                                  = local.virtual_wan.type
  virtual_hubs                          = local.virtual_hubs
  virtual_network_connections           = local.virtual_network_connections
  virtual_wan_tags                      = local.virtual_wan.tags
  vpn_gateways                          = local.virtual_network_gateways_vpn
  vpn_site_connections                  = local.vpn_site_connections
  vpn_sites                             = local.vpn_sites
}

moved {
  from = module.virtual_wan
  to   = module.virtual_wan[0]
}

module "virtual_network_side_car" {
  source   = "Azure/avm-res-network-virtualnetwork/azurerm"
  version  = "0.15.0"
  for_each = local.sidecar_virtual_networks

  location             = each.value.location
  parent_id            = each.value.parent_id
  address_space        = each.value.address_space
  ddos_protection_plan = each.value.ddos_protection_plan
  enable_telemetry     = var.enable_telemetry
  name                 = each.value.name
  retry                = var.retry
  subnets              = local.subnets[each.key]
  tags                 = each.value.tags
  timeouts             = var.timeouts
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
  outbound_endpoints          = each.value.outbound_endpoints
  tags                        = each.value.tags
}

module "private_dns_zones" {
  source   = "Azure/avm-ptn-network-private-link-private-dns-zones/azurerm"
  version  = "0.22.2"
  for_each = local.private_dns_zones

  location                                                   = each.value.location
  parent_id                                                  = each.value.parent_id
  enable_telemetry                                           = var.enable_telemetry
  private_link_excluded_zones                                = each.value.private_link_excluded_zones
  private_link_private_dns_zones                             = each.value.private_link_private_dns_zones
  private_link_private_dns_zones_additional                  = each.value.private_link_private_dns_zones_additional
  private_link_private_dns_zones_regex_filter                = each.value.private_link_private_dns_zones_regex_filter
  tags                                                       = var.tags
  virtual_network_link_additional_virtual_networks           = each.value.virtual_network_link_additional_virtual_networks
  virtual_network_link_by_zone_and_virtual_network           = each.value.virtual_network_link_by_zone_and_virtual_network
  virtual_network_link_default_virtual_networks              = each.value.virtual_network_link_default_virtual_networks
  virtual_network_link_name_template                         = each.value.virtual_network_link_name_template
  virtual_network_link_overrides_by_virtual_network          = each.value.virtual_network_link_overrides_by_virtual_network
  virtual_network_link_overrides_by_zone                     = each.value.virtual_network_link_overrides_by_zone
  virtual_network_link_overrides_by_zone_and_virtual_network = each.value.virtual_network_link_overrides_by_zone_and_virtual_network
  virtual_network_link_resolution_policy_default             = each.value.virtual_network_link_resolution_policy_default
}

module "private_dns_zone_auto_registration" {
  source   = "Azure/avm-res-network-privatednszone/azurerm"
  version  = "0.4.3"
  for_each = local.private_dns_zones_auto_registration

  domain_name           = each.value.domain_name
  parent_id             = each.value.parent_id
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
  tags                = local.ddos_protection_plan.tags
}

module "bastion_public_ip" {
  source   = "Azure/avm-res-network-publicipaddress/azurerm"
  version  = "0.2.0"
  for_each = local.bastion_host_public_ips

  location                = each.value.location
  name                    = each.value.name
  resource_group_name     = each.value.resource_group_name
  allocation_method       = each.value.public_ip_settings.allocation_method
  ddos_protection_mode    = each.value.public_ip_settings.ddos_protection_mode
  ddos_protection_plan_id = each.value.public_ip_settings.ddos_protection_plan_id
  domain_name_label       = each.value.public_ip_settings.domain_name_label
  edge_zone               = each.value.public_ip_settings.edge_zone
  enable_telemetry        = var.enable_telemetry
  idle_timeout_in_minutes = each.value.public_ip_settings.idle_timeout_in_minutes
  ip_tags                 = each.value.public_ip_settings.ip_tags
  ip_version              = each.value.public_ip_settings.ip_version
  public_ip_prefix_id     = each.value.public_ip_settings.public_ip_prefix_id
  reverse_fqdn            = each.value.public_ip_settings.reverse_fqdn
  sku                     = each.value.public_ip_settings.sku
  sku_tier                = each.value.public_ip_settings.sku_tier
  tags                    = each.value.tags
  zones                   = each.value.zones
}

module "bastion_host" {
  source   = "Azure/avm-res-network-bastionhost/azurerm"
  version  = "0.6.0"
  for_each = local.bastion_hosts

  location               = each.value.location
  name                   = each.value.name
  resource_group_name    = each.value.resource_group_name
  copy_paste_enabled     = each.value.bastion_settings.copy_paste_enabled
  enable_telemetry       = var.enable_telemetry
  file_copy_enabled      = each.value.bastion_settings.file_copy_enabled
  ip_configuration       = each.value.ip_configuration
  ip_connect_enabled     = each.value.bastion_settings.ip_connect_enabled
  kerberos_enabled       = each.value.bastion_settings.kerberos_enabled
  scale_units            = each.value.bastion_settings.scale_units
  shareable_link_enabled = each.value.bastion_settings.shareable_link_enabled
  sku                    = each.value.bastion_settings.sku
  tags                   = each.value.tags
  tunneling_enabled      = each.value.bastion_settings.tunneling_enabled
  zones                  = each.value.zones
}
