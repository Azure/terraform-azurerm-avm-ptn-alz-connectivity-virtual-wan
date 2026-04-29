output "name" {
  description = "The name of the route map."
  value       = azapi_resource.route_map.name
}

output "resource" {
  description = "The full route map resource object."
  value       = azapi_resource.route_map
}

output "resource_id" {
  description = "The resource ID of the route map."
  value       = azapi_resource.route_map.id
}
