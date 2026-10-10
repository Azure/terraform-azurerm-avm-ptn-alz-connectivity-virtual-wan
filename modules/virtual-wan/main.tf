# AzAPI addresses every resource by ARM resource ID, where AzureRM took a resource group
# NAME plus an implicit subscription from the provider block. This is a provider migration
# in place, so the module's public variable shape is preserved and the missing subscription
# segment is read from the provider once, here.
data "azapi_client_config" "current" {}

resource "azapi_resource" "rg" {
  count = var.create_resource_group ? 1 : 0

  location  = var.location
  name      = var.resource_group_name
  parent_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  type      = var.resource_types.resources_resource_groups
  # `azurerm_resource_group` sends nothing but `location` and `tags` (it never set
  # `managedBy`), and AzAPI folds both of those into the request from the arguments below,
  # so there is no body to build.
  ignore_body_changes = length(var.ignore_body_changes.resources_resource_groups) > 0 ? var.ignore_body_changes.resources_resource_groups : null
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left
  # unset is absent from the request rather than sent as an explicit JSON null.
  ignore_null_property = true
  # ✅ `response_export_values` IS SET, per AVM spec TFFR4 (Severity-MUST, Class-Pattern):
  # an AzAPI resource MUST declare the attribute, "even if empty". The earlier repo-wide
  # removal breached that MUST and is RETRACTED. `[]` is the right value -- nothing
  # reads this resource's `.output`, and the computed-output rule keeps a computed `.output` out of a
  # module output.
  #
  # 🔴 It is paired with the `ignore_changes` entry below and must stay paired. The
  # attribute carries NO `skip_on` tag (`azapi_resource.go` L77), so at ADOPTION a `null`
  # state against a `[]` config is a difference that alone defeats
  # `skip.CanSkipExternalRequest` and PUTs the stale `state.body`. `ignore_changes` keeps the
  # prior value, so there is no such diff.
  #
  # 🔴 A FUTURE CHANGE TO THIS EXPORT LIST NEEDS ITS OWN MIGRATION: `ignore_changes` pins
  # the prior value, so a new list is a no-op until a state operation is performed.
  response_export_values = []
  retry                  = local.retry
  # Preserved verbatim from the AzureRM resource, including the `try`: `var.tags` defaults
  # to null, `merge` rejects a null argument, and the fallback is the null itself.
  # tflint-ignore: avm_azapi_resource_tags_required // the rule wants exactly `tags = var.tags`. These are PER-INSTANCE tags carried on a collection variable, which is the v0.17.2 public API; forcing a single module-wide `var.tags` is a BREAKING interface change. Tracked for the next major.
  tags = try(merge(var.resource_group_tags, var.tags), var.tags)

  timeouts {
    create = local.timeouts.resources_resource_groups.create
    delete = local.timeouts.resources_resource_groups.delete
    read   = local.timeouts.resources_resource_groups.read
    update = local.timeouts.resources_resource_groups.update
  }
}

resource "azapi_resource" "virtual_wan" {
  count = local.create_virtual_wan ? 1 : 0

  location  = var.location
  name      = var.virtual_wan_name
  parent_id = local.resource_group_resource_id
  type      = var.resource_types.network_virtual_wans
  body = {
    properties = {
      allowBranchToBranchTraffic     = var.allow_branch_to_branch_traffic
      disableVpnEncryption           = var.disable_vpn_encryption
      office365LocalBreakoutCategory = var.office365_local_breakout_category
      type                           = var.type
    }
  }
  ignore_body_changes = length(var.ignore_body_changes.network_virtual_wans) > 0 ? var.ignore_body_changes.network_virtual_wans : null
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left
  # unset is absent from the request rather than sent as an explicit JSON null.
  ignore_null_property = true
  # ✅ `response_export_values` IS SET, per AVM spec TFFR4 (Severity-MUST, Class-Pattern):
  # an AzAPI resource MUST declare the attribute, "even if empty". The earlier repo-wide
  # removal breached that MUST and is RETRACTED. `[]` is the right value -- nothing
  # reads this resource's `.output`, and the computed-output rule keeps a computed `.output` out of a
  # module output.
  #
  # 🔴 It is paired with the `ignore_changes` entry below and must stay paired. The
  # attribute carries NO `skip_on` tag (`azapi_resource.go` L77), so at ADOPTION a `null`
  # state against a `[]` config is a difference that alone defeats
  # `skip.CanSkipExternalRequest` and PUTs the stale `state.body`. `ignore_changes` keeps the
  # prior value, so there is no such diff.
  #
  # 🔴 A FUTURE CHANGE TO THIS EXPORT LIST NEEDS ITS OWN MIGRATION: `ignore_changes` pins
  # the prior value, so a new list is a no-op until a state operation is performed.
  response_export_values = []
  retry                  = local.retry
  # ARM persisted this property in the recorded 2025-07-01 probe, despite AzAPI's
  # read-only schema. The exception disables validation of this whole WAN body.
  # See docs/MIGRATION-DEVIATIONS.md.
  schema_validation_enabled = false
  # `var.tags` defaults to null and `merge` rejects a null argument, which made the original
  # expression a hard error whenever the consumer left `tags` unset. Guarded rather than
  # preserved: the null-into-function class caused a live apply failure on.
  # tflint-ignore: avm_azapi_resource_tags_required // the rule wants exactly `tags = var.tags`. These are PER-INSTANCE tags carried on a collection variable, which is the v0.17.2 public API; forcing a single module-wide `var.tags` is a BREAKING interface change. Tracked for the next major.
  tags = merge(var.tags != null ? var.tags : {}, var.virtual_wan_tags)

  timeouts {
    create = local.timeouts.network_virtual_wans.create
    delete = local.timeouts.network_virtual_wans.delete
    read   = local.timeouts.network_virtual_wans.read
    update = local.timeouts.network_virtual_wans.update
  }
}

# 🔴 A `moved` BLOCK WAS DELETED HERE, and deleting it was the SAFE act.
#
#   moved {
#     from = azurerm_virtual_wan.virtual_wan
#     to   = azurerm_virtual_wan.virtual_wan[0]
#   }
#
# Its `to` address NO LONGER EXISTS: the virtual WAN is now `azapi_resource`, migrated by 46eecc6.
#
# A `moved` block whose `to` is not in configuration does NOT error and does NOT
# warn. `terraform validate` is clean. Terraform moves the state entry to the new
# address, finds nothing declaring it, and plans to DESTROY the live resource:
#
#     # <addr> will be destroyed
#     # (because <old> was moved to <new>, which is not in configuration)
#     Plan: 1 to add, 0 to change, 1 to destroy.
#
# MEASURED, the dangling-`moved` measurement, with a
# hand-written state and `-refresh=false` -- no Azure involved.
#
# Deleting it is safe because the module's supported floor is v0.12.0 and the
# upgrade guide covers anything older. A consumer still on a pre-v0.12.0 state
# follows the guide, not this block.

module "virtual_hubs" {
  source = "../virtual-hub"

  # TFFR6 / TFFR7 / TFFR8 interface cascade -- register and neutrality argument
  # are in `main.express_route_gateway.tf` on `module "express_route_gateways"`.
  ignore_body_changes = var.ignore_body_changes.network_virtual_hubs
  resource_types      = var.resource_types.network_virtual_hubs
  retry               = var.retry
  # Orders the hub tags write after the firewall policy writes. See `tags_depends_on` in `../virtual-hub`.
  tags_depends_on = compact([for value in values(var.firewalls) : value.firewall_policy_id])
  timeouts        = var.timeouts
  virtual_hubs = {
    for key, value in local.virtual_hubs : key => {
      name                                   = value.name
      location                               = value.location
      resource_group_name                    = value.resource_group_name
      address_prefix                         = value.address_prefix
      virtual_wan_id                         = local.effective_virtual_wan_id
      hub_routing_preference                 = value.hub_routing_preference
      sku                                    = value.sku
      tags                                   = value.tags
      virtual_router_auto_scale_min_capacity = value.virtual_router_auto_scale_min_capacity
    }
  }
}

# The `moved` block that used to sit here was DELETED.
#
#   moved {
#     from = azurerm_virtual_hub.virtual_hub
#     to   = module.virtual_hubs.azurerm_virtual_hub.virtual_hub
#   }
#
# Its `to` address stopped existing when modules/virtual-hub migrated to azapi.
# A `moved` whose `to` is not in configuration does NOT error and does NOT
# warn -- `terraform validate` stays clean. Terraform moves the state entry to
# the new address, finds nothing declaring it, and plans to DESTROY the live
# resource. Measured (dangling `moved` check).
#
# Safe to delete: the supported upgrade floor is v0.12.0 and docs/upgrade-guide.md
# covers anything older. Anyone upgrading across this boundary needs a `removed`
# + `import` pair, not a `moved`.

resource "azapi_resource" "virtual_hub_route_table" {
  for_each = var.virtual_hub_route_tables

  name                = each.value.name
  parent_id           = module.virtual_hubs.resource_id[each.value.virtual_hub_key]
  type                = var.resource_types.network_virtual_hubs_hub_route_tables
  body                = local.virtual_hub_route_table_bodies[each.key]
  ignore_body_changes = length(var.ignore_body_changes.network_virtual_hubs_hub_route_tables) > 0 ? var.ignore_body_changes.network_virtual_hubs_hub_route_tables : null
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left
  # unset is absent from the request rather than sent as an explicit JSON null. Null VALUES
  # only -- `labels` and `routes` are still emitted as empty lists above.
  ignore_null_property = true
  # ✅ `response_export_values` IS SET, per AVM spec TFFR4 (Severity-MUST, Class-Pattern):
  # an AzAPI resource MUST declare the attribute, "even if empty". `[]` is the right value --
  # nothing reads this resource's `.output`.
  #
  # ⛔ NO `lifecycle { ignore_changes = [response_export_values] }` -- WITHDRAWN, AND IT MUST
  # NOT COME BACK. This site is "armed": `ignore_body_changes`/`ignore_null_property` leave
  # `body` free, so `skip.CanSkipExternalRequest` is false and a PUT does occur. Pinning
  # `response_export_values` here reproduces BUG 3: the pin freezes `plan.Output` to the stale
  # null-derived default projection while the writer still PUTs at adoption, so the applied
  # output disagrees with the planned one -> "Error: Provider produced inconsistent result
  # after apply" on first apply after upgrade. Do not copy this withdrawal onto a Class A
  # (fully silent) writer -- there, pinning costs nothing extra since no PUT happens, and BUG 3
  # cannot fire either way.
  response_export_values = []
  retry                  = local.retry

  timeouts {
    create = local.timeouts.network_virtual_hubs_hub_route_tables.create
    delete = local.timeouts.network_virtual_hubs_hub_route_tables.delete
    read   = local.timeouts.network_virtual_hubs_hub_route_tables.read
    update = local.timeouts.network_virtual_hubs_hub_route_tables.update
  }
}

# =============================================================================
# AzureRM -> AzAPI state moves (`avm-tf-migration` SKILL.md L66-78)
#
# The provider migration is IN PLACE: same module, same `for_each`/`count`
# boundary, same keys, so every move is a whole-resource move and the consumer
# only bumps the module version. Plan with a normal refresh -- see
# `docs/upgrade-guide.md`; `-refresh=false` hits azapi#1227 and plans a replace.
# =============================================================================

moved {
  from = azurerm_virtual_wan.virtual_wan
  to   = azapi_resource.virtual_wan
}

moved {
  from = azurerm_resource_group.rg
  to   = azapi_resource.rg
}

moved {
  from = azurerm_virtual_hub_route_table.virtual_hub_route_table
  to   = azapi_resource.virtual_hub_route_table
}
