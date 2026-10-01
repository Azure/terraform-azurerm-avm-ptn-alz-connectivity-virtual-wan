terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}

variable "name" {
  type = string
}

resource "azapi_resource" "this" {
  type                   = "Microsoft.Resources/resourceGroups@2022-09-01"
  name                   = var.name
  parent_id              = "/subscriptions/00000000-0000-0000-0000-000000000001"
  location               = "eastus"
  body                   = {}
  response_export_values = []
}

output "resource_id" {
  value = azapi_resource.this.id
}
