locals {
  virtual_hub_and_sidecar_default_ip_prefix_sizes = {
    virtual_hub = 22
    sidecar     = 22
  }
  virtual_network_subnet_default_ip_prefix_sizes = {
    bastion      = 26
    dns_resolver = 28
  }
}

locals {
  virtual_network_default_ip_prefix_input = {
    for key, value in var.virtual_hubs : key => {
      address_space    = value.default_hub_address_space == null ? "10.${index(keys(var.virtual_hubs), key)}.0.0/16" : value.default_hub_address_space
      address_prefixes = local.virtual_hub_and_sidecar_default_ip_prefix_sizes
    }
  }
}

module "virtual_network_ip_prefixes" {
  source   = "Azure/avm-utl-network-ip-addresses/azurerm"
  version  = "0.1.0"
  for_each = local.virtual_network_default_ip_prefix_input

  address_prefixes = each.value.address_prefixes
  address_space    = each.value.address_space
  enable_telemetry = var.enable_telemetry
}

locals {
  virtual_network_subnet_default_ip_prefix_input = {
    for key, value in module.virtual_network_ip_prefixes : key => {
      address_space    = value.address_prefixes["sidecar"]
      address_prefixes = local.virtual_network_subnet_default_ip_prefix_sizes
    }
  }
}

module "virtual_network_subnet_ip_prefixes" {
  source   = "Azure/avm-utl-network-ip-addresses/azurerm"
  version  = "0.1.0"
  for_each = local.virtual_network_subnet_default_ip_prefix_input

  address_prefixes = each.value.address_prefixes
  address_space    = each.value.address_space
  enable_telemetry = var.enable_telemetry
}

locals {
  virtual_network_default_ip_prefixes = {
    for key, value in module.virtual_network_ip_prefixes : key => value.address_prefixes
  }
  virtual_network_subnet_default_ip_prefixes = {
    for key, value in module.virtual_network_subnet_ip_prefixes : key => value.address_prefixes
  }
}