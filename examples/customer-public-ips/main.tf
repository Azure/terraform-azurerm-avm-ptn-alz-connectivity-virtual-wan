data "azapi_client_config" "current" {}

resource "azapi_resource" "resource_group" {
  location               = var.location
  name                   = var.resource_group_name
  parent_id              = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  type                   = var.resource_types.resources_resource_groups
  body                   = {}
  ignore_body_changes    = length(var.ignore_body_changes.resources_resource_groups) > 0 ? var.ignore_body_changes.resources_resource_groups : null
  response_export_values = []
  retry                  = var.retry
  tags                   = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}

resource "azapi_resource" "public_ips" {
  for_each = var.public_ip_names

  location  = var.location
  name      = each.value
  parent_id = azapi_resource.resource_group.id
  type      = var.resource_types.network_public_ip_addresses
  body = {
    sku   = { name = "Standard", tier = "Regional" }
    zones = [for zone in var.zones : tostring(zone)]
    properties = {
      publicIPAllocationMethod = "Static"
      publicIPAddressVersion   = "IPv4"
    }
  }
  ignore_body_changes    = length(var.ignore_body_changes.network_public_ip_addresses) > 0 ? var.ignore_body_changes.network_public_ip_addresses : null
  replace_triggers_refs  = ["zones"]
  response_export_values = ["properties.ipAddress", "properties.ipConfiguration"]
  retry                  = var.retry
  tags                   = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}

resource "azapi_resource" "firewall_policy" {
  location  = var.location
  name      = "${var.name_prefix}-policy"
  parent_id = azapi_resource.resource_group.id
  type      = var.resource_types.network_firewall_policies
  body = {
    properties = {
      sku             = { tier = var.sku_tier }
      threatIntelMode = "Alert"
    }
  }
  ignore_body_changes    = length(var.ignore_body_changes.network_firewall_policies) > 0 ? var.ignore_body_changes.network_firewall_policies : null
  response_export_values = []
  retry                  = var.retry
  tags                   = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}

module "virtual_wan" {
  source = "../.."

  enable_telemetry = var.enable_telemetry
  tags             = var.tags
  virtual_hubs = {
    primary = {
      location          = var.location
      default_parent_id = azapi_resource.resource_group.id
      enabled_resources = {
        firewall                              = true
        firewall_policy                       = false
        bastion                               = false
        private_dns_resolver                  = false
        private_dns_zones                     = false
        sidecar_virtual_network               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
      }
      hub = {
        name = "${var.name_prefix}-hub"
      }
      firewall = {
        name               = "${var.name_prefix}-firewall"
        sku_tier           = var.sku_tier
        zones              = var.zones
        firewall_policy_id = azapi_resource.firewall_policy.id
        ip_configurations = {
          for key, ip in azapi_resource.public_ips : key => {
            name                 = "ip-${key}"
            public_ip_address_id = ip.id
          }
        }
      }
    }
  }
  virtual_wan_settings = {
    enabled_resources = { ddos_protection_plan = false }
    virtual_wan       = { name = "${var.name_prefix}-wan" }
  }
}
