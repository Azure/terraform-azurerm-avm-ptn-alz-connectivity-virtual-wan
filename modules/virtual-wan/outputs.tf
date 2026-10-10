output "diagnostic_settings_azure_firewall_resource_ids" {
  description = "A map of Azure Firewall diagnostic settings resource IDs with the map keys of the `firewalls` variable."
  value       = module.firewalls.diagnostic_settings_resource_ids
}

output "ergw" {
  description = "ExpressRoute Gateway Objects"
  value       = var.expressroute_gateways != null ? [for gw in module.express_route_gateways.resource_object : gw] : null
}

output "ergw_id" {
  description = "ExpressRoute Gateway ID"
  value       = var.expressroute_gateways != null ? [for gw in module.express_route_gateways.resource_object : gw.id] : null
}

output "ergw_resource_ids_by_hub_key" {
  description = "A map of ExpressRoute Gateway resource IDs with the map keys of the `expressroute_gateways` variable."
  value       = try(var.expressroute_gateways, null) != null ? { for key, value in var.expressroute_gateways : value.virtual_hub_key => module.express_route_gateways.resource_object[key].id } : null
}

output "firewall_ip_addresses" {
  description = "Azure Firewall IP addresses."
  value = var.firewalls != null ? { for key, value in module.firewalls.resource_object : key => {
    firewall_key        = key
    private_ip_address  = module.firewalls.resource_object[key].virtual_hub[0].private_ip_address
    public_ip_addresses = module.firewalls.resource_object[key].virtual_hub[0].public_ip_addresses
  } } : null
}

output "p2s_vpn_gw_id" {
  description = "P2S VPN Gateway ID"
  value       = var.p2s_gateways != null ? [for gw in azapi_resource.p2s_gateway : gw.id] : null
}

output "p2s_vpn_gw_resource_ids" {
  description = "A map of point to site VPN gateway names with the map keys of the `p2s_gateways` variable."
  value       = var.p2s_gateways != null ? { for key, value in azapi_resource.p2s_gateway : key => value.id } : null
}

# ⚠️ PRE-EXISTING BUG, PRESERVED DELIBERATELY. This is named `..._names` and documented as
# names, but it returns `.id` -- it did so under `azurerm_point_to_site_vpn_gateway` too, and
# `vpn_gateway_resource_names` below has the identical bug. `azapi_resource` exposes `.name`,
# so the fix is a one-word change, but making it here would silently alter the value of a
# published output during a provider migration. Left as-is; the fix belongs in its own change
# with its own changelog entry.
output "p2s_vpn_gw_resource_names" {
  description = "A map of point to site VPN gateway names with the map keys of the `p2s_gateways` variable."
  value       = var.p2s_gateways != null ? { for key, value in azapi_resource.p2s_gateway : key => value.id } : null
}

output "resource_group_name" {
  description = "Resource Group Name"
  value       = local.resource_group_name
}

output "s2s_vpn_gw" {
  description = "S2S VPN Gateway Objects"
  value       = var.vpn_gateways != null ? [for gw in module.vpn_gateway.resource_object : gw] : null
}

output "s2s_vpn_gw_id" {
  description = "S2S VPN Gateway ID"
  value       = var.vpn_gateways != null ? [for gw in module.vpn_gateway.resource_object : gw.id] : null
}

output "virtual_hub_bgp_connection_resource_ids" {
  description = "A map of Virtual Hub BGP connection resource IDs with the map keys of the `bgp_connections` map of each entry in the `virtual_hubs` variable, prefixed with the virtual hub key (i.e. `<hub_key>-<bgp_connection_key>`)."
  value       = { for key, value in azapi_resource.bgp_connection : key => value.id }
}

output "vpn_gateway_resource_ids" {
  description = "A map of Azure VPN Gateway resource IDs with the map keys of the `vpn_gateways` variable."
  value       = var.vpn_gateways != null ? { for key, value in module.vpn_gateway.resource_object : key => value.id } : null
}

output "vpn_gateway_resource_names" {
  description = "A map of Azure VPN Gateway resource names with the map keys of the `vpn_gateways` variable."
  value       = var.vpn_gateways != null ? { for key, value in module.vpn_gateway.resource_object : key => value.id } : null
}
