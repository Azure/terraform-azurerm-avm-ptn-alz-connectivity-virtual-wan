# Why this file exists
# --------------------
# An earlier test apply failed after a long gateway provisioning because
# `length(try(x, []))` let a null reach `length()`. It got that far because
# `terraform validate` is a type check, not an evaluation, and `terraform plan` never
# evaluated the `for` body -- the collection was UNKNOWN at plan time, so the expression was
# deferred to apply.
#
# These runs close that hole for the resources migrated out of AzureRM in this module by
# giving every input a KNOWN value, so the locals are forced to evaluate at plan time.
#
# `mock_provider` means no Azure calls, no credentials and no cost. Every provider the module
# declares is mocked. As of the Point-to-Site migration the module declares NO AzureRM
# provider at all -- `azurerm_vpn_server_configuration` and `azurerm_point_to_site_vpn_gateway`
# were the last two, and `mock_provider "azurerm" {}` was removed with them.

mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "11111111-1111-1111-1111-111111111111"
    }
  }
}

mock_provider "modtm" {}

mock_provider "random" {}

variables {
  enable_telemetry    = false
  location            = "eastus"
  resource_group_name = "rg-test"
  virtual_wan_name    = "vwan-test"
}

# The default shape: no resource group created, no hubs, no children. Exercises the
# constructed resource group ID and every AzureRM schema default the Virtual WAN body has to
# keep sending.
run "virtual_wan_defaults" {
  command = plan

  assert {
    condition     = length(azapi_resource.rg) == 0
    error_message = "create_resource_group defaults to false, so no resource group may be planned."
  }

  # AzureRM took the resource group by NAME plus the provider's implicit subscription. AzAPI
  # needs an ID, so it is composed from the client config rather than from a new input.
  assert {
    condition     = azapi_resource.virtual_wan[0].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    error_message = "parent_id must be composed from the provider subscription and var.resource_group_name when the module does not create the group."
  }

  # AzureRM's Create sets these unconditionally from `d.Get`, so the schema defaults
  # reached ARM on every create and must keep doing so.
  assert {
    condition     = azapi_resource.virtual_wan[0].body.properties.allowBranchToBranchTraffic == true
    error_message = "allowBranchToBranchTraffic must reproduce the AzureRM schema default true."
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].body.properties.disableVpnEncryption == false
    error_message = "disableVpnEncryption must reproduce the AzureRM schema default false."
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].body.properties.type == "Standard"
    error_message = "type must reproduce the AzureRM schema default \"Standard\"."
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].body.properties.office365LocalBreakoutCategory == "None"
    error_message = "The default Office365 category must be sent, matching AzureRM."
  }

  # `var.tags` defaults to NULL and `merge` rejects a null argument. Without the guard this
  # expression is a hard error, not an empty map.
  assert {
    condition     = length(azapi_resource.virtual_wan[0].tags) == 0
    error_message = "tags must be an empty map when var.tags is null and var.virtual_wan_tags is empty."
  }
}

run "office365_breakout_non_default_is_preserved" {
  command = plan

  variables {
    office365_local_breakout_category = "OptimizeAndAllow"
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].body.properties.office365LocalBreakoutCategory == "OptimizeAndAllow"
    error_message = "A non-default Office365 category must reach the body."
  }
}

run "tags_merged_onto_virtual_wan" {
  command = plan

  variables {
    tags             = { environment = "dev" }
    virtual_wan_tags = { deployment = "terraform" }
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].tags["environment"] == "dev"
    error_message = "General tags must be merged onto the Virtual WAN."
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].tags["deployment"] == "terraform"
    error_message = "Virtual WAN specific tags must be merged onto the Virtual WAN."
  }
}

run "resource_group_created" {
  command = plan

  variables {
    create_resource_group = true
    resource_group_tags   = { owner = "platform" }
    tags                  = { environment = "dev" }
  }

  assert {
    condition     = azapi_resource.rg[0].name == "rg-test"
    error_message = "The resource group must take var.resource_group_name verbatim."
  }

  # `Microsoft.Resources/resourceGroups` is subscription scoped. AzAPI would default this,
  # but it is set explicitly so the scope is visible in the configuration.
  assert {
    condition     = azapi_resource.rg[0].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "The resource group parent_id must be the subscription scope."
  }

  assert {
    condition     = azapi_resource.rg[0].location == "eastus"
    error_message = "The resource group must take var.location."
  }

  assert {
    condition     = azapi_resource.rg[0].tags["owner"] == "platform" && azapi_resource.rg[0].tags["environment"] == "dev"
    error_message = "The resource group must carry resource_group_tags merged with tags, as AzureRM did."
  }
}

# An existing Virtual WAN is adopted rather than created. `parse_resource_id` has to cope
# with the supplied ID and no `azapi_resource.virtual_wan` may be planned.
run "existing_virtual_wan_adopted" {
  command = plan

  variables {
    virtual_wan_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing/providers/Microsoft.Network/virtualWans/vwan-existing"
  }

  assert {
    condition     = length(azapi_resource.virtual_wan) == 0
    error_message = "Supplying virtual_wan_id must suppress creation of the Virtual WAN."
  }

  assert {
    condition     = output.name == "vwan-existing"
    error_message = "The name output must be parsed out of the supplied virtual_wan_id."
  }

  assert {
    condition     = output.resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing/providers/Microsoft.Network/virtualWans/vwan-existing"
    error_message = "The resource_id output must be the supplied virtual_wan_id verbatim."
  }
}

# `virtual_network_connection_id` is `optional(string)` with no default, so it is NULL when
# omitted. AzureRM guards the sub-resource on `d.GetOk`, which is false for both a null and
# an empty string.
run "bgp_connection_optional_null" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                = "vhub-a"
        location            = "eastus"
        resource_group_name = "rg-test"
        address_prefix      = "10.0.0.0/23"
      }
    }
    bgp_connections = {
      bgp_null = {
        name            = "bgp-null"
        virtual_hub_key = "hub_a"
        peer_asn        = 65001
        peer_ip         = "10.50.0.4"
      }
      bgp_empty = {
        name                          = "bgp-empty"
        virtual_hub_key               = "hub_a"
        peer_asn                      = 65002
        peer_ip                       = "10.50.0.5"
        virtual_network_connection_id = ""
      }
      bgp_set = {
        name                          = "bgp-set"
        virtual_hub_key               = "hub_a"
        peer_asn                      = 65003
        peer_ip                       = "10.50.0.6"
        virtual_network_connection_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/hubVirtualNetworkConnections/conn-a"
      }
    }
  }

  assert {
    condition     = !can(azapi_resource.bgp_connection["bgp_null"].body.properties.hubVirtualNetworkConnection)
    error_message = "hubVirtualNetworkConnection must be absent when virtual_network_connection_id is null, matching AzureRM's d.GetOk guard."
  }

  assert {
    condition     = !can(azapi_resource.bgp_connection["bgp_empty"].body.properties.hubVirtualNetworkConnection)
    error_message = "hubVirtualNetworkConnection must be absent for an empty string; d.GetOk is false for the zero value."
  }

  assert {
    condition     = azapi_resource.bgp_connection["bgp_set"].body.properties.hubVirtualNetworkConnection.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/hubVirtualNetworkConnections/conn-a"
    error_message = "hubVirtualNetworkConnection must wrap the connection ID in a SubResource object."
  }

  assert {
    condition     = azapi_resource.bgp_connection["bgp_null"].body.properties.peerAsn == 65001
    error_message = "peer_asn must map to properties.peerAsn."
  }

  # ARM spells this `peerIp`, with a lower-case `p`. The Go SDK field is `PeerIP`, which is
  # the easy thing to copy by mistake.
  assert {
    condition     = azapi_resource.bgp_connection["bgp_null"].body.properties.peerIp == "10.50.0.4"
    error_message = "peer_ip must map to properties.peerIp."
  }
}

run "bgp_connections_empty_map" {
  command = plan

  assert {
    condition     = length(azapi_resource.bgp_connection) == 0
    error_message = "An empty bgp_connections map must create no resources."
  }
}

# `labels` and `routes` are both `optional(...)` with no default, so both are NULL when
# omitted. AzureRM's expanders return empty slices rather than nil, so both keys have to be
# present as empty lists -- and the original `dynamic "route"` block raised on the null.
run "route_table_optionals_null" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                = "vhub-a"
        location            = "eastus"
        resource_group_name = "rg-test"
        address_prefix      = "10.0.0.0/23"
      }
    }
    virtual_hub_route_tables = {
      rt_null = {
        name            = "rt-null"
        virtual_hub_key = "hub_a"
      }
    }
  }

  assert {
    condition     = length(azapi_resource.virtual_hub_route_table["rt_null"].body.properties.labels) == 0
    error_message = "labels must be an empty list, not absent: utils.ExpandStringSlice returns a non-nil pointer to an empty slice."
  }

  assert {
    condition     = length(azapi_resource.virtual_hub_route_table["rt_null"].body.properties.routes) == 0
    error_message = "routes must be an empty list, not absent: expandVirtualHubRouteTableHubRoutes always returns a slice."
  }
}

run "route_table_routes_set" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                = "vhub-a"
        location            = "eastus"
        resource_group_name = "rg-test"
        address_prefix      = "10.0.0.0/23"
      }
    }
    virtual_hub_route_tables = {
      rt_a = {
        name            = "rt-a"
        virtual_hub_key = "hub_a"
        labels          = ["default", "spoke"]
        routes = {
          route_a = {
            name              = "route-a"
            destinations      = ["10.60.0.0/16"]
            destinations_type = "CIDR"
            next_hop          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-a"
            next_hop_type     = "ResourceId"
          }
        }
      }
    }
  }

  # A bare list literal is a TUPLE and `tuple == list(string)` is false with nothing but a
  # warning, so both sides are normalised.
  assert {
    condition     = tolist(azapi_resource.virtual_hub_route_table["rt_a"].body.properties.labels) == tolist(["default", "spoke"])
    error_message = "labels must carry the configured labels verbatim."
  }

  # `destinations_type` (plural input) maps to `destinationType` (singular ARM property).
  assert {
    condition     = azapi_resource.virtual_hub_route_table["rt_a"].body.properties.routes[0].destinationType == "CIDR"
    error_message = "destinations_type must map to the singular ARM property destinationType."
  }

  assert {
    condition     = azapi_resource.virtual_hub_route_table["rt_a"].body.properties.routes[0].nextHop == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-a"
    error_message = "next_hop must be used verbatim when vnet_connection_key is null."
  }

  assert {
    condition     = azapi_resource.virtual_hub_route_table["rt_a"].body.properties.routes[0].nextHopType == "ResourceId"
    error_message = "next_hop_type must map to properties.routes[].nextHopType."
  }

  assert {
    condition     = tolist(azapi_resource.virtual_hub_route_table["rt_a"].body.properties.routes[0].destinations) == tolist(["10.60.0.0/16"])
    error_message = "destinations must be carried verbatim."
  }
}

# `expandRoutingPolicy` returns a pointer to an empty slice for empty input, so
# `routingPolicies` is `[]` rather than absent.
run "routing_intent_empty_policies" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                = "vhub-a"
        location            = "eastus"
        resource_group_name = "rg-test"
        address_prefix      = "10.0.0.0/23"
      }
    }
    routing_intents = {
      intent_a = {
        name             = "intent-a"
        virtual_hub_key  = "hub_a"
        routing_policies = []
      }
    }
  }

  assert {
    condition     = length(azapi_resource.routing_intent["intent_a"].body.properties.routingPolicies) == 0
    error_message = "routingPolicies must be an empty list, not absent, when there are no policies."
  }
}

run "routing_intent_policies_set" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                = "vhub-a"
        location            = "eastus"
        resource_group_name = "rg-test"
        address_prefix      = "10.0.0.0/23"
      }
    }
    firewalls = {
      fw_a = {
        name            = "fw-a"
        virtual_hub_key = "hub_a"
        sku_tier        = "Standard"
      }
    }
    routing_intents = {
      intent_a = {
        name            = "intent-a"
        virtual_hub_key = "hub_a"
        routing_policies = [
          {
            name                  = "policy-internet"
            destinations          = ["Internet"]
            next_hop_firewall_key = "fw_a"
          }
        ]
      }
    }
  }

  assert {
    condition     = length(azapi_resource.routing_intent["intent_a"].body.properties.routingPolicies) == 1
    error_message = "One routing policy in must be one routingPolicies entry out."
  }

  assert {
    condition     = azapi_resource.routing_intent["intent_a"].body.properties.routingPolicies[0].name == "policy-internet"
    error_message = "The routing policy name must be carried verbatim."
  }

  assert {
    condition     = tolist(azapi_resource.routing_intent["intent_a"].body.properties.routingPolicies[0].destinations) == tolist(["Internet"])
    error_message = "The routing policy destinations must be carried verbatim."
  }
}

run "routing_intents_empty_map" {
  command = plan

  assert {
    condition     = length(azapi_resource.routing_intent) == 0
    error_message = "An empty routing_intents map must create no resources."
  }
}

# Timeout defaults are PER RESOURCE, taken from the AzureRM resource each azapi_resource
# replaced, not from one blanket 30m. Sourced from terraform-provider-azurerm at
# 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0); see `locals.timeouts.tf`.
run "timeout_defaults_are_per_resource" {
  command = plan

  variables {
    create_resource_group = true
  }

  # resource_group_resource.go L41-L46. This is the one the blanket 30m got wrong.
  assert {
    condition     = azapi_resource.rg[0].timeouts.create == "90m" && azapi_resource.rg[0].timeouts.update == "90m" && azapi_resource.rg[0].timeouts.delete == "90m"
    error_message = "azurerm_resource_group defaulted create/update/delete to 90m, not 30m."
  }

  assert {
    condition     = azapi_resource.rg[0].timeouts.read == "5m"
    error_message = "azurerm_resource_group defaulted read to 5m."
  }

  # virtual_wan_resource.go L36-L41.
  assert {
    condition     = azapi_resource.virtual_wan[0].timeouts.create == "30m" && azapi_resource.virtual_wan[0].timeouts.read == "5m" && azapi_resource.virtual_wan[0].timeouts.update == "30m" && azapi_resource.virtual_wan[0].timeouts.delete == "30m"
    error_message = "azurerm_virtual_wan defaulted to Create 30m, Read 5m, Update 30m, Delete 30m."
  }
}

# An explicitly supplied var.timeouts still wins everywhere: the public variable shape is
# unchanged and a consumer who sets it today keeps the behaviour they have.
run "explicit_timeouts_override_every_resource" {
  command = plan

  variables {
    create_resource_group = true
    timeouts              = { create = "12m", read = "3m", update = "13m", delete = "14m" }
  }

  assert {
    condition     = azapi_resource.rg[0].timeouts.create == "12m" && azapi_resource.rg[0].timeouts.read == "3m" && azapi_resource.rg[0].timeouts.update == "13m" && azapi_resource.rg[0].timeouts.delete == "14m"
    error_message = "An explicit var.timeouts must override the per-resource fallback."
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].timeouts.create == "12m" && azapi_resource.virtual_wan[0].timeouts.delete == "14m"
    error_message = "An explicit var.timeouts must override the per-resource fallback on every resource."
  }
}

# A partially supplied var.timeouts keeps the per-resource fallback for the attributes the
# consumer left unset -- which is the whole point of dropping the blanket defaults.
run "partial_timeouts_fall_back_per_resource" {
  command = plan

  variables {
    create_resource_group = true
    timeouts              = { create = "45m" }
  }

  assert {
    condition     = azapi_resource.rg[0].timeouts.create == "45m" && azapi_resource.rg[0].timeouts.delete == "90m"
    error_message = "An unset attribute must fall back to the AzureRM default for that resource."
  }

  assert {
    condition     = azapi_resource.virtual_wan[0].timeouts.create == "45m" && azapi_resource.virtual_wan[0].timeouts.delete == "30m"
    error_message = "An unset attribute must fall back to the AzureRM default for that resource."
  }
}
