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
  validation {
    # AzureRM parity, ADDED by the AzAPI migration. `monitor_diagnostic_setting_
    # resource.go` L285-287 hard-failed with "at least one type of Log or Metric
    # must be enabled" before ever calling ARM, and the comment above it
    # (L263) explains why: with neither, the API "creates" but then 404s on
    # Read. AzAPI has no such guard, so a config AzureRM rejected at plan would
    # now create an unreadable object. No previously-working configuration can
    # trip this.
    condition = alltrue(flatten(
      [
        for _, v in var.diagnostic_settings :
        [
          for _, v2 in v :
          length(coalesce(v2.log_categories, [])) > 0 || length(coalesce(v2.log_groups, [])) > 0 || length(coalesce(v2.metric_categories, [])) > 0
        ]
      ])
    )
    error_message = "At least one of `log_categories`, `log_groups`, or `metric_categories` must be non-empty for every diagnostic setting."
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
    # TFNFR38 (Severity-MUST): a LITERAL type through `parse_resource_id`, never a regex.
    # `locals.tf` rebuilds `parent_id` via `split(...)[2]`, so the ID must stay RG-scoped;
    # `parse` alone is looser and admits other scopes -- see `MIGRATION-DEVIATIONS.md`.
    condition = alltrue([
      for firewall in(var.firewalls != null ? values(var.firewalls) : []) :
      can(provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", firewall.virtual_hub_id)) &&
      try(provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", firewall.virtual_hub_id).resource_group_name, "") != ""
    ])
    error_message = "Every `firewalls` entry must set `virtual_hub_id` to a resource-group-scoped `Microsoft.Network/virtualHubs` resource ID."
  }
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
      for firewall in var.firewalls : firewall.firewall_policy_id == null ? true :
      can(provider::azapi::parse_resource_id("Microsoft.Network/firewallPolicies", firewall.firewall_policy_id))
    ])
    error_message = "Each firewall_policy_id must be a valid Firewall Policy resource ID or null."
  }
  validation {
    # AzureRM parity for managed mode: a non-numeric value failed at plan in the SDK. Explicit zero is accepted
    # only together with customer ip_configurations (next validation).
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
    insights_diagnostic_settings = optional(list(string), [])
    network_azure_firewalls      = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Body property paths whose changes the `azapi` provider ignores after creation, letting an out-of-band controller own those properties without producing perpetual `terraform plan` drift.

- `insights_diagnostic_settings` - (Optional) Ignored body paths for the firewall diagnostic settings, in dot notation relative to the request body, for example `["properties.logs"]`. Default `[]`.
- `network_azure_firewalls` - (Optional) Ignored body paths for the Azure Firewall, for example `["tags"]`. Default `[]`. **Read the caveat below before setting this.**

While a path is ignored, configuration changes at that path are no longer sent to Azure. The value is write-only provider state, so a change only takes effect after an `apply`, and supplying a non-empty list requires Terraform 1.11 or later.

> 🔴 CAVEAT ON `network_azure_firewalls`. The key exists because AVM spec TFFR8 (Severity-MUST, Class-Pattern) says the argument "**MUST NOT**" be omitted from any module-declared `azapi_resource`, and this module declares two. Its practical reach, however, is close to nil, and that is a property of this module's writer split rather than of the variable:
>
> - `azapi_resource.fw` is a CREATE-ONLY writer whose `lifecycle.ignore_changes` already contains `body`, so it never issues an update PUT for body drift at all. The provider only consults `ignore_body_changes` where prior state already exists: `overrideBodyWithPaths` is called at `azapi_resource.go` L630 (guarded by `if state != nil && len(ignoreBodyChanges) != 0` at L619, inside `ModifyPlan` at L542) and at L942 (guarded by `if !isNewResource {` at L930). A path list here therefore has nothing to suppress.
> - `azapi_update_resource.fw`, the day-2 writer that does the real work, has NO `ignore_body_changes` argument in `Azure/azapi` v2.12.0. `AzapiUpdateResourceModel` (`internal/services/azapi_update_resource.go` L40-L63) declares no such field and the resource's schema declares no such attribute. Measured by reading the provider source at tag v2.12.0, not inferred from docs.
>
> Use `firewalls.<key>.tags` and the dedicated inputs to control the firewall body. This key is here for spec conformance and for the day the merge writer gains the argument.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for path in var.ignore_body_changes.insights_diagnostic_settings : length(trimspace(path)) > 0])
    error_message = "Every ignore_body_changes.insights_diagnostic_settings entry must be a non-empty body path in dot notation, for example \"properties.logs\"."
  }
  validation {
    condition = alltrue([
      for path in var.ignore_body_changes.network_azure_firewalls :
      !contains(["", "*", "properties", "properties.*", "properties.hubIPAddresses", "properties.ipConfigurations", "properties.virtualHub"], path) &&
      !startswith(path, "properties.hubIPAddresses.") && !startswith(path, "properties.ipConfigurations.") && !startswith(path, "properties.virtualHub.")
    ])
    error_message = "Firewall IP configurations, managed IP counts, virtual hub association, or all properties cannot be ignored."
  }
  validation {
    condition     = alltrue([for path in var.ignore_body_changes.network_azure_firewalls : length(trimspace(path)) > 0])
    error_message = "Every ignore_body_changes.network_azure_firewalls entry must be a non-empty body path in dot notation, for example \"tags\"."
  }
}

variable "resource_types" {
  type = object({
    insights_diagnostic_settings = optional(string, "Microsoft.Insights/diagnosticSettings@2021-05-01-preview")
    network_azure_firewalls      = optional(string, "Microsoft.Network/azureFirewalls@2025-07-01")
    network_public_ip_addresses  = optional(string, "Microsoft.Network/publicIPAddresses@2024-10-01")
    network_virtual_hubs         = optional(string, "Microsoft.Network/virtualHubs@2024-10-01")
    network_virtual_wans         = optional(string, "Microsoft.Network/virtualWans@2024-10-01")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) The Azure resource type and API version used for each resource created by this module.

- `insights_diagnostic_settings` - (Optional) The type and API version of the firewall diagnostic settings. Default `Microsoft.Insights/diagnosticSettings@2021-05-01-preview`, which is the version `hashicorp/azurerm` v4.81.0 used (`monitor_diagnostic_setting_resource.go` L18).
- `network_azure_firewalls` - (Optional) The type and API version of the Azure Firewall. Default `Microsoft.Network/azureFirewalls@2025-07-01`.
- `network_public_ip_addresses` - (Optional) Read-only inspection of caller-owned public IPs (customer-IP mode only). Default `Microsoft.Network/publicIPAddresses@2024-10-01`.
- `network_virtual_hubs` - (Optional) Read-only inspection of the secured hub (customer-IP mode only). Default `Microsoft.Network/virtualHubs@2024-10-01`.
- `network_virtual_wans` - (Optional) Read-only inspection of the hub's parent Virtual WAN (customer-IP mode only). Default `Microsoft.Network/virtualWans@2024-10-01`.

> 🔴 Changing `network_azure_firewalls` on an EXISTING deployment is a breaking change, not a routine bump. `type` is not a replacement trigger on `azapi_resource` (v2.12.0 `azapi_resource.go` L206-212 declares no `RequiresReplace`) and it carries no `skip_on:"update"` tag either, so a changed value drags the create-only full writer into a full PUT of its stale `state.body`. Plan it, read it, and do not apply it casually.
DESCRIPTION
  nullable    = false
}

variable "retry" {
  type = object({
    error_message_regex  = optional(list(string), ["ReferencedResourceNotProvisioned"])
    interval_seconds     = optional(number, 10)
    max_interval_seconds = optional(number, 180)
  })
  default     = {}
  description = "(Optional) Retry configuration for the resource operations."
}

variable "timeouts" {
  type = object({
    create = optional(string)
    read   = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Timeouts for the resource operations. Each value is a Go duration string, for example `30m` or `1h`.

- `create` - (Optional) Timeout for create operations.
- `read`   - (Optional) Timeout for read operations.
- `update` - (Optional) Timeout for update operations.
- `delete` - (Optional) Timeout for delete operations.

An attribute left unset does NOT fall back to a single blanket value. It falls back PER RESOURCE to the timeout default of the `hashicorp/azurerm` v4.81.0 resource that resource replaced, so a migrated deployment keeps the timeouts it had. The fallbacks and their source lines are in `local.timeouts` in `locals.tf`:

- The Azure Firewall - create `90m`, read `5m`, update `90m`, delete `90m` (`firewall_resource.go` L46-51). Applied to BOTH the create-only full writer and the day-2 merge writer.
- The firewall diagnostic settings - create `30m`, read `5m`, update `30m`, delete `60m` (`monitor_diagnostic_setting_resource.go` L43-48). Note the `60m` delete, which is NOT the firewall's `90m`.

🔴 THE SHAPE IS THE FLAT TFFR7 ONE, not a per-resource-keyed object. It used to be keyed by resource type (`network_azure_firewalls` / `insights_diagnostic_settings`), which was untypeable as a cascade target: TFFR7 requires the parent to pass `timeouts = var.timeouts` through unchanged, and the parent's `timeouts` is the flat four-attribute object the spec shows. The per-resource fallbacks were not lost, only moved from the variable into `local.timeouts`, so behaviour at the defaults is unchanged. This variable was never published -- v0.17.2 declared no `timeouts` in this submodule -- so the reshape breaks no released consumer.
DESCRIPTION
  nullable    = false
}
