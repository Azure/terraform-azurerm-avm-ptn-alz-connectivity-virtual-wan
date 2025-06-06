output "bastion_host_public_ip_address" {
  description = "The public IP addresses of the bastion hosts associated with the virtual WAN, grouped by hub key."
  value       = { for key, value in module.bastion_public_ip : key => value.public_ip_address }
}

output "bastion_host_resource_ids" {
  description = "The resource IDs of the bastion hosts associated with the virtual WAN, grouped by hub key."
  value       = { for key, value in module.bastion_host : key => value.resource_id }
}

output "bastion_host_resources" {
  description = "The bastion host resources associated with the virtual WAN, grouped by hub key."
  value       = module.bastion_host
}

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

output "private_dns_resolver_resource_ids" {
  description = "The resource IDs of the private DNS resolvers associated with the virtual WAN, grouped by hub key."
  value       = { for key, value in module.dns_resolver : key => value.resource_id }
}

output "private_dns_resolver_resources" {
  description = "The private DNS resolvers associated with the virtual WAN, grouped by hub key."
  value       = module.dns_resolver
}

output "resource_id" {
  description = "The resource ID of the virtual WAN."
  value       = module.virtual_wan.resource_id
}

output "sidecar_virtual_network_resource_ids" {
  description = "The resource IDs of the side car virtual networks associated with the virtual WAN, grouped by hub key."
  value       = { for key, value in module.virtual_network_side_car : key => value.resource_id }
}

output "sidecar_virtual_network_resources" {
  description = "The side car virtual networks associated with the virtual WAN, grouped by hub key."
  value       = module.virtual_network_side_car
}

output "virtual_hub_resource_ids" {
  description = "The resource IDs of the virtual hubs associated with the virtual WAN."
  value       = module.virtual_wan.virtual_hub_resource_ids
}

output "virtual_hub_resource_names" {
  description = "The names of the virtual hubs associated with the virtual WAN."
  value       = module.virtual_wan.virtual_hub_resource_names
}
