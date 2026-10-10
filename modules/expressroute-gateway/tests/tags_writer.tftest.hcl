# REG-1'S REMEDY, `azapi_resource_action.tags`, tested on its own.
#
# WHAT REG-1 WAS. `azapi_update_resource` is a MERGE writer and `mergeObjectAtPath`'s map branch
# copies every key of the LIVE object that the new body does not mention straight into the request
# (`utils/json.go` L52-L53, `} else { res[key] = value }`, unconditional). So a merge writer can
# add a tag and change a tag but can NEVER REMOVE one. Removing a key from `tags` produced a plan
# that looked right, an apply that succeeded, and a tag still live in Azure. AzureRM's update
# assigned the WHOLE expanded map, so removal worked there.
#
# THE FIX. Tags left the merge writer's body and moved to a `Microsoft.Resources/tags@2021-04-01`
# PUT, which REPLACES the whole tag set. Observed in testing: the PUT deleted one
# tag, left two intact, and issued exactly ONE ARM write.
#
# `mock_provider` means no Azure calls, no credentials and no cost.
#
# 🔴 WHY `mock_resource` IS REQUIRED AND NOT DECORATION. The default mock generates an
# 8-character random string for every computed attribute, and both `azapi_update_resource
# .resource_id` and this file's `azapi_resource_action.resource_id` are wired to
# `azapi_resource.this[...].id`, which the provider validates as an ARM resource ID and rejects
# unless it starts with "/". Only the `command = apply` run below needs it, but the block is
# file-scoped.
mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteGateways/ergw-tags"
    }
  }
}

variables {
  resource_types = {
    network_express_route_gateways = "Microsoft.Network/expressRouteGateways@2025-07-01"
  }
}

# ------------------------------------------------------------------------------------------------
# ONE TAG WRITER PER GATEWAY, AND ONLY WHERE A GATEWAY EXISTS.
#
# `command = plan`, deliberately. The tag writer's `body` and `method` are Optional and NOT
# Computed on `azapi_resource_action` (schema read from `terraform providers schema -json` at
# azapi 2.13.0), so the planned values are the CONFIGURED values and asserting them here is
# meaningful. `resource_id` interpolates an id that is unknown until apply, so it is checked in
# the apply run further down instead.
# ------------------------------------------------------------------------------------------------
run "tag_writer_exists_per_gateway" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-tags-a"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        tags                = { env = "test", owner = "alz" }
      }
      gw_b = {
        name                = "ergw-tags-b"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
      }
    }
  }

  # The action's `for_each` is the SAME map as the full writer's, so the two addresses have the
  # same instance keys: a tag writer exists if and only if a gateway does.
  #
  # 🔴 KEYS, NOT `can(...)` ON THE INSTANCE. `can(azapi_resource_action.tags["gw_a"])` evaluates
  # the whole instance object, several of whose attributes are unknown at plan, so the condition
  # comes back UNKNOWN and the run errors with "Unknown condition value" rather than failing.
  # `keys()` is static, so it is known at plan. `sort()` returns a list on both sides, so there
  # is no tuple-versus-list unification trap here.
  assert {
    condition     = sort(keys(azapi_resource_action.tags)) == sort(keys(azapi_resource.this))
    error_message = "There must be exactly one tag writer per gateway, keyed identically to the full writer."
  }

  assert {
    condition     = tomap(azapi_resource_action.tags["gw_a"].body.properties.tags) == tomap({ env = "test", owner = "alz" })
    error_message = "The tag writer must carry the configured tags verbatim."
  }

  # 🔴 THE `{}` IS THE POINT, not an accident. This PUT replaces the whole tag set, so an omitted
  # `tags` key would mean "send no tags at all". `{}` is also AzureRM parity: `tags.Expand(nil)`
  # returns a pointer to an EMPTY map and never nil.
  assert {
    condition     = azapi_resource_action.tags["gw_b"].body.properties.tags != null && length(azapi_resource_action.tags["gw_b"].body.properties.tags) == 0
    error_message = "A gateway with no tags must still PUT an empty map, never a null and never an omitted key."
  }

  # The whole fix rests on this being a REPLACING PUT rather than another merge.
  assert {
    condition     = azapi_resource_action.tags["gw_a"].method == "PUT" && azapi_resource_action.tags["gw_a"].type == "Microsoft.Resources/tags@2021-04-01"
    error_message = "The tag writer must be a PUT against Microsoft.Resources/tags@2021-04-01: that is what replaces the whole tag set instead of merging into it."
  }

  # There must be exactly ONE tag writer per address after create, so the merge writer must have
  # shed its tags key on BOTH the tagged and the untagged gateway.
  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.tags) && !can(azapi_update_resource.this["gw_b"].body.tags)
    error_message = "The merge writer must NOT carry a tags key in its body: a merge writer can never remove a tag (REG-1)."
  }
}

# ------------------------------------------------------------------------------------------------
# NO GATEWAYS, NO TAG WRITERS. The other half of "iff".
# ------------------------------------------------------------------------------------------------
run "no_gateways_no_tag_writers" {
  command = plan

  variables {
    expressroute_gateways = {}
  }

  assert {
    condition     = length(azapi_resource_action.tags) == 0
    error_message = "With no gateways configured there must be no tag writers: the action's for_each is the gateway map itself."
  }
}

# ------------------------------------------------------------------------------------------------
# THE TARGET ID. `command = apply`, because `resource_id` interpolates `azapi_resource.this[...]
# .id`, which is unknown at plan.
#
# 🔴 THE FULL WRITER'S ID, NOT THE MERGE WRITER'S. `azapi_update_resource` has an `id` of its own
# that is NOT the ARM resource ID of the gateway, so wiring the action to it would PUT tags at a
# nonsense path. This assertion is what keeps that wrong.
#
# 🔴 `Microsoft.Resources/tags/default` IS AN ARM SINGLETON THAT ALWAYS EXISTS, which
# is why this is an `azapi_resource_action` and not an `azapi_resource`: there is nothing to
# create, only something to PUT. Do not "improve" it into a resource.
# ------------------------------------------------------------------------------------------------
run "tag_writer_targets_the_full_writers_id" {
  command = apply

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-tags-a"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        tags                = { env = "test" }
      }
    }
  }

  assert {
    condition     = azapi_resource_action.tags["gw_a"].resource_id == "${azapi_resource.this["gw_a"].id}/providers/Microsoft.Resources/tags/default"
    error_message = "The tag writer must target the FULL writer's ARM id plus /providers/Microsoft.Resources/tags/default."
  }
}
