variable "resource_types" {
  type = object({
    network_virtual_wans = optional(object({
      network_azure_firewalls = optional(object({
        network_azure_firewalls      = optional(string)
        network_public_ip_addresses  = optional(string)
        network_virtual_hubs         = optional(string)
        network_virtual_wans         = optional(string)
        insights_diagnostic_settings = optional(string)
      }), {})
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
AzAPI resource-type overrides for firewalls. Omitted versions use the owning submodule's defaults.

- `network_virtual_wans` - Virtual WAN submodule resource types.
- `network_virtual_wans.network_azure_firewalls` - Firewall submodule resource types.
- `network_virtual_wans.network_azure_firewalls.network_azure_firewalls` - Firewall and inventory API.
- `network_virtual_wans.network_azure_firewalls.network_public_ip_addresses` - Caller-owned public IP read API.
- `network_virtual_wans.network_azure_firewalls.network_virtual_hubs` - Secured hub read API.
- `network_virtual_wans.network_azure_firewalls.network_virtual_wans` - Secured hub's parent Virtual WAN read API.
- `network_virtual_wans.network_azure_firewalls.insights_diagnostic_settings` - Firewall diagnostic settings API.
DESCRIPTION
  nullable    = false
}
