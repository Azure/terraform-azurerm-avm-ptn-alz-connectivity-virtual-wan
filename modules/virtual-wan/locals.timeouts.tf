locals {
  # Per-resource timeout defaults.
  #
  # `var.timeouts` keeps its published shape -- same variable name, same four attributes, same
  # types, still `nullable = false` with `default = {}` -- but its attributes no longer carry a
  # blanket `30m`/`5m` default. Each attribute is now `optional(string)`, null when unset, and
  # falls back PER RESOURCE to the timeout default of the AzureRM resource that resource
  # replaced. A consumer who sets `var.timeouts` today keeps working unchanged: whatever they
  # set still wins for every resource in the module. Only the UNSET attributes changed meaning.
  #
  # The blanket `30m` was measurably wrong here: `azurerm_resource_group` defaulted
  # create/update/delete to 90m, not 30m.
  #
  # Every fallback below is cited against the AzureRM provider source at
  # terraform-provider-azurerm@5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0).
  timeouts = {
    # azapi_resource.rg -> azurerm_resource_group
    #   resource_group_resource.go L41-L46: Create 90m, Read 5m, Update 90m, Delete 90m
    resources_resource_groups = {
      create = try(var.timeouts.create, null) != null ? var.timeouts.create : "90m"
      read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
      update = try(var.timeouts.update, null) != null ? var.timeouts.update : "90m"
      delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "90m"
    }
    # azapi_resource.virtual_wan -> azurerm_virtual_wan
    #   virtual_wan_resource.go L36-L41: Create 30m, Read 5m, Update 30m, Delete 30m
    network_virtual_wans = {
      create = try(var.timeouts.create, null) != null ? var.timeouts.create : "30m"
      read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
      update = try(var.timeouts.update, null) != null ? var.timeouts.update : "30m"
      delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "30m"
    }
    # azapi_resource.virtual_hub_route_table -> azurerm_virtual_hub_route_table
    #   virtual_hub_route_table_resource.go L36-L41: Create 30m, Read 5m, Update 30m, Delete 30m
    network_virtual_hubs_hub_route_tables = {
      create = try(var.timeouts.create, null) != null ? var.timeouts.create : "30m"
      read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
      update = try(var.timeouts.update, null) != null ? var.timeouts.update : "30m"
      delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "30m"
    }
    # azapi_resource.bgp_connection -> azurerm_virtual_hub_bgp_connection
    #   virtual_hub_bgp_connection_resource.go L33-L37: Create 30m, Read 5m, Delete 30m
    #
    # ⚠️ That block declares NO Update timeout, because the AzureRM resource registers no
    # Update at all -- every schema attribute is ForceNew. AzAPI does issue a PUT for an
    # in-place change, so an update timeout still has to be supplied; there is no sourced
    # AzureRM value for it and the create timeout is reused rather than invented from nothing.
    # This is the one fallback below that is NOT a direct transcription of a provider default.
    network_virtual_hubs_bgp_connections = {
      create = try(var.timeouts.create, null) != null ? var.timeouts.create : "30m"
      read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
      update = try(var.timeouts.update, null) != null ? var.timeouts.update : "30m"
      delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "30m"
    }
    # azapi_resource.routing_intent -> azurerm_virtual_hub_routing_intent
    #   This one is a typed (`sdk.ResourceFunc`) resource, so its timeouts are per CRUD method
    #   rather than one `ResourceTimeout` block. virtual_hub_routing_intent_resource.go:
    #     Create L111-L113: 30m
    #     Update L155-L157: 30m
    #     Read   L194-L196: 5m
    #     Delete L234-L236: 30m
    network_virtual_hubs_routing_intent = {
      create = try(var.timeouts.create, null) != null ? var.timeouts.create : "30m"
      read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
      update = try(var.timeouts.update, null) != null ? var.timeouts.update : "30m"
      delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "30m"
    }
    # azapi_resource.p2s_gateway_vpn_server_configuration
    # + azapi_update_resource.p2s_gateway_vpn_server_configuration
    #   -> azurerm_vpn_server_configuration
    #   vpn_server_configuration_resource.go L36-L40: Create 90m, Read 5m, Update 90m, Delete 90m
    #
    # ⚠️ The merge writer has no delete timeout to set -- `azapi_update_resource.Delete` is an
    # empty function and `AzapiUpdateResourceModel` carries no delete timeout attribute -- and
    # its "create" is really the first merge PUT, so it takes the 90m UPDATE value. Both
    # writers share this one entry.
    network_vpn_server_configurations = {
      create = try(var.timeouts.create, null) != null ? var.timeouts.create : "90m"
      read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
      update = try(var.timeouts.update, null) != null ? var.timeouts.update : "90m"
      delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "90m"
    }
    # azapi_resource.p2s_gateway -> azurerm_point_to_site_vpn_gateway
    #   point_to_site_vpn_gateway_resource.go L40-L44: Create 90m, Read 5m, Update 90m, Delete 90m
    network_p2s_vpn_gateways = {
      create = try(var.timeouts.create, null) != null ? var.timeouts.create : "90m"
      read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
      update = try(var.timeouts.update, null) != null ? var.timeouts.update : "90m"
      delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "90m"
    }
  }
}
