# The output shapes are unchanged from the AzureRM version: both are LISTS built by iterating
# the resource, so the ordering and cardinality a consumer sees are the same. What changes is
# the element type of `resource` -- an `azapi_resource` object rather than an
# `azurerm_express_route_connection` one, so per-attribute reads such as `.routing_weight` are
# no longer available. Nothing inside this repository reads them; `modules/virtual-wan` uses
# this module for its side effect only.
output "resource" {
  description = "Azure ExpressRoute Connection resource"
  value       = [for connection in azapi_resource.this : connection]
}

output "resource_id" {
  description = "Azure ExpressRoute Connection resource ID"
  value       = var.er_circuit_connections != null ? [for connection in azapi_resource.this : connection.id] : []
}
