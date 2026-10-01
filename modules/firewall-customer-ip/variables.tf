variable "ip_configurations" {
  type = map(object({
    name                 = string
    public_ip_address_id = string
  }))
  description = <<DESCRIPTION
Caller-owned public IP configurations keyed by stable caller keys known at plan time. Each value requires `name` and `public_ip_address_id`; IDs may be unknown until apply.

Keep at least one IP to remain in customer mode. Names and IDs must be unique ignoring case. IPs must be Standard/Regional, static IPv4, in the same region and subscription, and unassociated or already attached to this firewall. IP edits are explicit maintenance operations, not a zero-downtime guarantee.

Ownership scope and its documented boundary: this module checks, at plan time, only whether the supplied public IP's `ipConfiguration` property (populated identically regardless of which resource type - network interface, Load Balancer frontend, Application Gateway frontend, VPN/ExpressRoute Gateway, Bastion, Route Server, or NIC-attached API Management/VMSS - set it) shows it already attached elsewhere, and rejects the plan early if so. It deliberately does NOT check NAT Gateway ownership (`natGateway`) or any other association surface client-side: Azure's own control plane independently, synchronously, and pre-mutation rejects an already-owned public IP with a named `PublicIPAddressInUse` error naming the true owner, verified against real Azure directly on this module's own Azure Firewall attach path as well as network-interface and Load Balancer attachment. A public IP must not be attached elsewhere (including via a NAT Gateway) for this module to accept it; that prerequisite is enforced by Azure itself, not by this module.
DESCRIPTION
  nullable    = false

  validation {
    condition     = length(var.ip_configurations) > 0
    error_message = "Customer mode requires at least one IP configuration. Removing the final IP would change modes and is not supported."
  }
  validation {
    condition = alltrue([
      for key, configuration in var.ip_configurations : configuration == null ? false : (
        trimspace(key) != "" && key == trimspace(key) &&
        (configuration.name == null ? false : trimspace(configuration.name) != "" && configuration.name == trimspace(configuration.name))
      )
    ])
    error_message = "IP configurations require nonempty stable keys and explicit nonempty names without surrounding whitespace; entries cannot be null."
  }
  validation {
    condition = alltrue([
      for configuration in var.ip_configurations :
      can(provider::azapi::parse_resource_id("Microsoft.Network/publicIPAddresses", configuration.public_ip_address_id))
    ])
    error_message = "Every public_ip_address_id must be a valid Microsoft.Network/publicIPAddresses resource ID."
  }
  validation {
    condition = try(
      length(distinct([for configuration in var.ip_configurations : lower(configuration.name)])) == length(var.ip_configurations),
      false
    )
    error_message = "IP configuration names must be unique ignoring case."
  }
  validation {
    condition = try(
      length(distinct([for configuration in var.ip_configurations : lower(configuration.public_ip_address_id)])) == length(var.ip_configurations),
      false
    )
    error_message = "Public IP resource IDs must be unique ignoring case."
  }
}

variable "location" {
  type        = string
  description = "Azure region, matching the virtual hub and public IPs."
  nullable    = false
}

variable "name" {
  type        = string
  description = "Firewall resource name."
  nullable    = false
}

variable "parent_id" {
  type        = string
  description = "Resource group ARM ID for the firewall."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id))
    error_message = "parent_id must be a resource group resource ID."
  }
}

variable "virtual_hub_id" {
  type        = string
  description = "Virtual Hub resource ID, which may be unknown until apply."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", var.virtual_hub_id))
    error_message = "virtual_hub_id must be a Virtual Hub resource ID."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "This variable controls whether or not telemetry is enabled for the module. For more information see <https://aka.ms/avm/telemetryinfo>. If it is set to false, then no telemetry will be collected."
  nullable    = false
}

variable "firewall_policy_id" {
  type        = string
  default     = null
  description = "Optional existing firewall policy resource ID."

  validation {
    condition     = var.firewall_policy_id == null ? true : can(provider::azapi::parse_resource_id("Microsoft.Network/firewallPolicies", var.firewall_policy_id))
    error_message = "firewall_policy_id must be a Firewall Policy resource ID or null."
  }
}

variable "ignore_body_changes" {
  type = object({
    authorization_locks            = optional(list(string), [])
    authorization_role_assignments = optional(list(string), [])
    network_azure_firewalls        = optional(list(string), [])
    insights_diagnostic_settings   = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
Body-relative dot paths ignored by each AzAPI resource. Changes take effect after apply; ignored configuration is not sent to Azure. Nonempty lists require Terraform 1.11 or later.

- `network_azure_firewalls` - Firewall body paths; IP and hub association paths cannot be ignored.
- `insights_diagnostic_settings` - Diagnostic setting body paths.
- `authorization_locks` - Resource lock body paths.
- `authorization_role_assignments` - Role assignment body paths.
DESCRIPTION
  nullable    = false

  validation {
    condition = alltrue([
      for path in var.ignore_body_changes.network_azure_firewalls :
      !contains(["", "*", "properties", "properties.*", "properties.hubIPAddresses", "properties.ipConfigurations", "properties.virtualHub"], path) &&
      !startswith(path, "properties.hubIPAddresses.") && !startswith(path, "properties.ipConfigurations.") && !startswith(path, "properties.virtualHub.")
    ])
    error_message = "Firewall IP configurations, managed IP counts, virtual hub association, or all properties cannot be ignored."
  }
}

variable "resource_types" {
  type = object({
    authorization_locks            = optional(string, "Microsoft.Authorization/locks@2020-05-01")
    authorization_role_assignments = optional(string, "Microsoft.Authorization/roleAssignments@2022-04-01")
    network_azure_firewalls        = optional(string, "Microsoft.Network/azureFirewalls@2024-10-01")
    network_public_ip_addresses    = optional(string, "Microsoft.Network/publicIPAddresses@2024-10-01")
    network_virtual_hubs           = optional(string, "Microsoft.Network/virtualHubs@2024-10-01")
    network_virtual_wans           = optional(string, "Microsoft.Network/virtualWans@2024-10-01")
    insights_diagnostic_settings   = optional(string, "Microsoft.Insights/diagnosticSettings@2021-05-01-preview")
  })
  default     = {}
  description = <<DESCRIPTION
AzAPI resource types and API versions.

- `network_azure_firewalls` - Firewall resource and inventory reads.
- `network_public_ip_addresses` - Read-only inspection of caller-owned public IPs.
- `network_virtual_hubs` - Read-only inspection of the secured hub.
- `network_virtual_wans` - Read-only inspection of the hub's parent Virtual WAN, the authoritative source for the Standard/Basic SKU.
- `insights_diagnostic_settings` - Diagnostic settings; the preview API supports log category groups.
- `authorization_locks` - Resource management lock.
- `authorization_role_assignments` - Firewall-scoped role assignments.
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
  description = "AzAPI retries: error_message_regex selects retryable errors, interval_seconds sets the initial delay, and max_interval_seconds limits it."
}

variable "sku_tier" {
  type        = string
  default     = "Standard"
  description = "Firewall SKU tier, Standard or Premium."
  nullable    = false

  validation {
    condition     = contains(["Standard", "Premium"], var.sku_tier)
    error_message = "A customer-IP secured hub requires Standard or Premium Azure Firewall."
  }
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "Tags applied to the firewall."
}

variable "timeouts" {
  type = object({
    create = optional(string, "90m")
    read   = optional(string, "5m")
    update = optional(string, "90m")
    delete = optional(string, "90m")
  })
  default     = {}
  description = "AzAPI operation timeouts. Firewall create, update and delete default to 90m; read defaults to 5m."
}

variable "zones" {
  type        = list(number)
  default     = [1, 2, 3]
  description = "Availability zones. Changing zones requires firewall replacement; this is separate from same-mode IP maintenance."
}
