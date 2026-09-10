output "route_map_resource_ids_by_name" {
  description = "A map of route map name to resource ID."
  value       = module.vwan.route_map_resource_ids_by_name
}

output "route_map_resources" {
  description = "The route map resource objects, keyed by the map key."
  value       = module.vwan.route_map_resources
}

output "vwan_outputs" {
  description = "The Virtual WAN module outputs."
  value       = module.vwan
}
