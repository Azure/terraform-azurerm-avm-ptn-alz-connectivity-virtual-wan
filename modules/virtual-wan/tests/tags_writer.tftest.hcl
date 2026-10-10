# REG-1'S REMEDY, `azapi_resource_action.p2s_gateway_vpn_server_configuration_tags`, tested on its
# own -- plus the premise that keeps `azapi_resource.p2s_gateway` OUT of the remedy honest.
#
# WHAT REG-1 WAS. `azapi_update_resource` is a MERGE writer and `mergeObjectAtPath`'s map branch
# copies every key of the LIVE object that the new body does not mention straight into the request
# (`utils/json.go` L52-L53, `} else { res[key] = value }`, unconditional). So a merge writer can
# add a tag and change a tag but can NEVER REMOVE one. Removing a key from
# `p2s_gateway_vpn_server_configurations[*].tags` produced a plan that looked right, an apply that
# succeeded, and a tag still live in Azure. AzureRM's Update assigned the WHOLE expanded map
# (`vpn_server_configuration_resource.go` L571-L573), so removal worked there. Observed in testing.
#
# THE FIX. Tags left the merge writer's body and moved to a `Microsoft.Resources/tags@2021-04-01`
# PUT, which REPLACES the whole tag set. Observed in testing: the PUT deleted one
# tag, left two intact, and issued exactly ONE ARM write.
#
# 🔴 ONLY THE VPN SERVER CONFIGURATION GETS A TAG WRITER. `azapi_resource.p2s_gateway` is a PLAIN
# `azapi_resource` whose `tags` argument drives a whole-object PUT on every change -- neither
# `body` nor `tags` is in its `lifecycle.ignore_changes` -- so tag REMOVAL already worked there and
# a second writer would be a needless extra ARM call. That premise is load-bearing, and the last
# two runs in this file are what stop it regressing silently.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "11111111-1111-1111-1111-111111111111"
    }
  }

  # ⚠️ REQUIRED FOR `command = apply`, AND IT IS A LIE THAT HAS TO BE UNDERSTOOD -- the same lie
  # as in `p2s_vpn_gateway.tftest.hcl`. Without it the mock invents an 8-character random string
  # for every computed `id`, and `azapi_update_resource.resource_id` rejects it with "invalid
  # resource ID: resource id '...' must start with '/'". The override hands EVERY `azapi_resource`
  # in the module the SAME well-formed ARM ID, so no assertion here may read `.id` and expect it to
  # identify a particular resource. The `resource_id` assertion below reads it only as a PREFIX of
  # the tag writer's own `resource_id`, which is exactly the relationship under test.
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnServerConfigurations/mock"
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
  virtual_hubs = {
    hub_a = {
      name                = "vhub-a"
      location            = "eastus"
      resource_group_name = "rg-test"
      address_prefix      = "10.0.0.0/23"
    }
  }
}

# ------------------------------------------------------------------------------------------------
# ONE TAG WRITER PER VPN SERVER CONFIGURATION, AND ONLY WHERE ONE EXISTS.
#
# `command = plan`, deliberately. The tag writer's `body` and `method` are Optional and NOT
# Computed on `azapi_resource_action` (schema read from `terraform providers schema -json` at azapi
# 2.13.0), so the planned values are the CONFIGURED values and asserting them here is meaningful.
# `resource_id` interpolates an id that is unknown until apply, so it is checked in the apply run
# further down instead.
# ------------------------------------------------------------------------------------------------
run "tag_writer_exists_per_vpn_server_configuration" {
  command = plan

  variables {
    p2s_gateway_vpn_server_configurations = {
      cfg_tagged = {
        name                     = "vpnsc-tagged"
        virtual_hub_key          = "hub_a"
        vpn_authentication_types = ["Certificate"]
        tags                     = { env = "test", owner = "alz" }
      }
      cfg_bare = {
        name                     = "vpnsc-bare"
        virtual_hub_key          = "hub_a"
        vpn_authentication_types = ["Certificate"]
      }
    }
    p2s_gateways = {}
  }

  # The action's `for_each` is the SAME map as the full writer's, so the two addresses have the
  # same instance keys: a tag writer exists if and only if a configuration does.
  #
  # 🔴 KEYS, NOT `can(...)` ON THE INSTANCE. `can(azapi_resource_action.…["cfg_tagged"])`
  # evaluates the whole instance object, several of whose attributes are unknown at plan, so the
  # condition comes back UNKNOWN and the run errors with "Unknown condition value" rather than
  # failing. `keys()` is static, so it is known at plan. `sort()` returns a list on both sides, so
  # there is no tuple-versus-list unification trap here.
  assert {
    condition     = sort(keys(azapi_resource_action.p2s_gateway_vpn_server_configuration_tags)) == sort(keys(azapi_resource.p2s_gateway_vpn_server_configuration))
    error_message = "There must be exactly one tag writer per VPN server configuration, keyed identically to the full writer."
  }

  assert {
    condition     = tomap(azapi_resource_action.p2s_gateway_vpn_server_configuration_tags["cfg_tagged"].body.properties.tags) == tomap({ env = "test", owner = "alz" })
    error_message = "The tag writer must carry the configured tags verbatim."
  }

  # 🔴 THE `{}` IS THE POINT, not an accident, and it is the ONE deliberate change from the
  # expression the merge writer used: that one SPLICED the key in only when tags were non-null, so
  # an untagged configuration had no `tags` key at all. On a merge, an omitted key means "leave the
  # live tags alone". On this PUT, which replaces the whole set, it would mean "send no tags at
  # all". `{}` is also AzureRM parity: `tags.Expand(nil)` returns a pointer to an EMPTY map and
  # never nil.
  assert {
    condition     = azapi_resource_action.p2s_gateway_vpn_server_configuration_tags["cfg_bare"].body.properties.tags != null && length(azapi_resource_action.p2s_gateway_vpn_server_configuration_tags["cfg_bare"].body.properties.tags) == 0
    error_message = "A configuration with no tags must still PUT an empty map, never a null and never an omitted key."
  }

  # The whole fix rests on this being a REPLACING PUT rather than another merge.
  assert {
    condition     = azapi_resource_action.p2s_gateway_vpn_server_configuration_tags["cfg_tagged"].method == "PUT" && azapi_resource_action.p2s_gateway_vpn_server_configuration_tags["cfg_tagged"].type == "Microsoft.Resources/tags@2021-04-01"
    error_message = "The tag writer must be a PUT against Microsoft.Resources/tags@2021-04-01: that is what replaces the whole tag set instead of merging into it."
  }

  # There must be exactly ONE tag writer per address after create, so the merge writer must have
  # shed its tags key on BOTH the tagged and the untagged configuration.
  assert {
    condition     = !can(azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_tagged"].body.tags) && !can(azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.tags)
    error_message = "The merge writer must NOT carry a tags key in its body: a merge writer can never remove a tag (REG-1)."
  }

  # 🔴 AND NO TAG WRITER FOR THE GATEWAY. `azapi_resource.p2s_gateway` needs none, and adding one
  # would be a second ARM write per apply for no behaviour. The address does not exist.
  assert {
    condition     = length(azapi_resource_action.p2s_gateway_vpn_server_configuration_tags) == length(azapi_resource.p2s_gateway_vpn_server_configuration)
    error_message = "Tag writers must be created for VPN server configurations only."
  }
}

# ------------------------------------------------------------------------------------------------
# THE TARGET ID. `command = apply`, because `resource_id` interpolates
# `azapi_resource.p2s_gateway_vpn_server_configuration[...].id`, which is unknown at plan.
#
# 🔴 THE FULL WRITER'S ID, NOT THE MERGE WRITER'S. `azapi_update_resource` has an `id` of its own
# that is NOT the ARM resource ID of the configuration, so wiring the action to it would PUT tags
# at a nonsense path. This assertion is what keeps that wrong.
#
# 🔴 `Microsoft.Resources/tags/default` IS AN ARM SINGLETON THAT ALWAYS EXISTS, which
# is why this is an `azapi_resource_action` and not an `azapi_resource`: there is nothing to
# create, only something to PUT. Do not "improve" it into a resource.
# ------------------------------------------------------------------------------------------------
run "tag_writer_targets_the_full_writers_id" {
  command = apply

  variables {
    p2s_gateway_vpn_server_configurations = {
      cfg_tagged = {
        name                     = "vpnsc-tagged"
        virtual_hub_key          = "hub_a"
        vpn_authentication_types = ["Certificate"]
        tags                     = { env = "test" }
      }
    }
    p2s_gateways = {}
  }

  assert {
    condition     = azapi_resource_action.p2s_gateway_vpn_server_configuration_tags["cfg_tagged"].resource_id == "${azapi_resource.p2s_gateway_vpn_server_configuration["cfg_tagged"].id}/providers/Microsoft.Resources/tags/default"
    error_message = "The tag writer must target the FULL writer's ARM id plus /providers/Microsoft.Resources/tags/default."
  }
}

# ------------------------------------------------------------------------------------------------
# 🔴 THE PREMISE THAT KEEPS `azapi_resource.p2s_gateway` OUT OF SCOPE.
#
# The p2s gateway gets NO tag writer, and the entire justification is that `tags` is ABSENT from
# its `lifecycle.ignore_changes` list, so changing the tag map drives a whole-object PUT and
# removal already works. If somebody adds `tags` (or `body`) to that list -- the way the four
# candidate-1 full writers legitimately do -- the gateway would silently join REG-1 with nothing
# to catch it.
#
# 🔴 WHY THIS IS TWO `command = apply` RUNS AND CANNOT BE A PLAN. `ignore_changes` only has an
# effect when there IS prior state: with none, the planned value comes straight from configuration
# and the assertion would pass whatever the lifecycle block said -- the plan-only trap. The first
# run lays down a gateway with TWO tags; the second removes one and asserts the planned/applied
# value followed the configuration DOWN to one. Under `ignore_changes = [tags]` the second run's
# value would still be the prior state's two tags and the assertion goes red.
#
# `terraform test` carries state across `command = apply` runs within a file, which is what makes
# the pair work.
# ------------------------------------------------------------------------------------------------
run "p2s_gateway_genesis_with_two_tags" {
  command = apply

  variables {
    p2s_gateway_vpn_server_configurations = {
      cfg_gw = {
        name                     = "vpnsc-gw"
        virtual_hub_key          = "hub_a"
        vpn_authentication_types = ["Certificate"]
      }
    }
    p2s_gateways = {
      gw_a = {
        name                                     = "p2sgw-tags"
        virtual_hub_key                          = "hub_a"
        scale_unit                               = 1
        p2s_gateway_vpn_server_configuration_key = "cfg_gw"
        tags                                     = { keep = "1", drop = "2" }
        connection_configuration = {
          name = "conn-a"
          vpn_client_address_pool = {
            address_prefixes = ["10.100.0.0/24"]
          }
        }
      }
    }
  }

  # Without this the next run could be comparing one tag against one tag and passing vacuously.
  assert {
    condition     = length(azapi_resource.p2s_gateway["gw_a"].tags) == 2 && azapi_resource.p2s_gateway["gw_a"].tags["drop"] == "2"
    error_message = "Genesis must put BOTH tags on the gateway, otherwise the removal run below proves nothing."
  }
}

run "p2s_gateway_tag_removal_is_not_ignored" {
  command = apply

  variables {
    p2s_gateway_vpn_server_configurations = {
      cfg_gw = {
        name                     = "vpnsc-gw"
        virtual_hub_key          = "hub_a"
        vpn_authentication_types = ["Certificate"]
      }
    }
    p2s_gateways = {
      gw_a = {
        name                                     = "p2sgw-tags"
        virtual_hub_key                          = "hub_a"
        scale_unit                               = 1
        p2s_gateway_vpn_server_configuration_key = "cfg_gw"
        tags                                     = { keep = "1" }
        connection_configuration = {
          name = "conn-a"
          vpn_client_address_pool = {
            address_prefixes = ["10.100.0.0/24"]
          }
        }
      }
    }
  }

  # 🔴 THIS IS THE ASSERTION THAT STANDS IN FOR "tags IS NOT IN ignore_changes". With `tags`
  # ignored, the prior state's two-key map would win and `drop` would still be here.
  assert {
    condition     = length(azapi_resource.p2s_gateway["gw_a"].tags) == 1 && !can(azapi_resource.p2s_gateway["gw_a"].tags["drop"])
    error_message = "Removing a key from a p2s gateway's tags must remove it from the resource: `tags` must NOT be in azapi_resource.p2s_gateway's lifecycle.ignore_changes, or the gateway silently joins REG-1."
  }

  assert {
    condition     = azapi_resource.p2s_gateway["gw_a"].tags["keep"] == "1"
    error_message = "Removing one tag must not disturb the others."
  }

  # The gateway carries its tags as a RESOURCE ARGUMENT, not as a body key: a whole-object PUT is
  # what replaces the set, and `body.tags` would be neither read nor written by that path.
  assert {
    condition     = !can(azapi_resource.p2s_gateway["gw_a"].body.tags)
    error_message = "The p2s gateway must carry tags on its `tags` argument, never in `body`."
  }
}
