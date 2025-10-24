locals {
  p2s_gateway_vpn_server_configurations = { for flattened_object in flatten([
    for key, value in var.virtual_hubs : [
      for child_key, child_value in value.p2s_gateway_vpn_server_configurations : merge({
        composite_key   = "${key}-${child_key}"
        virtual_hub_key = key
      }, child_value)
    ]
  ]) : flattened_object.composite_key => flattened_object }
}
