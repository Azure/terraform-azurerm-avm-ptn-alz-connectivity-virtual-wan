variable "vpn_sites" {
  type = map(object({
    location            = string
    name                = string
    resource_group_name = string
    virtual_wan_id      = string
    address_cidrs       = optional(list(string))
    device_model        = optional(string)
    device_vendor       = optional(string)
    tags                = optional(map(string))
    links = list(object({
      name = string
      bgp = optional(object({
        asn             = number
        peering_address = string
      }))
      fqdn          = optional(string)
      ip_address    = optional(string)
      provider_name = optional(string)
      speed_in_mbps = optional(number)
    }))
    o365_policy = optional(object({
      traffic_category = object({
        allow_endpoint_enabled    = optional(bool)
        default_endpoint_enabled  = optional(bool)
        optimize_endpoint_enabled = optional(bool)
      })
    }))
  }))
  description = <<DESCRIPTION
  Map of objects for VPN Sites to deploy into the Virtual WAN Virtual Hubs that have been defined in the variable `virtual_hubs`.

  The key is deliberately arbitrary to avoid issues with known after apply values. The value is an object, of which there can be multiple in the map:

  - `name`: Name for the VPN Site resource.
  - `virtual_hub_id`: Virtual hub ID.
  - `virtual_wan_id`: Virtual WAN ID.
  - `links`: List of links for the VPN Site, which includes:
    - `name`: Name for the link.
    - `bgp`: Optional BGP object for the link, which includes:
      - `asn`: ASN for the BGP.
      - `peering_address`: Peering address for the BGP.
    - `fqdn`: Optional FQDN for the link.
    - `ip_address`: Optional IP address for the link.
    - `provider_name`: Optional provider name for the link.
    - `speed_in_mbps`: Optional speed in Mbps for the link.
  - `address_cidrs`: Optional list of address CIDRs for the VPN Site. Must be set if `links.bgp` is not set.
  - `device_model`: Optional device model for the VPN Site.
  - `device_vendor`: Optional device vendor for the VPN Site.
  - `o365_policy`: Optional O365 policy object for the VPN Site, which includes:
    - `traffic_category`: Optional traffic category object for the O365 policy, which includes:
      - `allow_endpoint_enabled`: Optional boolean. Is allow endpoint enabled? The `Allow` endpoint is required for connectivity to specific O365 services and features, but are not as sensitive to network performance and latency as other endpoint types.
      - `default_endpoint_enabled`: Optional boolean. Is default endpoint enabled? The `Default` endpoint represents O365 services and dependencies that do not require any optimization, and can be treated by customer networks as normal Internet bound traffic.
      - `optimize_endpoint_enabled`: Optional boolean. Is optimize endpoint enabled? The `Optimize` endpoint is required for connectivity to every O365 service and represents the O365 scenario that is the most sensitive to network performance, latency, and availability.
  - `tags`: Optional tags to apply to the VPN Site resource.

  > Note: There can be multiple objects in this map, one for each VPN Site you wish to deploy into the Virtual WAN Virtual Hubs that have been defined in the variable `virtual_hubs`.

  DESCRIPTION

  validation {
    # TFNFR38 (Severity-MUST): a LITERAL type through `parse_resource_id`, never a regex.
    # `main.tf` rebuilds `parent_id` via `split(...)[2]`, so the ID must stay RG-scoped;
    # `parse` alone is looser and admits other scopes -- see `MIGRATION-DEVIATIONS.md`.
    condition = alltrue([
      for site in(var.vpn_sites != null ? values(var.vpn_sites) : []) :
      can(provider::azapi::parse_resource_id("Microsoft.Network/virtualWans", site.virtual_wan_id)) &&
      try(provider::azapi::parse_resource_id("Microsoft.Network/virtualWans", site.virtual_wan_id).resource_group_name, "") != ""
    ])
    error_message = "Every `vpn_sites` entry must set `virtual_wan_id` to a resource-group-scoped `Microsoft.Network/virtualWans` resource ID."
  }
}

variable "ignore_body_changes" {
  type = object({
    network_vpn_sites = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) Body property paths whose changes the `azapi` provider ignores after creation, letting an out-of-band controller own those properties without producing perpetual `terraform plan` drift.

- `network_vpn_sites` - (Optional) Ignored body paths for the VPN Site, in dot notation relative to the request body, for example `["properties.vpnSiteLinks"]`. Default `[]`.

While a path is ignored, configuration changes at that path are no longer sent to Azure. The value is write-only provider state, so a change only takes effect after an `apply`, and supplying a non-empty list requires Terraform 1.11 or later.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for path in var.ignore_body_changes.network_vpn_sites : length(trimspace(path)) > 0])
    error_message = "Every ignore_body_changes.network_vpn_sites entry must be a non-empty body path in dot notation, for example \"properties.vpnSiteLinks\"."
  }
}

variable "resource_types" {
  type = object({
    network_vpn_sites = optional(string, "Microsoft.Network/vpnSites@2025-07-01")
  })
  default     = {}
  description = <<DESCRIPTION
(Optional) The Azure resource type and API version used for each resource created by this module.

- `network_vpn_sites` - (Optional) The type and API version of the VPN Site. Default `Microsoft.Network/vpnSites@2025-07-01`.
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

Any attribute left unset falls back, per resource, to the timeout default of the `azurerm` resource this module replaced, rather than to a single blanket value. The fallbacks and their source lines are in `local.timeouts` in `main.tf`. See "Design notes -> Per-resource timeout defaults" in `_header.md`.
DESCRIPTION
}
