output "enabled" {
  description = "Mirror the pattern's zero-deployed-hubs cardinality."
  value       = length(var.configuration.hub_keys) > 0
}

output "firewalls" {
  description = "Two independently keyed firewall inputs; no firewall resource is replaced by a fixture."
  value       = local.firewalls
}

output "virtual_hubs" {
  description = "Actual virtual-hub inputs, including optionally unknown names."
  value = {
    for key in var.configuration.hub_keys : key => {
      name = var.configuration.unknown_values ? (
        "hub-${key}-${terraform_data.upstream.output}"
      ) : "hub-${key}"
      location            = "uksouth"
      resource_group_name = "rg-firewall-graph"
      address_prefix      = key == "east" ? "10.0.0.0/24" : "10.1.0.0/24"
      sku                 = "Standard"
    }
  }
}

output "diagnostic_settings" {
  description = "Historical diagnostic addresses with explicit and generated names."
  value = {
    for key, firewall in local.firewalls : key => {
      audit = {
        name                  = key == "edge-east" ? "audit-east" : null
        workspace_resource_id = "${local.parent_id}/providers/Microsoft.OperationalInsights/workspaces/logs"
      }
    }
  }
}
