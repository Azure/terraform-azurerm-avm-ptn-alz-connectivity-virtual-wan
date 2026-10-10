variable "ignore_body_changes" {
  type = object({
    network_vpn_gateways = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Body property paths whose changes the `azapi` provider ignores after creation, letting an out-of-band controller own those properties without producing perpetual `terraform plan` drift.

- `network_vpn_gateways` - (Optional) Ignored body paths for the S2S VPN Gateway, in dot notation relative to the request body, for example `["properties.vpnGatewayScaleUnit"]`. Default `[]`.

While a path is ignored, configuration changes at that path are no longer sent to Azure. The value is write-only provider state, so a change only takes effect after an `apply`, and supplying a non-empty list requires Terraform 1.11 or later.

> Note: this module pins the whole request body with `lifecycle.ignore_changes` after creation, so this setting only affects the initial create request. Day-2 writes go through a separate merge writer that has no equivalent setting.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for path in var.ignore_body_changes.network_vpn_gateways : length(trimspace(path)) > 0])
    error_message = "Every ignore_body_changes.network_vpn_gateways entry must be a non-empty body path in dot notation, for example \"properties.vpnGatewayScaleUnit\"."
  }
}

variable "resource_types" {
  type = object({
    network_vpn_gateways = optional(string, "Microsoft.Network/vpnGateways@2025-07-01")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) The Azure resource type and API version used for each resource created by this module.

- `network_vpn_gateways` - (Optional) The type and API version of the S2S VPN Gateway. Default `Microsoft.Network/vpnGateways@2025-07-01`.
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

The defaults are AzureRM's own per-resource timeouts for `azurerm_vpn_gateway`, not a module-wide convention: `vpn_gateway_resource.go` L41-L46 sets Create 90m, Read 5m, Update 90m and Delete 90m. A vpnGateway commonly takes the better part of an hour to provision, so the shorter 30m default used by this repo's other submodules would be a behaviour regression on migration.
DESCRIPTION
}

variable "vpn_gateways" {
  type = map(object({
    name                                  = string
    location                              = string
    resource_group_name                   = string
    virtual_hub_id                        = string
    tags                                  = optional(map(string))
    bgp_route_translation_for_nat_enabled = optional(bool)
    bgp_settings = optional(object({
      instance_0_bgp_peering_address = optional(object({
        custom_ips = list(string)
      }))
      instance_1_bgp_peering_address = optional(object({
        custom_ips = list(string)
      }))
      peer_weight = number
      asn         = number
    }))
    routing_preference = optional(string)
    scale_unit         = optional(number)
  }))
  default     = {}
  description = <<DESCRIPTION
  Map of objects for S2S VPN Gateways to deploy into the Virtual WAN Virtual Hubs that have been defined in the variable `virtual_hubs`.

  The key is deliberately arbitrary to avoid issues with known after apply values. The value is an object, of which there can be multiple in the map:

  - `name`: Name for the S2S VPN Gateway resource.
  - `virtual_hub_key`: The arbitrary key specified in the map of objects variable called `virtual_hubs` for the object specifying the Virtual Hub you wish to deploy this S2S VPN Gateway into.
  - `tags`: Optional tags to apply to the S2S VPN Gateway resource.
  - `bgp_route_translation_for_nat_enabled`: Optional boolean to enable BGP route translation for NAT.
  - `bgp_settings`: Optional BGP settings object for the S2S VPN Gateway, which includes:
    - `instance_0_bgp_peering_address`: Optional object for the instance 0 BGP peering address, which includes:
      - `custom_ips`: List of custom IPs for the instance 0 BGP peering address.
    - `instance_1_bgp_peering_address`: Optional object for the instance 1 BGP peering address, which includes:
      - `custom_ips`: List of custom IPs for the instance 1 BGP peering address.
    - `peer_weight`: BGP peer weight for the S2S VPN Gateway.
    - `asn`: BGP ASN for the BGP Speaker.
  - `routing_preference`: Optional Azure routing preference lets you to choose how your traffic routes between Azure and the internet. You can choose to route traffic either via the Microsoft network (default value, `Microsoft Network`), or via the ISP network (public internet, set to `Internet`). More context of the configuration can be found in the Microsoft Docs to create a VPN Gateway. Defaults to `Microsoft Network` if not set. Changing this forces a new resource to be created.
  - `scale_unit`: Optional number of scale units for the S2S VPN Gateway. See https://learn.microsoft.com/azure/virtual-wan/gateway-settings#s2s for more information on scale units.

  > Note: There can be multiple objects in this map, one for each S2S VPN Gateway you wish to deploy into the Virtual WAN Virtual Hubs that have been defined in the variable `virtual_hubs`.

  DESCRIPTION

  validation {
    # TFNFR38 (Severity-MUST): a LITERAL type through `parse_resource_id`, never a regex.
    # `main.tf` rebuilds `parent_id` via `split(...)[2]`, so the ID must stay RG-scoped;
    # `parse` alone is looser and admits other scopes -- see `MIGRATION-DEVIATIONS.md`.
    condition = alltrue([
      for gateway in(var.vpn_gateways != null ? values(var.vpn_gateways) : []) :
      can(provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", gateway.virtual_hub_id)) &&
      try(provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", gateway.virtual_hub_id).resource_group_name, "") != ""
    ])
    error_message = "Every `vpn_gateways` entry must set `virtual_hub_id` to a resource-group-scoped `Microsoft.Network/virtualHubs` resource ID."
  }
  validation {
    # AzureRM's `validation.StringInSlice` on `routing_preference`, L72-L75. Preserved
    # because `main.tf` turns this string into the BOOLEAN `isRoutingPreferenceInternet`
    # by comparing it to "Internet" (L258) -- any other misspelling would silently mean
    # "Microsoft Network" rather than failing.
    condition = alltrue([
      for gateway in(var.vpn_gateways != null ? values(var.vpn_gateways) : []) :
      contains(["Microsoft Network", "Internet"], gateway.routing_preference)
      if try(gateway.routing_preference, null) != null
    ])
    error_message = "`routing_preference` must be either \"Microsoft Network\" or \"Internet\"."
  }
  validation {
    # AzureRM's `validation.IntAtLeast(0)` on `scale_unit`, L195.
    condition = alltrue([
      for gateway in(var.vpn_gateways != null ? values(var.vpn_gateways) : []) :
      gateway.scale_unit >= 0
      if try(gateway.scale_unit, null) != null
    ])
    error_message = "`scale_unit` must be greater than or equal to 0."
  }
}
