locals {
  sidecar_virtual_networks_enabled          = { hub = true }
  private_dns_zones_enabled                 = { hub = true }
  hub_virtual_networks_resource_group_names = { hub = "rg-test" }
  default_names                             = { hub = { private_dns_resolver_name = "pdr-test" } }
}
