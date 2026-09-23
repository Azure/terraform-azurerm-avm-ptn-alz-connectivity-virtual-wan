variable "location" {
  type        = string
  description = "Region supporting Standard/Premium secured hubs and the selected availability zones."
}

variable "name_prefix" {
  type        = string
  description = "Unique prefix for the resources this example creates."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group created by this example."
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Whether to enable AVM telemetry for this example."
}

variable "ignore_body_changes" {
  type = object({
    resources_resource_groups   = optional(list(string), [])
    network_public_ip_addresses = optional(list(string), [])
    network_firewall_policies   = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
Body-relative dot paths for this caller's supporting resources. Changes take effect after apply; ignored configuration is not sent to Azure. Leave empty so drift remains visible.

- `resources_resource_groups` - Resource group body paths.
- `network_public_ip_addresses` - Public IP body paths.
- `network_firewall_policies` - Firewall policy body paths.
DESCRIPTION
  nullable    = false
}

variable "public_ip_names" {
  type        = map(string)
  description = "Stable configuration key to public IP resource name. Supply one or more entries; these IPs are owned by this caller, not the pattern."

  validation {
    condition     = length(var.public_ip_names) > 0
    error_message = "Keep at least one public IP to remain in customer mode."
  }
}

variable "resource_types" {
  type = object({
    resources_resource_groups   = optional(string, "Microsoft.Resources/resourceGroups@2022-09-01")
    network_public_ip_addresses = optional(string, "Microsoft.Network/publicIPAddresses@2024-10-01")
    network_firewall_policies   = optional(string, "Microsoft.Network/firewallPolicies@2024-10-01")
  })
  default     = {}
  description = <<DESCRIPTION
AzAPI types and API versions for the caller-owned supporting resources.

- `resources_resource_groups` - Resource group.
- `network_public_ip_addresses` - Public IP pool.
- `network_firewall_policies` - Firewall policy.
DESCRIPTION
  nullable    = false
}

variable "retry" {
  type = object({
    error_message_regex  = optional(list(string))
    interval_seconds     = optional(number)
    max_interval_seconds = optional(number)
  })
  default     = null
  description = "Retries for supporting resources: error_message_regex selects retryable errors, interval_seconds sets the initial delay, and max_interval_seconds limits it."
}

variable "sku_tier" {
  type        = string
  default     = "Standard"
  description = "Firewall and policy tier for this example."

  validation {
    condition     = contains(["Standard", "Premium"], var.sku_tier)
    error_message = "Use Standard or Premium."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the example resources."
}

variable "timeouts" {
  type = object({
    create = optional(string)
    read   = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default     = null
  description = "Optional create, read, update and delete timeouts for the caller-owned supporting resources."
}

variable "zones" {
  type        = list(number)
  default     = [1, 2, 3]
  description = "Matching availability zones for the firewall and public IPs."
}
