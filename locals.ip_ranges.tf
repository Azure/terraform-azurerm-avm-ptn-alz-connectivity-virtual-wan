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

locals {
  virtual_network_subnet_default_ip_prefix_input = {
    for key, value in module.virtual_network_ip_prefixes : key => {
      address_space    = value.address_prefixes["sidecar"]
      address_prefixes = local.virtual_network_subnet_default_ip_prefix_sizes
    }
  }
}

locals {
  virtual_network_default_ip_prefixes = {
    for key, value in module.virtual_network_ip_prefixes : key => value.address_prefixes
  }
  virtual_network_subnet_default_ip_prefixes = {
    for key, value in module.virtual_network_subnet_ip_prefixes : key => value.address_prefixes
  }
}
