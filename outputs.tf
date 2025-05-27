output "dns_server_ip_address" {
  description = "The private IP addresses of the DNS servers associated with the virtual WAN."
  value       = module.virtual_wan.firewall_private_ip_address_by_hub_key
}

output "express_route_gateway_resource_ids" {
  description = "The resource IDs of the ExpressRoute gateways associated with the virtual WAN."
  value       = module.virtual_wan.ergw_id
}

output "express_route_gateway_resources" {
  description = "The resource objects of the ExpressRoute gateways associated with the virtual WAN."
  value       = module.virtual_wan.ergw
}

output "firewall_policy_resource_ids" {
  description = "The resource IDs of the firewall policies associated with the virtual WAN."
  value       = { for key, value in module.firewall_policy : key => value.resource_id }
}

output "firewall_private_ip_address" {
  description = "The private IP addresses of the firewalls associated with the virtual WAN, grouped by hub key."
  value       = module.virtual_wan.firewall_private_ip_address_by_hub_key
}

output "firewall_public_ip_addresses" {
  description = "The public IP addresses of the firewalls associated with the virtual WAN, grouped by hub key."
  value       = module.virtual_wan.firewall_public_ip_addresses_by_hub_key
}

output "firewall_resource_ids" {
  description = "The resource IDs of the firewalls associated with the virtual WAN, grouped by hub key."
  value       = module.virtual_wan.firewall_resource_ids_by_hub_key
}

output "firewall_resource_names" {
  description = "The names of the firewalls associated with the virtual WAN, grouped by hub key."
  value       = module.virtual_wan.firewall_resource_names_by_hub_key
}

output "name" {
  description = "The name of the virtual WAN."
  value       = module.virtual_wan.name
}

output "resource_id" {
  description = "The resource ID of the virtual WAN."
  value       = module.virtual_wan.resource_id
}

output "virtual_hub_resource_ids" {
  description = "The resource IDs of the virtual hubs associated with the virtual WAN."
  value       = module.virtual_wan.virtual_hub_resource_ids
}

output "virtual_hub_resource_names" {
  description = "The names of the virtual hubs associated with the virtual WAN."
  value       = module.virtual_wan.virtual_hub_resource_names
}
