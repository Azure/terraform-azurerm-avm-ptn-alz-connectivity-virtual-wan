terraform {
  required_version = "~> 1.7"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
