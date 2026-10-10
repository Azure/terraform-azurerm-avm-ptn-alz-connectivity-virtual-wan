locals {
  # AzureRM exposed per-link IDs as computed attributes on the `link` blocks. AzAPI returns
  # them inside the response, so they are projected back into the same shape here.
  #
  # 🔴 The parent module indexes this list POSITIONALLY:
  #     module.vpn_site.resource_object[key].links[n].id
  # so the order must match `var.vpn_sites[key].links` exactly. The list is built from the
  # CONFIGURED links, in configured order, so that contract holds by construction.
  #
  # 🔴 THE ID IS CONSTRUCTED, NOT READ BACK, AND THAT IS LOAD-BEARING (observed in testing).
  # This used to read the ID out of `azapi_resource.this[key].output`, matching by name. That
  # was correct but UNKNOWN AT PLAN TIME on any update: `output` is computed, so changing
  # anything on the site -- even a tag -- made every link ID unknown. Downstream, every
  # `vpn_site_link_id` went unknown, so each connection's whole
  # `properties.vpnLinkConnections` list became `(known after apply)` and azapi issued a FULL
  # PUT of every VPN connection on that site. AzureRM kept the link IDs known across an
  # in-place update, so this was a REGRESSION introduced by the migration, not a quirk of the
  # test fixture. It was caught by an earlier plan.
  #
  # `.id` is a known, stable attribute on update, so building the child ID from it keeps the
  # whole downstream chain known. The format is verified against live ARM (readback):
  #   .../vpnSites/vpnsite-c1  +  /vpnSiteLinks/link-a
  # Trade-off accepted: a link ARM somehow failed to create would previously surface as a
  # `null` ID and now surfaces as a constructed one. The links are sent in the same PUT as the
  # site, so ARM cannot return the site without them; a wrong ID here would fail loudly at the
  # connection instead of silently propagating a null.
  vpn_site_links = {
    for key, value in local.vpn_sites : key => [
      for link in(value.links != null ? value.links : []) : {
        id            = "${azapi_resource.this[key].id}/vpnSiteLinks/${link.name}"
        name          = link.name
        bgp           = try(link.bgp, null) != null ? [{ asn = link.bgp.asn, peering_address = link.bgp.peering_address }] : []
        fqdn          = try(link.fqdn, null)
        ip_address    = try(link.ip_address, null)
        provider_name = try(link.provider_name, null)
        speed_in_mbps = try(link.speed_in_mbps, null)
      }
    ]
  }
}

output "links" {
  description = "Azure VPN Site links"
  value       = var.vpn_sites != null ? local.vpn_site_links : {}
}

output "resource" {
  description = "Azure VPN Site resource"
  value       = var.vpn_sites != null ? { for k, v in azapi_resource.this : k => v } : {}
}

output "resource_id" {
  description = "Azure VPN Site ID"
  value       = var.vpn_sites != null ? { for k, v in azapi_resource.this : k => v.id } : {}
}

output "resource_object" {
  description = "Azure VPN Site object"
  value = var.vpn_sites != null ? { for k, v in azapi_resource.this : k => {
    location       = v.location
    name           = v.name
    id             = v.id
    resource_group = local.vpn_sites[k].resource_group_name
    virtual_wan_id = local.vpn_sites[k].virtual_wan_id
    address_cidrs  = try(local.vpn_sites[k].address_cidrs, null)
    device_model   = try(local.vpn_sites[k].device_model, null)
    device_vendor  = try(local.vpn_sites[k].device_vendor, null)
    tags           = try(v.tags, {})
    links          = local.vpn_site_links[k]
    o365_policy    = try(local.vpn_sites[k].o365_policy, null) != null ? [local.vpn_sites[k].o365_policy] : []
  } } : {}
}

output "vpn_site_name" {
  description = "Azure VPN Site names"
  value       = var.vpn_sites != null ? keys(azapi_resource.this) : []
}
