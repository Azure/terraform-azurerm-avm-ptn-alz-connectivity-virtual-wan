# REG-1'S REMEDY, `azapi_resource_action.tags`, tested on its own.
#
# WHAT REG-1 WAS. `azapi_update_resource` is a MERGE writer and `mergeObjectAtPath`'s map branch
# copies every key of the LIVE object that the new body does not mention straight into the
# request (`utils/json.go` L52-L53, `} else { res[key] = value }`, unconditional). So a merge
# writer can add a tag and change a tag but can NEVER REMOVE one. Removing a key from
# `firewalls[*].tags` produced a plan that looked right, an apply that succeeded, and a tag
# still live in Azure. AzureRM assigned the WHOLE expanded map (FW L262 + L276), so removal
# worked there.
#
# THE FIX. Tags left the merge writer's body and moved to a
# `Microsoft.Resources/tags@2021-04-01` PUT, which REPLACES the whole tag set. Measured live on
# in testing: the PUT deleted one tag, left two intact, and issued exactly ONE ARM
# write.
#
# `mock_provider` means no Azure calls, no credentials and no cost.
#
# 🔴 WHY `mock_resource` AND `mock_data` ARE REQUIRED AND NOT DECORATION. The default mock
# invents an 8-character token for every computed attribute, and `azapi_update_resource
# .resource_id`, this file's `azapi_resource_action.resource_id` and the hub-IP data source are
# all wired to `azapi_resource.fw[...].id`, which the provider validates as an ARM resource ID
# and rejects unless it starts with "/". Only the `command = apply` run below needs them, but
# the blocks are file-scoped.
mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-mock"
    }
  }

  # The hub IP data source is read during the apply run. Its values are asserted in
  # `hub_ip_outputs.tftest.hcl`; here it only has to not explode.
  mock_data "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-mock"
      output = {
        properties = {
          hubIPAddresses = {
            privateIPAddress = "10.0.0.4"
            publicIPs = {
              count     = 1
              addresses = [{ address = "20.0.0.1" }]
            }
          }
        }
      }
    }
  }
}

variables {
  diagnostic_settings = {}
  resource_types = {
    insights_diagnostic_settings = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
    network_azure_firewalls      = "Microsoft.Network/azureFirewalls@2025-07-01"
  }
}

# ---------------------------------------------------------------------------
# ONE TAG WRITER PER FIREWALL, AND ONLY WHERE A FIREWALL EXISTS.
#
# `command = plan`, deliberately. The tag writer's `body` and `method` are Optional and NOT
# Computed on `azapi_resource_action` (schema read from `terraform providers schema -json` at
# azapi 2.13.0), so the planned values are the CONFIGURED values and asserting them here is
# meaningful. `resource_id` interpolates an id that is unknown until apply, so it is checked in
# the apply run further down instead.
# ---------------------------------------------------------------------------
run "tag_writer_exists_per_firewall" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-tags-a"
        tags                = { env = "test", owner = "alz" }
      }
      fw_b = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-tags-b"
        tags                = null
      }
    }
  }

  # The action's `for_each` is the SAME map as the full writer's, so the two addresses have the
  # same instance keys: a tag writer exists if and only if a firewall does.
  #
  # 🔴 KEYS, NOT `can(...)` ON THE INSTANCE. `can(azapi_resource_action.tags["fw_a"])` evaluates
  # the whole instance object, several of whose attributes are unknown at plan, so the condition
  # comes back UNKNOWN and the run errors with "Unknown condition value" rather than failing.
  # `keys()` is static, so it is known at plan. `sort()` returns a list on both sides, so there
  # is no tuple-versus-list unification trap here.
  assert {
    condition     = sort(keys(azapi_resource_action.tags)) == sort(keys(azapi_resource.fw))
    error_message = "There must be exactly one tag writer per firewall, keyed identically to the full writer."
  }

  assert {
    condition     = tomap(azapi_resource_action.tags["fw_a"].body.properties.tags) == tomap({ env = "test", owner = "alz" })
    error_message = "The tag writer must carry the configured tags verbatim."
  }

  # 🔴 THE `{}` IS THE POINT, not an accident. This PUT replaces the whole tag set, so an
  # omitted `tags` key would mean "send no tags at all". `{}` is also AzureRM parity:
  # `tags.Expand(nil)` returns a pointer to an EMPTY map and never nil -- the normalisation
  # `local.firewall_tags` has always done and still does.
  assert {
    condition     = azapi_resource_action.tags["fw_b"].body.properties.tags != null && length(azapi_resource_action.tags["fw_b"].body.properties.tags) == 0
    error_message = "A firewall with null tags must still PUT an empty map, never a null and never an omitted key."
  }

  # The whole fix rests on this being a REPLACING PUT rather than another merge.
  assert {
    condition     = azapi_resource_action.tags["fw_a"].method == "PUT" && azapi_resource_action.tags["fw_a"].type == "Microsoft.Resources/tags@2021-04-01"
    error_message = "The tag writer must be a PUT against Microsoft.Resources/tags@2021-04-01: that is what replaces the whole tag set instead of merging into it."
  }

  # There must be exactly ONE tag writer per address after create, so the merge writer must have
  # shed its tags key on BOTH the tagged and the untagged firewall.
  assert {
    condition     = !can(azapi_update_resource.fw["fw_a"].body.tags) && !can(azapi_update_resource.fw["fw_b"].body.tags)
    error_message = "The merge writer must NOT carry a tags key in its body: a merge writer can never remove a tag (REG-1)."
  }
}

# ---------------------------------------------------------------------------
# NO FIREWALLS, NO TAG WRITERS. The other half of "iff".
# ---------------------------------------------------------------------------
run "no_firewalls_no_tag_writers" {
  command = plan

  variables {
    firewalls = {}
  }

  assert {
    condition     = length(azapi_resource_action.tags) == 0
    error_message = "With no firewalls configured there must be no tag writers: the action's for_each is the firewall map itself."
  }
}

# ---------------------------------------------------------------------------
# THE TARGET ID. `command = apply`, because `resource_id` interpolates
# `azapi_resource.fw[...].id`, which is unknown at plan.
#
# 🔴 THE FULL WRITER'S ID, NOT THE MERGE WRITER'S. `azapi_update_resource` has an `id` of its
# own that is NOT the ARM resource ID of the firewall, so wiring the action to it would PUT tags
# at a nonsense path. This assertion is what keeps that wrong.
#
# 🔴 `Microsoft.Resources/tags/default` IS AN ARM SINGLETON THAT ALWAYS EXISTS,
# which is why this is an `azapi_resource_action` and not an `azapi_resource`: there is nothing
# to create, only something to PUT. Do not "improve" it into a resource.
# ---------------------------------------------------------------------------
run "tag_writer_targets_the_full_writers_id" {
  command = apply

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-tags-a"
        tags                = { env = "test" }
      }
    }
  }

  assert {
    condition     = azapi_resource_action.tags["fw_a"].resource_id == "${azapi_resource.fw["fw_a"].id}/providers/Microsoft.Resources/tags/default"
    error_message = "The tag writer must target the FULL writer's ARM id plus /providers/Microsoft.Resources/tags/default."
  }
}
