locals {
  private_traffic_routes = {
    for flattened_object in flatten([
      for virtual_hub_key, virtual_hub_value in var.virtual_hubs : [
        for route_key, route_value in virtual_hub_value.private_traffic_routes : merge({
          composite_key   = "${virtual_hub_key}-${route_key}"
          virtual_hub_key = virtual_hub_key
        }, route_value)
      ]
    ]) : flattened_object.composite_key => flattened_object
  }
}