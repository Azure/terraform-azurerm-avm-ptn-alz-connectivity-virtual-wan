# See `modules/site-to-site-vpn-site/tests/null_optionals.tftest.hcl` for why this exists:
# An earlier test apply failed at apply, not at plan, because the inputs were unknown at plan
# time and the locals were never evaluated. Known inputs force evaluation.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

mock_provider "azapi" {}

variables {
  resource_types = {
    network_express_route_gateways = "Microsoft.Network/expressRouteGateways@2025-07-01"
  }
}

run "all_optionals_null" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-null"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
      }
    }
  }

  # AzureRM's Create builds `parameters.Properties` as an unconditional struct literal and
  # sends every field via `pointer.To(d.Get(...))`. The schema defaults therefore reached ARM
  # on every create, so a migrated gateway must send the same literals or the first
  # post-upgrade apply resets them on a live gateway.
  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.allowNonVirtualWanTraffic == false
    error_message = "allowNonVirtualWanTraffic must reproduce AzureRM's schema default false (express_route_gateway_resource.go L74, sent unconditionally at L120)."
  }

  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.autoScaleConfiguration.bounds.min == 1
    error_message = "autoScaleConfiguration.bounds.min must reproduce the module's scale_units default of 1 (sent unconditionally at L123)."
  }

  # 🔴 `bounds.max` must NOT appear. AzureRM set `Min` only (L121-L125); adding `max` would be
  # a behaviour change on every existing gateway, not a completion of the object.
  assert {
    condition     = !can(azapi_resource.this["gw_a"].body.properties.autoScaleConfiguration.bounds.max)
    error_message = "autoScaleConfiguration.bounds.max must be absent: AzureRM only ever sent bounds.min."
  }

  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.virtualHub.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
    error_message = "virtualHub.id must carry the configured Virtual Hub ID (L126-L128)."
  }

  # 🔴🔴 THE ONE THAT MATTERS. The connections live in
  # `modules/expressroute-gateway-connection`, so a full PUT from here that declared the array
  # would delete every connection not named in it. AzureRM avoided that by LISTing and
  # re-attaching (L107-L115, L129); this module avoids it by never declaring the array and by
  # never PUTting after create. If this assertion ever fails, the deletion hazard is back.
  assert {
    condition     = !can(azapi_resource.this["gw_a"].body.properties.expressRouteConnections)
    error_message = "properties.expressRouteConnections must NEVER be declared by the gateway's full writer: the connections are owned by modules/expressroute-gateway-connection and a PUT carrying this array is a deletion."
  }

  # ⚠️ NO ASSERTION ON `azapi_resource.this[...].tags` HERE, and the reason is worth recording:
  # `tags` is Optional+Computed on `azapi_resource` (L80), so when the configured value is an
  # empty map the provider leaves it `(not yet known)` at plan time. The configured value is
  # `try(each.value.tags, {})`, which reproduces `tags.Expand`'s non-nil empty map (L131) --
  # `"tags": {}` rather than an omitted key -- but that is only observable at apply. The
  # `all_optionals_set` run asserts the attribute where it IS known at plan.

  # `parent_id` is reconstructed from the subscription in `virtual_hub_id` plus the
  # `resource_group_name` input, because AzAPI addresses the parent by resource ID and AzureRM
  # took an implicit subscription from the provider block.
  assert {
    condition     = azapi_resource.this["gw_a"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    error_message = "parent_id must be rebuilt as /subscriptions/<sub from virtual_hub_id>/resourceGroups/<resource_group_name>."
  }

  # `replace_triggers_external_values` USED TO BE ASSERTED HERE. It has been removed from the
  # module (azapi v2.12.0 `RequiresReplaceIfNotNull` does not fire when prior state is null, so
  # it planned an UPDATE at adoption instead of a replacement -- and the attribute has no
  # `skip_on:"update"` tag, so that alone PUTs the stale body and deletes the connections).
  #
  # Its job is now done by a precondition on the merge writer. This assertion covers the
  # PASSING side of that precondition -- the two operands agree on a create -- and
  # `tests/forcenew_replace_guard.tftest.hcl` covers the FAILING side, which needs prior state
  # and therefore its own file.
  assert {
    condition     = azapi_resource.this["gw_a"].replace_triggers_external_values == null && lower(azapi_resource.this["gw_a"].body.properties.virtualHub.id) == lower(var.expressroute_gateways["gw_a"].virtual_hub_id)
    error_message = "replace_triggers_external_values must stay unset, and the merge writer's ForceNew precondition must hold on a create: the full writer's body hub ID has to equal the configured virtual_hub_id."
  }

  # The merge writer is the only day-2 writer, and it must declare exactly what AzureRM's
  # Update could change -- and nothing else, above all not the connections array.
  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.properties.expressRouteConnections) && !can(azapi_update_resource.this["gw_a"].body.properties.virtualHub)
    error_message = "The merge writer must declare neither expressRouteConnections nor virtualHub: the first is owned elsewhere and the second is ForceNew, so AzureRM's Update could never send it."
  }

  # 🔴 REG-1, INVERTED IN 0.19.0. This assertion used to require the OPPOSITE -- that the merge
  # writer carried `tags` in its body -- and that is exactly what made REG-1: the merge
  # preserves every undeclared key of the live object (`utils/json.go` L52-L53), so a tag could
  # be added or changed but never REMOVED. Tags now travel on `azapi_resource_action.tags`, and
  # the merge writer must carry NO tags key at all, so that there is exactly one tag writer per
  # address after create. `!can()` rather than `== null`: a key absent from a Dynamic body is
  # not a null, it is a reference error.
  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.tags)
    error_message = "The merge writer must NOT carry a tags key in its body: a merge writer can never remove a tag (REG-1). Tags belong on azapi_resource_action.tags."
  }

  # `body` is a Dynamic attribute, so an empty map literal arrives as an empty OBJECT and
  # `object == map(string)` is false with only a warning. The check is therefore on presence
  # plus length rather than on equality -- the same HCL type-unification trap that was caught
  # on `expressroute-gateway-connection` (list side) on. `{}` and not an omitted key:
  # AzureRM parity, `tags.Expand(nil)` returns a pointer to an EMPTY map and never nil.
  assert {
    condition     = azapi_resource_action.tags["gw_a"].body.properties.tags != null && length(azapi_resource_action.tags["gw_a"].body.properties.tags) == 0
    error_message = "With tags null the tag writer must PUT an empty map, never a null and never an omitted key: an omitted key would mean 'send no tags at all' on a PUT that replaces the whole set."
  }
}

run "all_optionals_set" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                          = "ergw-full"
        virtual_hub_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        location                      = "uksouth"
        resource_group_name           = "rg-test"
        tags                          = { env = "test", owner = "alz" }
        allow_non_virtual_wan_traffic = true
        scale_units                   = 10
      }
    }
  }

  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.allowNonVirtualWanTraffic == true
    error_message = "allowNonVirtualWanTraffic must carry the configured value."
  }

  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.autoScaleConfiguration.bounds.min == 10
    error_message = "autoScaleConfiguration.bounds.min must carry the configured scale_units."
  }

  # 🔴 The HCL type-unification trap. A bare map literal in a test is an OBJECT, and
  # `object == map(string)` is false with only a warning, so the comparison has to be forced
  # onto the same type on BOTH sides. The list-typed form of the same bug was caught on
  # `expressroute-gateway-connection` (`tolist()` on both sides) on.
  assert {
    condition     = tomap(azapi_resource.this["gw_a"].tags) == tomap({ env = "test", owner = "alz" })
    error_message = "tags must carry the configured map verbatim."
  }

  # 🔴 REG-1's remedy. The merge writer must carry NO tags key, and the configured map must
  # appear on the tag writer instead, which PUTs at `Microsoft.Resources/tags/default` and
  # REPLACES the whole set. Same `tomap()`-on-both-sides discipline as above.
  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.tags)
    error_message = "The merge writer must NOT carry a tags key in its body: a merge writer can never remove a tag (REG-1)."
  }

  assert {
    condition     = tomap(azapi_resource_action.tags["gw_a"].body.properties.tags) == tomap({ env = "test", owner = "alz" })
    error_message = "The tag writer must carry the configured tags verbatim in body.properties.tags."
  }

  assert {
    condition     = azapi_update_resource.this["gw_a"].body.properties.autoScaleConfiguration.bounds.min == 10 && azapi_update_resource.this["gw_a"].body.properties.allowNonVirtualWanTraffic == true
    error_message = "The merge writer must carry every property AzureRM's Update could change (scale_units L187-L193, allow_non_virtual_wan_traffic L195-L197)."
  }

  # Still absent with every optional set. The array is never declared under any input.
  assert {
    condition     = !can(azapi_resource.this["gw_a"].body.properties.expressRouteConnections)
    error_message = "properties.expressRouteConnections must stay absent regardless of inputs."
  }
}

# Multiple gateways, distinct subscriptions, to prove the parent_id reconstruction is per-entry
# rather than accidentally shared, and that the merge writer is wired one-to-one.
run "multiple_gateways" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-a"
        virtual_hub_id      = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-a/providers/Microsoft.Network/virtualHubs/vhub-a"
        location            = "uksouth"
        resource_group_name = "rg-a"
        scale_units         = 2
      }
      gw_b = {
        name                = "ergw-b"
        virtual_hub_id      = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-b/providers/Microsoft.Network/virtualHubs/vhub-b"
        location            = "ukwest"
        resource_group_name = "rg-b"
        scale_units         = 3
      }
    }
  }

  assert {
    condition     = azapi_resource.this["gw_a"].parent_id == "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-a" && azapi_resource.this["gw_b"].parent_id == "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-b"
    error_message = "Each gateway's parent_id must be rebuilt from its OWN virtual_hub_id and resource_group_name."
  }

  assert {
    condition     = length(azapi_resource.this) == 2 && length(azapi_update_resource.this) == 2
    error_message = "There must be exactly one merge writer per full writer."
  }

  assert {
    condition     = output.resource_object["gw_b"].scale_units == 3 && output.resource_object["gw_b"].resource_group == "rg-b"
    error_message = "resource_object must project scale_units and resource_group from CONFIGURATION, not from the computed .output."
  }

  assert {
    condition     = length(output.resource) == 2 && length(output.resource_id) == 2
    error_message = "resource and resource_id must stay LISTS with one element per gateway, as they were under azurerm."
  }
}

run "empty_map" {
  command = plan

  variables {
    expressroute_gateways = {}
  }

  assert {
    condition     = length(azapi_resource.this) == 0 && length(azapi_update_resource.this) == 0
    error_message = "An empty expressroute_gateways map must create no resources."
  }

  assert {
    condition     = length(output.resource) == 0 && length(output.resource_id) == 0 && length(output.resource_object) == 0
    error_message = "An empty expressroute_gateways map must produce empty outputs, not null."
  }
}
