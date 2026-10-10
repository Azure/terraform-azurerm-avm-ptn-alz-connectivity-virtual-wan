# Bug-for-bug parity tests for the azurerm -> azapi migration of `modules/virtual-hub`.
#
# Why this file exists: An earlier test apply failed at APPLY, not at plan, because the inputs were
# unknown at plan time and the locals were never evaluated. Known inputs force evaluation. And
# `try()` catches ERRORS, not nulls, so a null that reaches a function survives `terraform
# validate` AND a passing plan. Nulls are therefore exercised explicitly below.
#
# `mock_provider` means no Azure calls, no credentials and no cost.
#
# Every assertion cites the azurerm source it is pinning, at v4.81.0
# (`5782a75422c68a0d0804ac16d97dcaf3df5ee2fa`), `internal/services/network/virtual_hub_resource.go`.

mock_provider "azapi" {}

variables {
  resource_types = {
    network_virtual_hubs = "Microsoft.Network/virtualHubs@2025-07-01"
  }
}

# Every optional the variable exposes is explicitly NULL. `resource_group_name` is the one
# exception: it was `Required` on `azurerm_virtual_hub` (`commonschema.ResourceGroupName()`, L62),
# so a null there was a hard plan error before this migration and still is.
run "all_optionals_null" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                                   = "vhub-null"
        location                               = "uksouth"
        resource_group_name                    = "rg-test"
        address_prefix                         = "10.0.0.0/23"
        virtual_wan_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        tags                                   = null
        sku                                    = null
        hub_routing_preference                 = null
        virtual_router_auto_scale_min_capacity = null
      }
    }
  }

  # L188-189. Built as a struct literal with `pointer.To(d.Get(...).(bool))`, so it is in EVERY
  # create body AzureRM sent, at the schema default `false` (L73-77) because this module exposes
  # no variable for it. If this literal ever disappears, a migrated hub silently changes its
  # branch-to-branch behaviour on the first post-upgrade apply.
  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.allowBranchToBranchTraffic == false
    error_message = "allowBranchToBranchTraffic must reproduce AzureRM's unexposed schema default false."
  }

  # L191. Unconditional, and `optional(string, \"ExpressRoute\")` applies its default to an
  # explicit null as well as to an omitted attribute.
  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.hubRoutingPreference == "ExpressRoute"
    error_message = "hubRoutingPreference must be present and default to ExpressRoute."
  }

  # L190 + L414-417: `expandVirtualHubRoute` returns a NIL pointer for empty input, and the field
  # is `omitempty`, so the key was absent from the request - not an empty object. The module
  # exposes no `route` variable, so it must never appear.
  assert {
    condition     = !can(azapi_resource.this["hub_a"].body.properties.routeTable)
    error_message = "routeTable must be absent: expandVirtualHubRoute returns nil for empty input and the field is omitempty."
  }

  # L200-202: `if v, ok := d.GetOk(\"sku\"); ok`.
  assert {
    condition     = !can(azapi_resource.this["hub_a"].body.properties.sku)
    error_message = "sku must be absent when null, matching AzureRM's d.GetOk guard."
  }

  # L196-198.
  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.addressPrefix == "10.0.0.0/23"
    error_message = "addressPrefix must carry the configured value."
  }

  # L204-208. ARM takes a SubResource object here, not a bare ID string, and the JSON key is
  # `virtualWan` with a lower-case `w`.
  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.virtualWan.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
    error_message = "virtualWan must be a SubResource object carrying the configured Virtual WAN ID."
  }

  # L210-214, with the module's `optional(number, 2)` default applied to the explicit null.
  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.virtualRouterAutoScaleConfiguration.minCapacity == 2
    error_message = "virtualRouterAutoScaleConfiguration.minCapacity must default to 2."
  }

  # L193: `tags.Expand` returns a pointer to a map and never nil, so `\"tags\": {}` was in every
  # create request AzureRM sent.
  assert {
    condition     = length(azapi_resource.this["hub_a"].tags) == 0
    error_message = "tags must be an empty map, not null, matching tags.Expand's never-nil pointer."
  }

  # The hub's parent is the resource group resource ID, assembled from the provider's subscription.
  assert {
    condition     = endswith(azapi_resource.this["hub_a"].parent_id, "/resourceGroups/rg-test")
    error_message = "parent_id must be the resource group resource ID built from resource_group_name."
  }

  # ── merge writer ────────────────────────────────────────────────────────────────────────────
  # L276: `branch_to_branch_traffic_enabled` is mutated only behind `d.HasChange`, and this module
  # exposes no variable for it, so HasChange never fired and the day-2 body must not carry it.
  assert {
    condition     = !can(azapi_update_resource.this["hub_a"].body.properties.allowBranchToBranchTraffic)
    error_message = "the day-2 merge body must NOT carry allowBranchToBranchTraffic: AzureRM's update guarded it on d.HasChange, which no module variable could ever trip."
  }

  # L281: same reasoning for `route`.
  assert {
    condition     = !can(azapi_update_resource.this["hub_a"].body.properties.routeTable)
    error_message = "the day-2 merge body must NOT carry routeTable."
  }

  # `address_prefix` (L69), `sku` (L82) and `virtual_wan_id` (L92) are ForceNew, so they were never
  # part of an update at all.
  assert {
    condition     = !can(azapi_update_resource.this["hub_a"].body.properties.addressPrefix) && !can(azapi_update_resource.this["hub_a"].body.properties.virtualWan)
    error_message = "the day-2 merge body must NOT carry ForceNew properties."
  }

  assert {
    condition     = azapi_update_resource.this["hub_a"].body.properties.hubRoutingPreference == "ExpressRoute"
    error_message = "the day-2 merge body must carry hubRoutingPreference (azurerm update L285)."
  }

  # 🔴 REG-1, INVERTED IN 0.19.0. This assertion used to require the OPPOSITE -- that the merge
  # body carried `tags` -- and that is what made REG-1: the merge preserves every undeclared key
  # of the live object (`utils/json.go` L52-L53), so a tag could be added or changed but never
  # REMOVED, while azurerm update L289 ASSIGNED the whole map.
  assert {
    condition     = !can(azapi_update_resource.this["hub_a"].body.tags)
    error_message = "the day-2 merge body must NOT carry a tags key: a merge writer can never remove a tag (REG-1). Tags belong on azapi_resource_action.tags."
  }

  # `{}` and not an omitted key: azurerm update L289 `tags.Expand` returned a pointer to an EMPTY
  # map and never nil, and this PUT REPLACES the whole set, so an omitted key would mean "send no
  # tags at all".
  assert {
    condition     = azapi_resource_action.tags["hub_a"].body.properties.tags != null && length(azapi_resource_action.tags["hub_a"].body.properties.tags) == 0
    error_message = "the tag writer must PUT an empty map rather than a null or an omitted key (azurerm update L289)."
  }
}

# Every optional set to a non-default value. This run is here because it has caught a real HCL
# type-unification bug before: a bare literal is a TUPLE / OBJECT, and comparing one against a
# `list(string)` / `map(string)` is false with only a warning. Both sides are therefore converted
# explicitly below.
run "all_optionals_set" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                                   = "vhub-full"
        location                               = "uksouth"
        resource_group_name                    = "rg-test"
        address_prefix                         = "10.1.0.0/23"
        virtual_wan_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        tags                                   = { env = "test", owner = "alz" }
        sku                                    = "Standard"
        hub_routing_preference                 = "ASPath"
        virtual_router_auto_scale_min_capacity = 3
      }
    }
  }

  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.sku == "Standard"
    error_message = "sku must be emitted when set."
  }

  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.hubRoutingPreference == "ASPath"
    error_message = "hubRoutingPreference must carry the configured value."
  }

  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.virtualRouterAutoScaleConfiguration.minCapacity == 3
    error_message = "virtualRouterAutoScaleConfiguration.minCapacity must carry the configured value."
  }

  # 🔴 `tomap()` on BOTH sides. `azapi_resource.this[...].tags` is `map(string)`; the right-hand
  # literal is an OBJECT, and `map(string) == object(...)` is false with only a warning.
  assert {
    condition     = tomap(azapi_resource.this["hub_a"].tags) == tomap({ env = "test", owner = "alz" })
    error_message = "tags must carry the configured map verbatim."
  }

  # Still the AzureRM literal, still absent - neither depends on the consumer's configuration.
  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.allowBranchToBranchTraffic == false
    error_message = "allowBranchToBranchTraffic must stay at AzureRM's schema default even when every exposed optional is set."
  }

  assert {
    condition     = !can(azapi_resource.this["hub_a"].body.properties.routeTable)
    error_message = "routeTable must stay absent even when every exposed optional is set."
  }

  # 🔴 None of the 11 undeclared writable hub paths may appear in the full writer's body. If one
  # ever does it must come with its own registry measurement, not with a shrug. See the table at
  # the top of `main.tf`.
  assert {
    condition     = !can(azapi_resource.this["hub_a"].body.properties.virtualHubRouteTableV2s) && !can(azapi_resource.this["hub_a"].body.properties.azureFirewall) && !can(azapi_resource.this["hub_a"].body.properties.vpnGateway) && !can(azapi_resource.this["hub_a"].body.properties.expressRouteGateway)
    error_message = "the full writer must declare none of the hub's child collections or back-references; the create-only lifecycle is what protects them."
  }

  # 🔴 REG-1's remedy. The configured map moved off the merge writer and onto the tag writer,
  # which PUTs at `Microsoft.Resources/tags/default` and REPLACES the whole set, as azurerm
  # update L289 did. Same `tomap()`-on-both-sides discipline as everywhere else in this file.
  assert {
    condition     = !can(azapi_update_resource.this["hub_a"].body.tags)
    error_message = "the day-2 merge body must NOT carry a tags key: a merge writer can never remove a tag (REG-1)."
  }

  assert {
    condition     = tomap(azapi_resource_action.tags["hub_a"].body.properties.tags) == tomap({ env = "test", owner = "alz" })
    error_message = "the tag writer must carry the configured tag map."
  }

  assert {
    condition     = !can(azapi_update_resource.this["hub_a"].body.properties.sku)
    error_message = "sku is ForceNew on azurerm_virtual_hub and must never appear in the day-2 merge body."
  }
}

# 🔴 `d.GetOk` on an INT is false for 0, so AzureRM omitted the whole
# `virtualRouterAutoScaleConfiguration` object rather than sending `minCapacity: 0` (L210-214).
# AzureRM's own schema could not produce 0 (`Default: 2`, `IntAtLeast(2)`, L149-154); this module's
# `optional(number, 2)` has no such validation, so the branch is reachable here in a way it was not
# there. Preserved rather than "fixed".
run "auto_scale_min_capacity_zero" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                                   = "vhub-zero"
        location                               = "uksouth"
        resource_group_name                    = "rg-test"
        address_prefix                         = "10.2.0.0/23"
        virtual_wan_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        virtual_router_auto_scale_min_capacity = 0
      }
    }
  }

  assert {
    condition     = !can(azapi_resource.this["hub_a"].body.properties.virtualRouterAutoScaleConfiguration)
    error_message = "a min capacity of 0 must omit virtualRouterAutoScaleConfiguration entirely, matching d.GetOk's zero-value semantics on an int."
  }

  assert {
    condition     = !can(azapi_update_resource.this["hub_a"].body.properties.virtualRouterAutoScaleConfiguration)
    error_message = "a min capacity of 0 must omit virtualRouterAutoScaleConfiguration from the day-2 merge body too."
  }
}

run "empty_map" {
  command = plan

  variables {
    virtual_hubs = {}
  }

  assert {
    condition     = length(azapi_resource.this) == 0
    error_message = "An empty virtual_hubs map must create no full writers."
  }

  assert {
    condition     = length(azapi_update_resource.this) == 0
    error_message = "An empty virtual_hubs map must create no merge writers."
  }

  assert {
    condition     = length(output.resource_id) == 0
    error_message = "An empty virtual_hubs map must produce empty outputs rather than failing."
  }
}
