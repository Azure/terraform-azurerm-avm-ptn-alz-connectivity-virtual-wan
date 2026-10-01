variable "name" {
  type        = string
  description = "The name of the route map."
  nullable    = false
}

variable "virtual_hub_id" {
  type        = string
  description = "The resource ID of the virtual hub to create the route map in."
  nullable    = false
}

variable "associated_inbound_connections" {
  type        = list(string)
  default     = []
  description = "List of connection resource IDs which have this route map associated for inbound traffic."
  nullable    = false
}

variable "associated_outbound_connections" {
  type        = list(string)
  default     = []
  description = "List of connection resource IDs which have this route map associated for outbound traffic."
  nullable    = false
}

variable "ignore_body_changes" {
  type = object({
    virtual_hubs_route_maps = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Body property paths whose changes the `azapi` provider ignores after creation, letting an out-of-band controller own those properties without producing perpetual `terraform plan` drift.

- `virtual_hubs_route_maps` - (Optional) Ignored body paths for the route map, in dot notation relative to the request body, for example `["properties.rules"]`. Default `[]`.

While a path is ignored, configuration changes at that path are no longer sent to Azure. The value is write-only provider state, so a change only takes effect after an `apply`, and supplying a non-empty list requires Terraform 1.11 or later.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for path in var.ignore_body_changes.virtual_hubs_route_maps : length(trimspace(path)) > 0])
    error_message = "Every ignore_body_changes.virtual_hubs_route_maps entry must be a non-empty body path in dot notation, for example \"properties.rules\"."
  }
}

variable "resource_types" {
  type = object({
    virtual_hubs_route_maps = optional(string, "Microsoft.Network/virtualHubs/routeMaps@2025-05-01")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) The Azure resource type and API version used for each resource created by this module.

- `virtual_hubs_route_maps` - (Optional) The type and API version of the route map. Default `Microsoft.Network/virtualHubs/routeMaps@2025-05-01`.
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

variable "rules" {
  type = list(object({
    name                 = string
    next_step_if_matched = optional(string, "Unknown")
    actions = optional(list(object({
      type = string
      parameters = optional(list(object({
        as_path      = optional(list(string), [])
        community    = optional(list(string), [])
        route_prefix = optional(list(string), [])
      })), [])
    })), [])
    match_criteria = optional(list(object({
      match_condition = string
      as_path         = optional(list(string), [])
      community       = optional(list(string), [])
      route_prefix    = optional(list(string), [])
    })), [])
  }))
  default     = []
  description = <<DESCRIPTION
  List of route map rules to apply. Each rule is an object with the following attributes:

  - `name`: The unique name for the rule.
  - `next_step_if_matched`: Next step after rule is evaluated. Supported values are `Continue`, `Terminate`, and `Unknown`. Defaults to `Unknown`.
  - `actions`: Optional list of actions to apply on a match:
    - `type`: Type of action. Supported values are `Add`, `Drop`, `Remove`, `Replace`, and `Unknown`.
    - `parameters`: Optional list of parameters for the action:
      - `as_path`: Optional list of AS paths.
      - `community`: Optional list of BGP communities.
      - `route_prefix`: Optional list of route prefixes.
  - `match_criteria`: Optional list of criteria to match traffic against:
    - `match_condition`: Condition to apply. Supported values are `Contains`, `Equals`, `NotContains`, `NotEquals`, and `Unknown`.
    - `as_path`: Optional list of AS paths to match.
    - `community`: Optional list of BGP communities to match.
    - `route_prefix`: Optional list of route prefixes to match.
  DESCRIPTION
  nullable    = false
}

variable "timeouts" {
  type = object({
    create = optional(string, "30m")
    read   = optional(string, "5m")
    update = optional(string, "30m")
    delete = optional(string, "30m")
  })
  default     = {}
  description = "(Optional) Timeouts for the resource operations."
}
