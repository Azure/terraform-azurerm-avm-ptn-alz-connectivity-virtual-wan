locals {
  vpn_site_connections = { for flattened_object in flatten([
    for key, value in var.virtual_hubs : [
      for child_key, child_value in value.vpn_site_connections : merge({
        composite_key   = "${key}-${child_key}"
        vpn_gateway_key = key
      }, child_value)
    ]
  ]) : flattened_object.composite_key => flattened_object }
}
