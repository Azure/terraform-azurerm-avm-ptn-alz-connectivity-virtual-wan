locals {
  ddos_protection_plan         = local.ddos_protection_plan_enabled ? var.virtual_wan_settings.ddos_protection_plan : null
  ddos_protection_plan_enabled = try(var.virtual_wan_settings.ddos_protection_plan.enabled, try(var.virtual_wan_settings.ddos_protection_plan, null) != null)
}
