locals {
  flattened_diagnostic_settings = {
    for v in
    flatten([
      for hub_key, diag_map in var.diagnostic_settings : [
        for setting_key, setting_val in diag_map : {
          value                  = setting_val
          virtual_hub_key        = hub_key
          diagnostic_setting_key = setting_key
        }
      ]
      ]) : "${v.virtual_hub_key}-${v.diagnostic_setting_key}" => {
      data                   = v.value
      virtual_hub_key        = v.virtual_hub_key
      diagnostic_setting_key = v.diagnostic_setting_key
    }
  }
  ip_configuration = {
    for k, v in(var.firewalls != null ? var.firewalls : {}) :
    k => (length(coalesce(v.firewall_public_ip_id, "")) > 0) ?
    [
      {
        name = "assigned"
        properties = {
          publicIPAddress = {
            id = v.firewall_public_ip_id
          }
        }
      }
    ] : []
  }
}
