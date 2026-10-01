variable "diagnostic_settings" {
  type = map(map(object({
    name                                     = optional(string, null)
    log_categories                           = optional(set(string), [])
    log_groups                               = optional(set(string), ["allLogs"])
    metric_categories                        = optional(set(string), ["AllMetrics"])
    log_analytics_destination_type           = optional(string, "Dedicated")
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  })))
  default     = {}
  description = <<DESCRIPTION
  A map of diagnostic settings to create on the firewall. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.

  The first map key is that of the Virtual Hub key, as defined in the `virtual_hubs` variable. The second map key is arbitrary to define multiple diagnostic settings on each firewall.

  - `name` - (Optional) The name of the diagnostic setting. One will be generated if not set, however this will not be unique if you want to create multiple diagnostic setting resources.
  - `log_categories` - (Optional) A set of log categories to send to the log analytics workspace. Defaults to `[]`.
  - `log_groups` - (Optional) A set of log groups to send to the log analytics workspace. Defaults to `["allLogs"]`.
  - `metric_categories` - (Optional) A set of metric categories to send to the log analytics workspace. Defaults to `["AllMetrics"]`.
  - `log_analytics_destination_type` - (Optional) The destination type for the diagnostic setting. Possible values are `Dedicated` and `AzureDiagnostics`. Defaults to `Dedicated`.
  - `workspace_resource_id` - (Optional) The resource ID of the log analytics workspace to send logs and metrics to.
  - `storage_account_resource_id` - (Optional) The resource ID of the storage account to send logs and metrics to.
  - `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the event hub authorization rule to send logs and metrics to.
  - `event_hub_name` - (Optional) The name of the event hub. If none is specified, the default event hub will be selected.
  - `marketplace_partner_resource_id` - (Optional) The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic LogsLogs.
  DESCRIPTION
  nullable    = false

  validation {
    condition = alltrue(flatten(
      [
        for _, v in var.diagnostic_settings :
        [
          for _, v2 in v : contains(["Dedicated", "AzureDiagnostics"], v2.log_analytics_destination_type)
        ]
      ])
    )
    error_message = "Log analytics destination type must be one of: 'Dedicated', 'AzureDiagnostics'."
  }
  validation {
    condition = alltrue(flatten(
      [
        for _, v in var.diagnostic_settings :
        [
          for _, v2 in v :
          v2.workspace_resource_id != null || v2.storage_account_resource_id != null || v2.event_hub_authorization_rule_resource_id != null || v2.marketplace_partner_resource_id != null
        ]
      ])
    )
    error_message = "At least one of `workspace_resource_id`, `storage_account_resource_id`, `marketplace_partner_resource_id`, or `event_hub_authorization_rule_resource_id`, must be set."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Controls telemetry for the AVM interface utility. Set false to disable telemetry."
  nullable    = false
}

variable "firewalls" {
  type = map(object({
    virtual_hub_id       = string
    sku_name             = optional(string, "AZFW_Hub")
    location             = string
    resource_group_name  = string
    sku_tier             = string
    name                 = string
    zones                = optional(list(number), [1, 2, 3])
    firewall_policy_id   = optional(string)
    vhub_public_ip_count = optional(string, null)
    ip_configurations = optional(map(object({
      name                 = string
      public_ip_address_id = string
    })), {})
    tags = optional(map(string))
  }))
  default     = {}
  description = <<DESCRIPTION

Map of objects for Azure Firewall resources to deploy into the Virtual WAN Virtual Hubs that have been defined in the variable `virtual_hubs`.

The key is deliberately arbitrary to avoid issues with known after apply values. The value is an object, of which there can be multiple in the map:

- `virtual_hub_key`: The arbitrary key specified in the map of objects variable called `virtual_hubs` for the object specifying the Virtual Hub you wish to deploy this Azure Firewall into.
- `sku_name`: The SKU name for the Azure Firewall. Possible values are: `AZFW_VNet`, `AZFW_Hub`. Defaults to `AZFW_Hub`.
- `sku_tier`: The SKU tier for the Azure Firewall. Possible values are: `Basic`, `Standard`, `Premium`.
- `name`: The name for the Azure Firewall resource.
- `zones`: Optional list of zones to deploy the Azure Firewall into. Defaults to `[1, 2, 3]`.
- `firewall_policy_id`: Optional Azure Firewall Policy Resource ID to associate with the Azure Firewall.
- `vhub_public_ip_count`: Optional managed public IP count, retaining the string input type. Null defaults to one managed IP when `ip_configurations` is empty. With customer IPs, only null or zero is accepted.
- `ip_configurations`: Optional map of caller-owned public IP configurations, default `{}`. Keys must be stable and known at plan time; resource IDs may be unknown until apply. Each value requires a unique `name` and `public_ip_address_id`. Customer IPs must be Standard/Regional, static IPv4, in the same subscription and region, and unassociated or already attached to this firewall. Names and IDs must be unique ignoring case. A nonempty map selects customer-only mode; mode conversion is not supported.
- `tags`: Optional tags to apply to the Azure Firewall resource.

> Note: There can be multiple objects in this map, one for each Azure Firewall you wish to deploy into the Virtual WAN Virtual Hubs that have been defined in the variable `virtual_hubs`.

  DESCRIPTION

  validation {
    condition = var.firewalls == null ? true : alltrue([
      for firewall in var.firewalls :
      firewall == null ? false : length(firewall.ip_configurations) == 0 ? true : (
        firewall.sku_name == "AZFW_Hub" && contains(["Standard", "Premium"], firewall.sku_tier)
      )
    ])
    error_message = "Each firewall must be non-null. Customer-IP firewalls must use AZFW_Hub with Standard or Premium SKU."
  }
  validation {
    condition = var.firewalls == null ? true : alltrue([
      for firewall in var.firewalls :
      can(provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", firewall.virtual_hub_id))
    ])
    error_message = "Each virtual_hub_id must be a valid Virtual Hub resource ID."
  }
  validation {
    condition = var.firewalls == null ? true : alltrue([
      for firewall in var.firewalls : firewall.firewall_policy_id == null ? true :
      can(provider::azapi::parse_resource_id("Microsoft.Network/firewallPolicies", firewall.firewall_policy_id))
    ])
    error_message = "Each firewall_policy_id must be a valid Firewall Policy resource ID or null."
  }
  validation {
    condition = var.firewalls == null ? true : alltrue([
      for firewall in var.firewalls : firewall.vhub_public_ip_count == null ? true : try(
        tonumber(firewall.vhub_public_ip_count) >= 0 &&
        floor(tonumber(firewall.vhub_public_ip_count)) == tonumber(firewall.vhub_public_ip_count),
        false
      )
    ])
    error_message = "vhub_public_ip_count must be null or a nonnegative integer represented as a string."
  }
  validation {
    condition = var.firewalls == null ? true : alltrue([
      for firewall in var.firewalls : firewall.vhub_public_ip_count == null ? true : try(
        length(firewall.ip_configurations) > 0 ? tonumber(firewall.vhub_public_ip_count) == 0 : tonumber(firewall.vhub_public_ip_count) > 0,
        false
      )
    ])
    error_message = "Customer ip_configurations require a null or zero vhub_public_ip_count; an empty map requires a positive managed count or null."
  }
  validation {
    condition = var.firewalls == null ? true : alltrue(flatten([
      for firewall in var.firewalls : [
        for key, configuration in firewall.ip_configurations : configuration == null ? false : (
          trimspace(key) != "" && key == trimspace(key) &&
          (configuration.name == null ? false : trimspace(configuration.name) != "" && configuration.name == trimspace(configuration.name))
        )
      ]
    ]))
    error_message = "IP configurations require nonempty stable keys and explicit nonempty names without surrounding whitespace; entries cannot be null."
  }
  validation {
    condition = var.firewalls == null ? true : alltrue(flatten([
      for firewall in var.firewalls : [
        for configuration in firewall.ip_configurations :
        can(provider::azapi::parse_resource_id("Microsoft.Network/publicIPAddresses", configuration.public_ip_address_id))
      ]
    ]))
    error_message = "Every public_ip_address_id must be a valid Microsoft.Network/publicIPAddresses resource ID."
  }
  validation {
    condition = var.firewalls == null ? true : alltrue([
      for firewall in var.firewalls : try(
        length(distinct([for configuration in firewall.ip_configurations : lower(configuration.name)])) == length(firewall.ip_configurations),
        false
      )
    ])
    error_message = "IP configuration names must be unique within each firewall, ignoring case."
  }
  validation {
    condition = var.firewalls == null ? true : try(
      length(distinct(flatten([
        for firewall in var.firewalls : [for configuration in firewall.ip_configurations : lower(configuration.public_ip_address_id)]
        ]))) == length(flatten([
        for firewall in var.firewalls : [for configuration in firewall.ip_configurations : configuration.public_ip_address_id]
      ])),
      false
    )
    error_message = "A public IP can appear only once across all firewall IP configurations, ignoring case."
  }
}

variable "ignore_body_changes" {
  type = object({
    network_azure_firewalls      = optional(list(string), [])
    insights_diagnostic_settings = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
Body-relative dot paths ignored by each AzAPI resource. Changes take effect after apply; ignored configuration is not sent to Azure. Nonempty lists require Terraform 1.11 or later.

- `network_azure_firewalls` - Firewall body paths. IP ownership, IP configuration and hub association paths cannot be ignored.
- `insights_diagnostic_settings` - Diagnostic setting body paths.
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
    network_azure_firewalls      = optional(string, "Microsoft.Network/azureFirewalls@2024-10-01")
    network_public_ip_addresses  = optional(string, "Microsoft.Network/publicIPAddresses@2024-10-01")
    network_virtual_hubs         = optional(string, "Microsoft.Network/virtualHubs@2024-10-01")
    network_virtual_wans         = optional(string, "Microsoft.Network/virtualWans@2024-10-01")
    insights_diagnostic_settings = optional(string, "Microsoft.Insights/diagnosticSettings@2021-05-01-preview")
  })
  default     = {}
  description = <<DESCRIPTION
AzAPI resource types and API versions.

- `network_azure_firewalls` - Firewall resource and inventory reads.
- `network_public_ip_addresses` - Read-only inspection of caller-owned public IPs.
- `network_virtual_hubs` - Read-only inspection of the secured hub.
- `network_virtual_wans` - Read-only inspection of the hub's parent Virtual WAN, the authoritative source for the Standard/Basic SKU.
- `insights_diagnostic_settings` - Diagnostic settings; the preview API supports log category groups.
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
