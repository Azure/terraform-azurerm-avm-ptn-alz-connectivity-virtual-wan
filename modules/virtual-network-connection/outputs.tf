output "resource" {
  description = "Virtual Hub"
  value       = [for connection in azapi_resource.this : connection]
}

output "resource_id" {
  description = "Virtual Hub ID"
  value       = var.virtual_network_connections != null ? [for connection in azapi_resource.this : connection.id] : []
}

output "resource_object" {
  description = "Virtual Hub Object"
  value = var.virtual_network_connections != null ? {
    for key, connection in azapi_resource.this : key => {
      id   = connection.id
      name = connection.name
    }
  } : {}
}
