variable "ignore_body_changes" {
  type = object({
    network_azure_firewalls = optional(object({
      network_azure_firewalls      = optional(list(string), [])
      insights_diagnostic_settings = optional(list(string), [])
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
AzAPI body-relative dot paths. Changes take effect after apply; ignored configuration is not sent to Azure.

- `network_azure_firewalls` - Firewall submodule overrides.
- `network_azure_firewalls.network_azure_firewalls` - Firewall body paths, excluding IP and hub association paths.
- `network_azure_firewalls.insights_diagnostic_settings` - Firewall diagnostic setting paths.
DESCRIPTION
  nullable    = false
}

variable "resource_types" {
  type = object({
    network_azure_firewalls = optional(object({
      network_azure_firewalls      = optional(string)
      network_public_ip_addresses  = optional(string)
      network_virtual_hubs         = optional(string)
      network_virtual_wans         = optional(string)
      insights_diagnostic_settings = optional(string)
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
AzAPI resource types passed to the firewall submodule. Omitted API versions use the owning submodule's defaults.

- `network_azure_firewalls` - Firewall submodule resource types.
- `network_azure_firewalls.network_azure_firewalls` - Firewall and inventory API.
- `network_azure_firewalls.network_public_ip_addresses` - Caller-owned public IP read API.
- `network_azure_firewalls.network_virtual_hubs` - Secured hub read API.
- `network_azure_firewalls.network_virtual_wans` - Secured hub's parent Virtual WAN read API.
- `network_azure_firewalls.insights_diagnostic_settings` - Firewall diagnostic settings API.
DESCRIPTION
  nullable    = false
}

variable "timeouts" {
  type = object({
    create = optional(string, "90m")
    read   = optional(string, "5m")
    update = optional(string, "90m")
    delete = optional(string, "90m")
  })
  default     = {}
  description = "AzAPI create, read, update and delete timeouts passed unchanged to firewalls."
}
