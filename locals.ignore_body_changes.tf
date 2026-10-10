locals {
  # Merges the deprecated keys from v0.18.0 into their replacements.
  ignore_body_changes_route_maps = distinct(concat(
    var.ignore_body_changes.network_virtual_hubs_route_maps.network_virtual_hubs_route_maps,
    var.ignore_body_changes.virtual_hubs_route_maps.virtual_hubs_route_maps,
  ))
  ignore_body_changes_virtual_wans = merge(var.ignore_body_changes.network_virtual_wans, {
    network_azure_firewalls = {
      network_azure_firewalls = distinct(concat(
        var.ignore_body_changes.network_virtual_wans.network_azure_firewalls.network_azure_firewalls,
        var.ignore_body_changes.virtual_hubs_firewalls,
      ))
      insights_diagnostic_settings = distinct(concat(
        var.ignore_body_changes.network_virtual_wans.network_azure_firewalls.insights_diagnostic_settings,
        var.ignore_body_changes.virtual_hubs_firewalls_diagnostic_settings,
      ))
    }
  })
}
