locals {
  express_route_circuit_connections = { for flattened_object in flatten([
    for key, value in var.virtual_hubs : [
      for child_key, child_value in value.express_route_circuit_connections : merge({
        composite_key             = "${key}-${child_key}"
        express_route_gateway_key = key
      }, child_value)
    ]
  ]) : flattened_object.composite_key => flattened_object }
}
