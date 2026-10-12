output "azure_firewall_resource_names" {
  description = "Azure Firewall resource name"
  value       = var.firewalls != null ? [for fw in local.resource_objects : fw.name] : []
}

output "diagnostic_settings_resource_ids" {
  description = "Value of the diagnostic settings resource ID for Azure Firewall"
  value = merge(
    { for key, value in azurerm_monitor_diagnostic_setting.this : key => value.id },
    merge([for firewall in module.customer_firewalls : firewall.legacy_diagnostic_settings_resource_ids]...)
  )
}

output "private_ip_address" {
  description = "Azure Firewall IP addresses"
  value       = var.firewalls != null ? { for key, value in local.resource_objects : key => value.virtual_hub[0].private_ip_address } : null
}

output "public_ip_addresses" {
  description = "Azure Firewall IP addresses"
  value       = var.firewalls != null ? { for key, value in local.resource_objects : key => value.virtual_hub[0].public_ip_addresses } : null
}

output "resource" {
  description = "Azure Firewall resource"
  value       = var.firewalls != null ? local.resource_objects : {}
}

output "resource_id" {
  description = "Azure Firewall resource ID"
  value       = var.firewalls != null ? [for fw in local.resource_objects : fw.id] : []
}

output "resource_ids" {
  description = "Azure Firewall resource IDs"
  value       = var.firewalls != null ? { for key, value in local.resource_objects : key => value.id } : null
}

output "resource_names" {
  description = "Azure Firewall resource names"
  value       = var.firewalls != null ? { for key, value in local.resource_objects : key => value.name } : null
}

output "resource_object" {
  description = "Azure Firewall resource object"
  value = var.firewalls != null ? {
    for key, fw in local.resource_objects : key => {
      id          = fw.id
      name        = fw.name
      virtual_hub = fw.virtual_hub
    }
  } : {}
}
