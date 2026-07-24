terraform {
  required_version = "~> 1.9"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_string" "suffix" {
  length  = 4
  numeric = true
  special = false
  upper   = false
}

locals {
  actual_dpd_timeout_seconds = try(data.azapi_resource.vpn_gateway_connection.output.dpd_timeout_seconds, null)
  common_tags = {
    created_by  = "terraform"
    environment = "test"
    project     = "Azure Landing Zones"
  }
  expected_dpd_timeout_seconds = 30
  location                     = "eastus"
  resource_group_name          = "rg-vwan-dpd-${random_string.suffix.result}"
  virtual_hub_name             = "vhub-dpd-${random_string.suffix.result}"
  virtual_wan_name             = "vwan-dpd-${random_string.suffix.result}"
  vpn_connection_name          = "vcn-dpd-${random_string.suffix.result}"
  vpn_gateway_name             = "vpng-dpd-${random_string.suffix.result}"
  vpn_link_name                = "link-dpd-${random_string.suffix.result}"
  vpn_site_name                = "site-dpd-${random_string.suffix.result}"
}

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.2.0"

  location         = local.location
  name             = local.resource_group_name
  enable_telemetry = false
  tags             = local.common_tags
}

# This is the module call.
module "test" {
  source = "../../"

  enable_telemetry = false
  tags             = local.common_tags
  virtual_hubs = {
    primary = {
      location          = local.location
      default_parent_id = module.resource_group.resource_id

      enabled_resources = {
        firewall                              = false
        firewall_policy                       = false
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = true
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }

      hub = {
        name           = local.virtual_hub_name
        address_prefix = "10.100.0.0/24"
      }

      virtual_network_gateways = {
        vpn = {
          name       = local.vpn_gateway_name
          scale_unit = 1
        }
      }

      vpn_sites = {
        site1 = {
          name          = local.vpn_site_name
          address_cidrs = ["192.168.100.0/24"]
          links = [
            {
              name          = local.vpn_link_name
              ip_address    = "203.0.113.10"
              provider_name = "Example"
              speed_in_mbps = 50
            }
          ]
        }
      }

      vpn_site_connections = {
        connection1 = {
          name                = local.vpn_connection_name
          remote_vpn_site_key = "primary-site1"
          vpn_links = [
            {
              name                 = local.vpn_link_name
              vpn_site_key         = "primary-site1"
              vpn_site_link_number = 0
              dpd_timeout_seconds  = local.expected_dpd_timeout_seconds
            }
          ]
        }
      }
    }
  }
  virtual_wan_settings = {
    enabled_resources = {
      ddos_protection_plan = false
    }
    virtual_wan = {
      name = local.virtual_wan_name
    }
  }
}

# Read the deployed child resource directly from Azure so the example fails if
# dpd_timeout_seconds is accepted by the caller but dropped by any module layer.
data "azapi_resource" "vpn_gateway_connection" {
  name      = local.vpn_connection_name
  parent_id = "${module.resource_group.resource_id}/providers/Microsoft.Network/vpnGateways/${local.vpn_gateway_name}"
  type      = "Microsoft.Network/vpnGateways/vpnConnections@2025-01-01"

  response_export_values = {
    dpd_timeout_seconds = "properties.vpnLinkConnections[0].properties.dpdTimeoutSeconds"
  }

  depends_on = [module.test]
}
