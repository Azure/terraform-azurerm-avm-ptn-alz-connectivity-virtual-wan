variable "ignore_body_changes" {
  type = object({
    network_virtual_hubs_hub_virtual_network_connections = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Body property paths whose changes the `azapi` provider ignores after creation, letting an out-of-band controller own those properties without producing perpetual `terraform plan` drift.

- `network_virtual_hubs_hub_virtual_network_connections` - (Optional) Ignored body paths for the Virtual Network connection, in dot notation relative to the request body, for example `["properties.routingConfiguration"]`. Default `[]`.

While a path is ignored, configuration changes at that path are no longer sent to Azure. The value is write-only provider state, so a change only takes effect after an `apply`, and supplying a non-empty list requires Terraform 1.11 or later.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for path in var.ignore_body_changes.network_virtual_hubs_hub_virtual_network_connections : length(trimspace(path)) > 0])
    error_message = "Every ignore_body_changes.network_virtual_hubs_hub_virtual_network_connections entry must be a non-empty body path in dot notation, for example \"properties.routingConfiguration\"."
  }
}

variable "resource_types" {
  type = object({
    network_virtual_hubs_hub_virtual_network_connections = optional(string, "Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2025-07-01")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) The Azure resource type and API version used for each resource created by this module.

- `network_virtual_hubs_hub_virtual_network_connections` - (Optional) The type and API version of the Virtual Network connection. Default `Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2025-07-01`.
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
(Optional) Timeouts for the resource operations.

Any attribute left unset falls back, per resource, to the timeout default of the `azurerm` resource this module replaced, rather than to a single blanket value. For this module that is `azurerm_virtual_hub_connection`, whose create/update/delete default was 60 minutes. The fallbacks and their source lines are in `local.timeouts` in `main.tf`. See "Design notes -> Per-resource timeout defaults" in `_header.md`.
DESCRIPTION
}

variable "virtual_network_connections" {
  type = map(object({
    name                      = string
    virtual_hub_id            = string
    remote_virtual_network_id = string
    internet_security_enabled = optional(bool, false)
    routing = optional(object({
      associated_route_table_id = string
      propagated_route_table = optional(object({
        route_table_ids = optional(list(string), [])
        labels          = optional(list(string), [])
      }))
      static_vnet_route = optional(object({
        name                = optional(string)
        address_prefixes    = optional(list(string), [])
        next_hop_ip_address = optional(string)
      }))
    }))
  }))
  default     = {}
  description = <<DESCRIPTION
  Map of objects for Virtual Network connections to connect Virtual Networks to the Virtual WAN Virtual Hubs that have been defined in the variable `virtual_hubs`.

  The key is deliberately arbitrary to avoid issues with known after apply values. The value is an object, of which there can be multiple in the map:

  - `name`: Name for the Virtual Network connection.
  - `virtual_hub_id`: The Resource ID of the Virtual Hub you wish to connect the Virtual Network to.
  - `remote_virtual_network_id`: The Resource ID of the Virtual Network you wish to connect to the Virtual Hub.
  - `internet_security_enabled`: Optional boolean to enable internet security for the connection, e.g. allow `0.0.0.0/0` route to be propagated to this connection.
  - `routing`: Optional routing configuration object for the connection, which includes:
    - `associated_route_table_id`: The resource ID of the Virtual Hub Route Table you wish to associate with this connection.
    - `propagated_route_table`: Optional configuration objection of propagated route table configuration, which includes:
      - `route_table_ids`: Optional list of resource IDs of the Virtual Hub Route Tables you wish to propagate this connections routes to.
      - `labels`: Optional list of labels you wish to propagate this connections routes to.
    - `static_vnet_route`: Optional configuration object for static VNet route configuration, which includes:
      - `name`: Optional name for the static VNet route.
      - `address_prefixes`: Optional list of address prefixes for the static VNet route.
      - `next_hop_ip_address`: Optional next hop IP address for the static VNet route.

  > Note: There can be multiple objects in this map, one for each Virtual Network connection you wish to connect to the Virtual WAN Virtual Hubs that have been defined in the variable `virtual_hubs`.

  DESCRIPTION
  nullable    = false
}
