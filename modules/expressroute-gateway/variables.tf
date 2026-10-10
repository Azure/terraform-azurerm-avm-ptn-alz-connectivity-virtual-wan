variable "expressroute_gateways" {
  type = map(object({
    name                          = string
    virtual_hub_id                = string
    location                      = string
    resource_group_name           = string
    tags                          = optional(map(string))
    allow_non_virtual_wan_traffic = optional(bool, false)
    scale_units                   = optional(number, 1)
  }))
  default     = {}
  description = <<DESCRIPTION

Map of objects for Express Route Gateways to deploy into the Virtual WAN Virtual Hubs that have been defined in the variable `virtual_hubs`.

The key is deliberately arbitrary to avoid issues with known after apply values. The value is an object, of which there can be multiple in the map:

- `name`: Name for the ExpressRoute Gateway to deploy in the Virtual WAN Virtual Hub.
- `virtual_hub_id`: The object ID of the virtual hub.
- `tags`: Optional tags to apply to the ExpressRoute Gateway resource.
- `allow_non_virtual_wan_traffic`: Optional boolean to configures this gateway to accept traffic from non Virtual WAN networks. Defaults to `false`.
- `scale_units`: Optional number of scale units for the ExpressRoute Gateway. Defaults to `1`. See: https://learn.microsoft.com/azure/virtual-wan/virtual-wan-expressroute-about#expressroute-gateway-performance for more information on scale units.

> Note: There can be multiple objects in this map, one for each ExpressRoute Gateway you wish to deploy into the Virtual WAN Virtual Hubs that have been defined in the variable `virtual_hubs`.

  DESCRIPTION

  validation {
    # TFNFR38 (Severity-MUST): a LITERAL type through `parse_resource_id`, never a regex.
    # `main.tf` rebuilds `parent_id` via `split(...)[2]`, so the ID must stay RG-scoped;
    # `parse` alone is looser and admits other scopes -- see `MIGRATION-DEVIATIONS.md`.
    condition = alltrue([
      for gateway in(var.expressroute_gateways != null ? values(var.expressroute_gateways) : []) :
      can(provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", gateway.virtual_hub_id)) &&
      try(provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", gateway.virtual_hub_id).resource_group_name, "") != ""
    ])
    error_message = "Every expressroute_gateways[*].virtual_hub_id must be a resource-group-scoped Microsoft.Network/virtualHubs resource ID of the form /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualHubs/<name>."
  }
  validation {
    # `azurerm_express_route_gateway` validated this with `validation.IntBetween(1, 10)`
    # (express_route_gateway_resource.go L68). AzAPI has no per-property validator, so the
    # check moves here rather than being lost -- an out-of-range value would otherwise only
    # fail at ARM, 90 minutes into an apply.
    condition = alltrue([
      for gateway in(var.expressroute_gateways != null ? values(var.expressroute_gateways) : []) :
      gateway.scale_units == null || (try(gateway.scale_units, 1) >= 1 && try(gateway.scale_units, 1) <= 10)
    ])
    error_message = "Every expressroute_gateways[*].scale_units must be between 1 and 10 inclusive, matching azurerm_express_route_gateway's validation.IntBetween(1, 10)."
  }
}

variable "ignore_body_changes" {
  type = object({
    network_express_route_gateways = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Body property paths whose changes the `azapi` provider ignores after creation, letting an out-of-band controller own those properties without producing perpetual `terraform plan` drift.

- `network_express_route_gateways` - (Optional) Ignored body paths for the ExpressRoute Gateway, in dot notation relative to the request body, for example `["properties.autoScaleConfiguration"]`. Default `[]`.

While a path is ignored, configuration changes at that path are no longer sent to Azure. The value is write-only provider state, so a change only takes effect after an `apply`, and supplying a non-empty list requires Terraform 1.11 or later.

> Note: this applies to the create-only `azapi_resource` writer, whose whole `body` is already silenced by `lifecycle.ignore_changes` after create. It is accepted for consistency with the sibling modules and for the create call itself; the day-2 writer is `azapi_update_resource`, which has no such argument.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for path in var.ignore_body_changes.network_express_route_gateways : length(trimspace(path)) > 0])
    error_message = "Every ignore_body_changes.network_express_route_gateways entry must be a non-empty body path in dot notation, for example \"properties.autoScaleConfiguration\"."
  }
}

variable "resource_types" {
  type = object({
    network_express_route_gateways = optional(string, "Microsoft.Network/expressRouteGateways@2025-07-01")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) The Azure resource type and API version used for each resource created by this module.

- `network_express_route_gateways` - (Optional) The type and API version of the ExpressRoute Gateway. Default `Microsoft.Network/expressRouteGateways@2025-07-01`.
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
    create = optional(string, "90m")
    read   = optional(string, "5m")
    update = optional(string, "90m")
    delete = optional(string, "90m")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Timeouts for the resource operations.

The defaults are `azurerm_express_route_gateway`'s OWN per-resource defaults, not a shared repository value: `express_route_gateway_resource.go` L39-L44 at `5782a75422c68a0d0804ac16d97dcaf3df5ee2fa` (v4.81.0) declares Create 90m, Read 5m, Update 90m, Delete 90m. An ExpressRoute Gateway routinely takes the better part of an hour to provision, so a shorter create budget would turn a normal deployment into a timeout.
DESCRIPTION
}
