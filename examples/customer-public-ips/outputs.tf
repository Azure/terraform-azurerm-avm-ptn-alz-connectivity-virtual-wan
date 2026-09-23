output "firewall_resource_ids" {
  description = "Firewall identity to compare across same-mode maintenance."
  value       = module.virtual_wan.firewall_resource_ids
}

output "firewall_public_ip_addresses" {
  description = "Address strings returned through the pattern's existing output."
  value       = module.virtual_wan.firewall_public_ip_addresses
}

output "caller_owned_public_ip_ids" {
  description = "Caller-owned public IP identities, separate from firewall ownership."
  value       = { for key, ip in azapi_resource.public_ips : key => ip.id }
}

output "resource_group_id" {
  description = "Qualification resource group identity."
  value       = azapi_resource.resource_group.id
}
