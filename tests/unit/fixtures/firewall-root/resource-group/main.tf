terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}

resource "azapi_resource" "this" {
  location               = "eastus"
  name                   = var.name
  parent_id              = "/subscriptions/00000000-0000-0000-0000-000000000001"
  type                   = "Microsoft.Resources/resourceGroups@2022-09-01"
  body                   = {}
  response_export_values = []
}

output "resource_id" {
  value = azapi_resource.this.id
}
