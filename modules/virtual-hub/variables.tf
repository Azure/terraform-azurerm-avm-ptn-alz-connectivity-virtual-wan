variable "ignore_body_changes" {
  type = object({
    network_virtual_hubs = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Body property paths whose changes the `azapi` provider ignores after creation, letting an out-of-band controller own those properties without producing perpetual `terraform plan` drift.

- `network_virtual_hubs` - (Optional) Ignored body paths for the Virtual Hub, in dot notation relative to the request body, for example `["properties.sku"]`. Default `[]`.

While a path is ignored, configuration changes at that path are no longer sent to Azure. The value is write-only provider state, so a change only takes effect after an `apply`, and supplying a non-empty list requires Terraform 1.11 or later.

> Note: the Virtual Hub full writer is create-only and already carries `body` in its `lifecycle.ignore_changes`, so this variable is close to inert on this module. It is kept for shape-consistency with the sibling modules.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for path in var.ignore_body_changes.network_virtual_hubs : length(trimspace(path)) > 0])
    error_message = "Every ignore_body_changes.network_virtual_hubs entry must be a non-empty body path in dot notation, for example \"properties.sku\"."
  }
}

variable "resource_types" {
  type = object({
    network_virtual_hubs = optional(string, "Microsoft.Network/virtualHubs@2025-07-01")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) The Azure resource type and API version used for each resource created by this module.

- `network_virtual_hubs` - (Optional) The type and API version of the Virtual Hub. Default `Microsoft.Network/virtualHubs@2025-07-01`.
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

variable "tags_depends_on" {
  type        = list(string)
  default     = []
  description = <<DESCRIPTION
(Optional) Resource IDs whose writes must finish before the hub tags write starts. Only the reference is used, not the values.

The Virtual WAN module passes the firewall policy IDs here. A tags write puts the hub in `Updating` for several minutes. A firewall policy PUT that runs in the same window pushes the policy to the hub firewall, the firewall rejects the push with `ReferencedResourceNotProvisioned`, and the policy fails with `FirewallPolicyUpdateFailed`. The failure is the final state of a long-running operation, so `retry` cannot catch it.
DESCRIPTION
  nullable    = false
}

variable "timeouts" {
  type = object({
    create = optional(string, "60m")
    read   = optional(string, "5m")
    update = optional(string, "60m")
    delete = optional(string, "60m")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Timeouts for the resource operations.

The defaults are `azurerm_virtual_hub`'s own per-resource defaults at provider v4.81.0 (`virtual_hub_resource.go` L47-52): create `60m`, read `5m`, update `60m`, delete `60m`. They are deliberately NOT the shared `30m` used elsewhere in this repository - a Virtual Hub create polls its `routingState` to `Provisioned` on top of the ARM long-running operation, which is why the create budget is twice the repository default.
DESCRIPTION
  nullable    = false
}

variable "virtual_hubs" {
  type = map(object({
    name                                   = string
    location                               = string
    resource_group_name                    = optional(string, null)
    address_prefix                         = string
    tags                                   = optional(map(string))
    virtual_wan_id                         = string
    hub_routing_preference                 = optional(string, "ExpressRoute")
    virtual_router_auto_scale_min_capacity = optional(number, 2)
    sku                                    = optional(string, null)
  }))
  default     = {}
  description = <<DESCRIPTION
  Map of objects for Virtual Hubs to deploy into the Virtual WAN.

  The key is deliberately arbitrary to avoid issues with known after apply values. The value is an object, of which there can be multiple in the map:

  - `name`: Name for the Virtual Hub resource.
  - `location`: Location for the Virtual Hub resource.
  - `resource_group_name`: Optional resource group name to deploy the Virtual Hub into. If not specified, the Virtual Hub will be deployed into the resource group specified in the variable `resource_group_name`, e.g. the same as the Virtual WAN itself.
  - `address_prefix`: Address prefix for the Virtual Hub. Recommend using a `/23` CIDR block.
  - `tags`: Optional tags to apply to the Virtual Hub resource.
  - `hub_routing_preference`: Optional hub routing preference for the Virtual Hub. Possible values are: `ExpressRoute`, `ASPath`, `VpnGateway`. Defaults to `ExpressRoute`. See https://learn.microsoft.com/azure/virtual-wan/hub-settings#routing-preference for more information.
  - `virtual_router_auto_scale_min_capacity`: Optional minimum capacity for the Virtual Router auto scale. Defaults to `2`. See https://learn.microsoft.com/azure/virtual-wan/hub-settings#capacity for more information.

  > Note: There can be multiple objects in this map, one for each Virtual Hub you wish to deploy into the Virtual WAN. Multiple Virtual Hubs in the same region/location can be deployed into the same Virtual WAN also.

  DESCRIPTION
  nullable    = false
}
