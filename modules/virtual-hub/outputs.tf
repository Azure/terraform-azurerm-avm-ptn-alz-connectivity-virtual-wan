# 🔴 NONE of these outputs exposes `azapi_resource.this` WHOLE, and that is deliberate. The
# resource object carries the computed `output` attribute, and a computed `.output` in a module
# output is a day-2 blast-radius bug (confirmed three ways: unit test by
# reintroduction, plan against live state, and applied state). Every output below is a curated
# object built from attributes that are known at plan time.
#
# Child IDs are CONSTRUCTED from `.id` for the same reason — never read back out of a response.


output "default_route_table_id" {
  description = "Default Hub Route Table ID for each Virtual Hub, constructed from the hub's own resource ID so that it stays known at plan time."
  # `azurerm_virtual_hub` exposed this as a computed attribute, built the same way rather than read
  # from ARM: `virtual_hub_resource.go` L350-351,
  # `NewHubRouteTableID(subscription, resourceGroup, hub, "defaultRouteTable").ID()`.
  value = { for key, hub in azapi_resource.this : key => "${hub.id}/hubRouteTables/defaultRouteTable" }
}

output "location" {
  description = "Virtual Hub Location"
  value       = { for key, hub in azapi_resource.this : key => hub.location }
}

output "resource" {
  description = "Virtual Hub"
  value = {
    for key, hub in azapi_resource.this : key => {
      id             = hub.id
      name           = hub.name
      location       = hub.location
      parent_id      = hub.parent_id
      type           = hub.type
      tags           = hub.tags
      resource_group = var.virtual_hubs[key].resource_group_name
      sku            = var.virtual_hubs[key].sku
    }
  }
}

output "resource_group_name" {
  description = "Resource Group Name"
  # AzAPI addresses the hub by parent resource ID, so there is no `resource_group_name` attribute
  # to read back. The configured value is returned instead; it is the same string AzureRM stored,
  # because AzureRM set it from the parsed resource ID (`virtual_hub_resource.go` L348).
  value = { for key, hub in var.virtual_hubs : key => hub.resource_group_name }
}

output "resource_id" {
  description = "Virtual Hub ID"
  value       = { for key, hub in azapi_resource.this : key => hub.id }
}

output "resource_ids" {
  description = "Virtual Hub IDs"
  value       = { for key, hub in azapi_resource.this : key => hub.id }
}

output "resource_names" {
  description = "Virtual Hub Names"
  value       = { for key, hub in azapi_resource.this : key => hub.name }
}

output "resource_object" {
  description = "Virtual Hub Object"
  value = {
    for key, hub in azapi_resource.this : key => {
      id             = hub.id
      name           = hub.name
      location       = hub.location
      resource_group = var.virtual_hubs[key].resource_group_name
      # 🔴 Sourced from configuration, not from ARM. `azurerm_virtual_hub` set `sku` from the
      # readback (L358), so a hub left at `sku = null` reported whatever default ARM assigned.
      # Here a null stays null. Nothing in this repository consumes it; recorded as a known
      # difference rather than papered over.
      sku  = var.virtual_hubs[key].sku
      tags = hub.tags
    }
  }
}
