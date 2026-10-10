# 🔴 EVERY OUTPUT HERE IS BUILT FROM CONFIGURATION AND FROM `.id`, NEVER FROM A COMPUTED
# `.output`. That is the computed-output rule, and it is a regression this repo has already measured
# once (see `modules/site-to-site-vpn-site/outputs.tf`): a computed `output` goes UNKNOWN
# on any update, which takes every downstream consumer unknown with it and turns an
# in-place edit into a full PUT of unrelated resources. AzureRM kept these values known
# across an update, so reading them back would be a migration regression, not a quirk.
#
# Both writers set `response_export_values = []` -- the empty list AVM spec TFFR4
# (Severity-MUST, Class-Pattern) requires, paired on the full writer with an
# `ignore_changes` entry (see `main.tf`). `[]` exports nothing, so there is no `.output`
# content to read even if one were wanted, and a future non-empty list would need its own
# migration because `ignore_changes` pins the prior value.
locals {
  # 🔴 THE IP CONFIGURATION IDs ARE LITERALS, NOT READ-BACK VALUES, AND THAT IS CORRECT.
  #
  # Despite the name, `ip_configuration_id` on a BGP peering address is NOT an ARM resource
  # ID. AzureRM's own documentation calls it "the pre-defined id of VPN Gateway IP
  # Configuration" (`website/docs/r/vpn_gateway.html.markdown` L116), and it is the value
  # `azurerm_vpn_gateway_connection` expects in
  # `vpn_links.custom_bgp_address.ip_configuration_id`.
  #
  # ✅ MEASURED against live ARM: a provisioned vpnGateway returns exactly two
  # `bgpSettings.bgpPeeringAddresses` entries whose `ipconfigurationId` values are the
  # literal strings "Instance0" and "Instance1", in that order --
  # a captured live 2025-07-01 response. They are assigned by ARM at
  # create and are the same on every gateway; they are not addressable, not unique and
  # cannot be chosen.
  #
  # So the parent module's `module.vpn_gateway.ip_configuration_ids[key][instance]` lookup
  # resolves at PLAN time rather than going unknown on every gateway change. The map is
  # keyed off `azapi_resource.this` so a gateway that is not being created does not appear.
  vpn_gateway_ip_configuration_ids = {
    for key, gateway in azapi_resource.this : key => ["Instance0", "Instance1"]
  }

  # AzureRM's `flattenVPNGatewayBGPSettings` (L462-L499) shape, rebuilt from configuration.
  # An empty list when `bgp_settings` is unset reproduces L463-L465 returning `[]`.
  #
  # 🔴 DEVIATION -- READ-ONLY FIELDS ARE NULL HERE, NOT POPULATED. AzureRM's `bgp_settings`
  # was Optional+COMPUTED (L86-L87), so its Read surfaced ARM's own values even when the
  # consumer configured nothing. Four fields can only come from a readback and therefore
  # cannot be reproduced without a NON-EMPTY `response_export_values`, which this module
  # declines to set -- the attribute is declared as `[]` for TFFR4, and the computed-output rule rules a
  # computed `.output` out of a module output:
  #   bgp_peering_address                     (flatten L472-L475, from BgpPeeringAddress)
  #   instance_*_bgp_peering_address.default_ips  (L511, from DefaultBgpIPAddresses)
  #   instance_*_bgp_peering_address.tunnel_ips   (L512, from TunnelIPAddresses)
  #   the whole block when `bgp_settings` was left unset, where AzureRM returned ARM's
  #   default asn 65515 / peerWeight 0 and this returns `[]`
  # A consumer reading those specific fields gets null/`[]` where AzureRM gave a value.
  # Nothing in this repo reads them; flagged for `MIGRATION-DEVIATIONS.md`.
  vpn_gateway_bgp_settings = {
    for key, value in local.vpn_gateways : key => [
      for settings in(try(value.bgp_settings, null) != null ? [value.bgp_settings] : []) : {
        asn                 = settings.asn
        peer_weight         = settings.peer_weight
        bgp_peering_address = null
        instance_0_bgp_peering_address = [
          for address in(try(settings.instance_0_bgp_peering_address, null) != null ? [settings.instance_0_bgp_peering_address] : []) : {
            custom_ips          = address.custom_ips
            ip_configuration_id = local.vpn_gateway_ip_configuration_ids[key][0]
            default_ips         = null
            tunnel_ips          = null
          }
        ]
        instance_1_bgp_peering_address = [
          for address in(try(settings.instance_1_bgp_peering_address, null) != null ? [settings.instance_1_bgp_peering_address] : []) : {
            custom_ips          = address.custom_ips
            ip_configuration_id = local.vpn_gateway_ip_configuration_ids[key][1]
            default_ips         = null
            tunnel_ips          = null
          }
        ]
      }
    ]
  }
}

output "bgp_settings" {
  description = "Azure VPN Gateway object"
  value       = var.vpn_gateways != null ? [for key, gateway in azapi_resource.this : local.vpn_gateway_bgp_settings[key]] : null
}

output "id" {
  description = "Azure VPN Gateway ID"
  value       = var.vpn_gateways != null ? [for gateway in azapi_resource.this : gateway.id] : null
}

output "ip_configuration_ids" {
  description = "Azure VPN Gateway BGP Peering Address IP Configuration ID"
  value       = var.vpn_gateways != null ? local.vpn_gateway_ip_configuration_ids : null
}

# 🔴 DEVIATION -- THE ELEMENT TYPE OF THIS OUTPUT CHANGES. It used to be an
# `azurerm_vpn_gateway` object (`bgp_settings`, `scale_unit`, `ip_configuration`, ...) and
# is now an `azapi_resource` object (`id`, `name`, `location`, `parent_id`, `type`,
# `body`, `tags`, ...). Anything outside this module reading a named attribute off it has
# to be updated. This is the same class of break as an earlier deviation and
# is unavoidable when the underlying resource type changes. The two attributes this repo
# actually consumes -- `.id` and `.name` -- exist on both, so `resource_object`, `id`,
# `resource_id`, `vpn_gateway_id` and `vpn_gateway_name` are unaffected.
output "resource" {
  description = "Azure VPN Gateway"
  value       = var.vpn_gateways == null ? null : [for gateway in azapi_resource.this : gateway]
}

output "resource_id" {
  description = "Azure VPN Gateway ID"
  value       = var.vpn_gateways != null ? [for gateway in azapi_resource.this : gateway.id] : null
}

output "resource_object" {
  description = "Azure VPN Gateway object"
  value = var.vpn_gateways != null ? { for key, gateway in azapi_resource.this : key => {
    id           = gateway.id
    name         = gateway.name
    bgp_settings = local.vpn_gateway_bgp_settings[key]
  } } : null
}

output "vpn_gateway_id" {
  description = "Azure VPN Gateway resource ID"
  value       = var.vpn_gateways != null ? [for gateway in azapi_resource.this : gateway.id] : null
}

output "vpn_gateway_name" {
  description = "Azure VPN Gateway resource name"
  value       = var.vpn_gateways != null ? [for gateway in azapi_resource.this : gateway.name] : null
}
