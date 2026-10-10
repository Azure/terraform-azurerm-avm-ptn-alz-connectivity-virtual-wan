# The output shapes are unchanged from the AzureRM version: `resource` and `resource_id` are
# still LISTS built by iterating the resource, and `resource_object` is still a map keyed the
# same way with the same five attributes. What changes is the element type of `resource` -- an
# `azapi_resource` object rather than an `azurerm_express_route_gateway` one, so per-attribute
# reads such as `.scale_units` are no longer available on it. `resource_object` is the shape
# `modules/virtual-wan` actually consumes and it is preserved attribute for attribute.
#
# 🔴 NOTHING HERE READS `.output`. The computed-output rule: `azapi_resource.output` is Computed, so it goes
# unknown on any update and cascades `(known after apply)` into every consumer -- on this
# module that would make `express_route_gateway_id` unknown for every ExpressRoute connection
# and force a full PUT of each one. `scale_units` and `resource_group` are therefore projected
# from CONFIGURATION, and every child ID a consumer builds is built from `.id`, which stays
# known across an in-place update.
output "resource" {
  description = "Azure ExpressRoute Gateway resource name"
  value       = [for gateway in azapi_resource.this : gateway]
}

output "resource_id" {
  description = "Azure ExpressRoute Gateway resource ID"
  value       = var.expressroute_gateways != null ? [for gateway in azapi_resource.this : gateway.id] : []
}

output "resource_object" {
  description = "Azure ExpressRoute Gateway resource object"
  value = var.expressroute_gateways != null ? {
    for key, gateway in azapi_resource.this : key => {
      id       = gateway.id
      name     = gateway.name
      location = gateway.location
      # AzureRM exposed these as resource attributes. `resource_group_name` was only ever a
      # copy of the input (Read set it from the parsed ID, L233), and `scale_units` was read
      # back out of `autoScaleConfiguration.bounds.min` (L242-L246) -- which under AzAPI would
      # mean `.output`, so it is projected from configuration instead. The default matches
      # `variables.tf` and AzureRM's create literal.
      resource_group = local.expressroute_gateways[key].resource_group_name
      scale_units    = try(local.expressroute_gateways[key].scale_units, null) != null ? local.expressroute_gateways[key].scale_units : 1
    }
  } : {}
}
