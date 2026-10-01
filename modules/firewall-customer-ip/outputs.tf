output "diagnostic_settings_resource_ids" {
  description = "ARM resource IDs of diagnostic settings."
  value       = { for key, setting in azapi_resource.diagnostic_settings : key => setting.id }
}

output "legacy_diagnostic_settings_resource_ids" {
  description = "Compatibility IDs in the legacy firewall helper's firewall-resource-ID|setting-name format."
  value       = { for key, setting in azapi_resource.diagnostic_settings : key => "${azapi_resource.this.id}|${setting.name}" }
}

output "legacy_resource" {
  description = "Compatibility projection for the pre-existing helper's whole-resource output. New consumers should use the discrete outputs instead."
  value = {
    id                  = azapi_resource.this.id
    name                = azapi_resource.this.name
    location            = azapi_resource.this.location
    resource_group_name = provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id).resource_group_name
    sku_name            = "AZFW_Hub"
    sku_tier            = var.sku_tier
    firewall_policy_id  = var.firewall_policy_id == null ? "" : var.firewall_policy_id
    tags                = azapi_resource.this.tags
    zones               = toset([for zone in coalesce(var.zones, []) : tostring(zone)])
    # threatIntelMode is intentionally never set on this AZFW_Hub-sku firewall (see main.tf), and real Azure
    # correspondingly omits the property from the GET response entirely rather than returning it as null.
    threat_intel_mode = try(azapi_resource.this.output.properties.threatIntelMode, null)
    dns_proxy_enabled = try(azapi_resource.this.output.properties.additionalProperties["Network.DNS.EnableProxy"] == "true", false)
    dns_servers       = compact(split(",", try(azapi_resource.this.output.properties.additionalProperties["Network.DNS.Servers"], "")))
    private_ip_ranges = toset(compact(split(",", try(azapi_resource.this.output.properties.additionalProperties["Network.SNAT.PrivateRanges"], ""))))
    ip_configuration = tolist([
      for key in sort(keys(var.ip_configurations)) : {
        name                 = var.ip_configurations[key].name
        public_ip_address_id = var.ip_configurations[key].public_ip_address_id
        private_ip_address   = ""
        subnet_id            = ""
      }
    ])
    management_ip_configuration = slice(tolist([{
      name                 = ""
      public_ip_address_id = ""
      private_ip_address   = ""
      subnet_id            = ""
    }]), 0, 0)
    virtual_hub = local.virtual_hub
    timeouts = false ? {
      create = tostring(null)
      read   = tostring(null)
      update = tostring(null)
      delete = tostring(null)
    } : null
  }
}

output "lock_resource_id" {
  description = "Resource lock ARM ID, or null when no lock is configured."
  value       = one(azapi_resource.lock[*].id)
}

output "name" {
  description = "Firewall resource name."
  value       = azapi_resource.this.name
}

output "private_ip_address" {
  description = "Firewall's private address in its virtual hub."
  value       = local.virtual_hub[0].private_ip_address
}

output "public_ip_addresses" {
  description = "Customer public IPv4 address strings in stable configuration-key order, not resource IDs."
  value       = tolist(local.public_ip_addresses)
}

output "resource_id" {
  description = "Firewall resource ID."
  value       = azapi_resource.this.id
}

output "role_assignment_resource_ids" {
  description = "Firewall-scoped role assignment ARM IDs keyed by the caller's stable keys."
  value       = { for key, assignment in azapi_resource.role_assignments : key => assignment.id }
}

output "virtual_hub" {
  description = "Legacy virtual-hub output shape, including private and public address strings."
  value       = local.virtual_hub
}
