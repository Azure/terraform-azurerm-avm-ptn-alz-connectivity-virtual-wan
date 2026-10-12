data "azurerm_client_config" "current" {
  count = length(local.requested_customer_firewalls) == 0 ? 0 : 1
}

data "azapi_resource_list" "firewalls" {
  count = length(local.requested_customer_firewalls) == 0 ? 0 : 1

  parent_id = "/subscriptions/${one(data.azurerm_client_config.current).subscription_id}"
  type      = var.resource_types.network_azure_firewalls
  response_export_values = {
    firewalls = "value[].{id:id,name:name,properties:properties}"
  }
}

resource "terraform_data" "public_ip_mode" {
  for_each = local.firewalls

  input = local.customer_mode[each.key]

  lifecycle {
    # Keep only this state-only record immutable; the postcondition rejects rather than hides a mode edit.
    ignore_changes = [input]

    precondition {
      condition = !local.customer_mode[each.key] ? true : (
        local.existing_firewalls[each.key] == null ? true : local.existing_customer_mode[each.key]
      )
      error_message = "Firewall ${each.key}: changing between managed and customer public IP modes is not supported by normal apply. Keep the existing mode; cross-mode conversion requires a separately approved maintenance procedure."
    }
    postcondition {
      condition     = self.output == local.customer_mode[each.key]
      error_message = "Firewall ${each.key}: the recorded public IP mode cannot change. Keep the existing managed/customer mode; removing the final customer IP or adding customer IPs to a managed firewall is not supported."
    }
  }
}

resource "azurerm_firewall" "fw" {
  for_each = { for key, firewall in local.firewalls : key => firewall if !local.customer_mode[key] }

  location            = each.value.location
  name                = each.value.name
  resource_group_name = each.value.resource_group_name
  sku_name            = each.value.sku_name
  sku_tier            = each.value.sku_tier
  firewall_policy_id  = each.value.firewall_policy_id
  tags                = try(each.value.tags, {})
  zones               = each.value.zones

  virtual_hub {
    virtual_hub_id  = each.value.virtual_hub_id
    public_ip_count = each.value.vhub_public_ip_count == null ? 1 : tonumber(each.value.vhub_public_ip_count)
  }

  depends_on = [terraform_data.public_ip_mode]
}

module "customer_firewalls" {
  source   = "../firewall-customer-ip"
  for_each = local.customer_firewalls

  ip_configurations = each.value.ip_configurations
  location          = each.value.location
  name              = each.value.name
  parent_id         = local.parent_ids[each.key]
  virtual_hub_id    = each.value.virtual_hub_id
  diagnostic_settings = {
    for key, setting in local.diagnostic_settings_v2 : key => setting
    if local.flattened_diagnostic_settings[key].virtual_hub_key == each.key
  }
  enable_telemetry    = var.enable_telemetry
  firewall_policy_id  = each.value.firewall_policy_id
  ignore_body_changes = var.ignore_body_changes
  resource_types      = var.resource_types
  retry               = var.retry
  sku_tier            = each.value.sku_tier
  tags                = each.value.tags
  timeouts            = var.timeouts
  zones               = each.value.zones

  depends_on = [terraform_data.public_ip_mode]
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = {
    for key, setting in local.flattened_diagnostic_settings : key => setting
    if !local.customer_mode[setting.virtual_hub_key]
  }

  name                           = each.value.data.name != null ? each.value.data.name : "diag-${azurerm_firewall.fw[each.value.virtual_hub_key].name}"
  target_resource_id             = azurerm_firewall.fw[each.value.virtual_hub_key].id
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
