package Azure_Proactive_Resiliency_Library_v2
import rego.v1

exception contains rules if {
  rules = [
    "virtual_network_gateway_use_zone_redundant_sku",
    "public_ip_use_standard_sku_and_zone_redundant_ip",
    "deploy_azure_firewall_across_multiple_availability_zones"
  ]
}

# UK West has no availability zones, so the secondary hub's Standard bastion public IP cannot be zone redundant.
# Exempt use_standard_sku_and_zone_redundant_ip only while that address is the sole violator.
# Only managed resources count, matching the APRL rule (data sources have no body/sku).
# Self-contained on purpose: avm also loads this file in policy runs that do not include the APRL helpers.
_uk_west_bastion_ip_address := "module.test.module.bastion_public_ip[\"secondary\"].azapi_resource.this"

_uk_west_changes contains change if {
  change := input.resource_changes[_]
}

_uk_west_changes contains change if {
  change := input.plan.resource_changes[_]
}

_uk_west_public_ip_violations contains address if {
  change := _uk_west_changes[_]
  change.mode == "managed"
  change.type == "azapi_resource"
  regex.match("^Microsoft.Network/publicIPAddresses@", change.change.after.type)
  not _uk_west_zone_redundant_standard(change.change.after)
  address := change.address
}

_uk_west_zone_redundant_standard(after) if {
  after.body.sku.name == "Standard"
  count(after.body.zones) >= 2
}

_uk_west_exempt_addresses contains address if {
  change := _uk_west_changes[_]
  change.mode == "managed"
  change.address == _uk_west_bastion_ip_address
  change.change.after.location == "ukwest"
  change.change.after.body.sku.name == "Standard"
  address := change.address
}

exception contains rules if {
  count(_uk_west_public_ip_violations) > 0
  _uk_west_public_ip_violations == _uk_west_exempt_addresses
  rules = ["use_standard_sku_and_zone_redundant_ip"]
}
