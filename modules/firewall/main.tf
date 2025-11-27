data "azurerm_resource_group" "fw_rg" {
  for_each = var.firewalls != null ? var.firewalls : {}
  name     = each.value.resource_group_name
}

resource "azapi_resource" "fw" {
  type     = "Microsoft.Network/azureFirewalls@2024-10-01"
  for_each = var.firewalls != null ? var.firewalls : {}

  location  = each.value.location
  name      = each.value.name
  parent_id = data.azurerm_resource_group.fw_rg[each.key].id
  tags      = try(each.value.tags, {})
  body = {
    zones = each.value.zones
    properties = {
      sku = {
        name = each.value.sku_name
        tier = each.value.sku_tier
      }
      firewallPolicy = {
        id = each.value.firewall_policy_id
      }
      virtualHub = {
        id = each.value.virtual_hub_id
      }
      hubIPAddresses = {
        publicIPs = {
          count = each.value.vhub_public_ip_count
        }
      }
      ipConfigurations = coalesce(each.value.ip_configuration, [])
    }
  }
  schema_validation_enabled = false
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.flattened_diagnostic_settings

  name                           = each.value.data.name != null ? each.value.data.name : "diag-${azapi_resource.fw[each.value.virtual_hub_key].name}"
  target_resource_id             = azapi_resource.fw[each.value.virtual_hub_key].id
  eventhub_authorization_rule_id = each.value.data.event_hub_authorization_rule_resource_id
  eventhub_name                  = each.value.data.event_hub_name
  log_analytics_destination_type = each.value.data.log_analytics_destination_type
  log_analytics_workspace_id     = each.value.data.workspace_resource_id
  partner_solution_id            = each.value.data.marketplace_partner_resource_id
  storage_account_id             = each.value.data.storage_account_resource_id

  dynamic "enabled_log" {
    for_each = each.value.data.log_categories

    content {
      category = enabled_log.value
    }
  }
  dynamic "enabled_log" {
    for_each = each.value.data.log_groups

    content {
      category_group = enabled_log.value
    }
  }
  dynamic "enabled_metric" {
    for_each = each.value.data.metric_categories

    content {
      category = enabled_metric.value
    }
  }
}
