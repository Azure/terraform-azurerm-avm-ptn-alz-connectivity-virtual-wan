terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

variable "firewall_enabled" {
  type    = bool
  default = true
}

module "resource_groups" {
  source = "./resource-group"

  name = "rg-fresh"
}

resource "azapi_resource" "public_ips" {
  for_each = toset(["primary", "secondary"])

  type      = "Microsoft.Network/publicIPAddresses@2024-10-01"
  name      = "pip-${each.key}"
  parent_id = module.resource_groups.resource_id
  location  = "eastus"
  body = {
    sku = { name = "Standard", tier = "Regional" }
    properties = {
      publicIPAllocationMethod = "Static"
      publicIPAddressVersion   = "IPv4"
    }
  }
  response_export_values = []
}

locals {
  resource_groups = { resource_groups = module.resource_groups }
  virtual_hubs = (merge({
    vhubs = {
      hub = {
        location          = "eastus"
        default_parent_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-fresh"
        enabled_resources = {
          firewall                              = var.firewall_enabled, firewall_policy = false, bastion = false
          virtual_network_gateway_express_route = false, virtual_network_gateway_vpn = false
          private_dns_zones                     = false, private_dns_resolver = false, sidecar_virtual_network = false
        }
        firewall = {
          name               = "fw-fresh"
          firewall_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-fresh/providers/Microsoft.Network/firewallPolicies/policy-test"
          ip_configurations = {
            for key, ip in azapi_resource.public_ips : key => {
              name                 = "explicit-${key}"
              public_ip_address_id = ip.id
            }
          }
        }
      }
    }
  }, local.resource_groups)).vhubs
  virtual_wan_settings = merge({ enabled_resources = { ddos_protection_plan = false } }, local.resource_groups)
}

module "virtual_wan" {
  source = "../../../.."

  enable_telemetry     = false
  virtual_hubs         = local.virtual_hubs
  virtual_wan_settings = local.virtual_wan_settings
}

output "firewall_public_ip_addresses" {
  value = module.virtual_wan.firewall_public_ip_addresses
}

output "public_ip_ids" {
  value = { for key, ip in azapi_resource.public_ips : key => ip.id }
}

output "resource_group_id" {
  value = module.resource_groups.resource_id
}
