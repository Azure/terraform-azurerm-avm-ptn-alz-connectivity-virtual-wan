# ===========================================================================
# v0.17.2 OUTPUT PARITY -- names, container types, and the null contract.
#
# WHY THIS FILE EXISTS. `output "resource"` was changed from
#
#     value = var.firewalls != null ? { for key, value in azapi_resource.fw : key => value } : {}
#
# to
#
#     value = azapi_resource.fw
#
# The conditional was dead code: `azapi_resource.fw` is driven by
# `local.firewalls` (`locals.tf` ~L35), which is `var.firewalls != null ?
# var.firewalls : {}` and therefore NEVER null, so the false branch was
# unreachable and the true branch already produced `{}` for a null input. The
# new form is also the closer structural match to the baseline, which
# published the raw resource map rather than a re-comprehension of it.
#
# 🔵 THE BASELINE. `Azure/terraform-azurerm-avm-ptn-alz-connectivity-virtual-wan`
# at tag `v0.17.2` (commit `4b820779dfe8c1b82e67908b40ed630c7d476104`, blob
# `ca143fd20190efd6c030e9dae519bc8bc828e0f3` for `modules/firewall/outputs.tf`).
# At that tag the module was AzureRM-based -- `resource "azurerm_firewall" "fw"`
# with `for_each = var.firewalls != null ? var.firewalls : {}` -- and the
# output read:
#
#     output "resource" {
#       description = "Azure Firewall resource"
#       value       = var.firewalls != null ? azurerm_firewall.fw : {}
#     }
#
# ===========================================================================
# ⛔ WHAT THIS TEST DOES NOT PROVE. READ THIS BEFORE CITING IT AS "PARITY".
#
# It does NOT prove that a v0.17.2 consumer's expressions still evaluate. The
# map ELEMENT type changed provider: `azurerm_firewall` and `azapi_resource`
# are different schemas and their attribute sets are NOT the same. Anything a
# consumer read off `module.firewalls.resource[key]` beyond `id` / `name` /
# `location` / `tags` is GONE, and the `divergence` run below asserts that it
# is gone rather than pretending otherwise. That is a real breaking change in
# the element type; this file records its exact boundary, it does not close it.
#
# It also cannot enumerate the module's outputs. `terraform test` can only
# reference `output.<name>`, so this file proves that every v0.17.2 name still
# RESOLVES; it cannot prove no name was ADDED. (One was:
# `full_writer_ignored_attributes`. Additive, so not a consumer break.)
#
# What it DOES prove, and all it proves:
#   1. All nine v0.17.2 output names still exist and evaluate.
#   2. Each one's CONTAINER type and keying are unchanged (map keyed by the
#      `var.firewalls` key / list, per output).
#   3. The v0.17.2 NULL CONTRACT survives -- the four outputs that collapsed to
#      `null` still do, and the five that collapsed to an empty collection
#      still do. This is the dimension the `output "resource"` edit could have
#      broken, and it is the reason this file was written.
#   4. For `resource`, the exact set of element members that did and did not
#      survive the provider change.
#
# mock_provider means no Azure calls, no credentials and no cost.
# ===========================================================================

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      # The mock provider generates a random 8-character `id`, which is
      # rejected by anything expecting a well-formed ARM resource ID.
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-mock"
    }
  }

  mock_data "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-mock"
      output = {
        properties = {
          hubIPAddresses = {
            privateIPAddress = "10.100.0.68"
            publicIPs = {
              count     = 1
              addresses = [{ address = "20.90.1.10" }]
            }
          }
        }
      }
    }
  }
}

variables {
  diagnostic_settings = {}
}

# ---------------------------------------------------------------------------
# 1 + 2. Every v0.17.2 name resolves, and every container type and key set is
#        the baseline one.
#
# 🔴 `command = apply`, not `plan`. Under `plan` the hub-IP data source keys
# off an id that does not exist yet, so `private_ip_address` and
# `public_ip_addresses` are unknown and an assertion on them is an ERROR, not
# a failure. The genesis apply makes them concrete.
# ---------------------------------------------------------------------------
run "v0_17_2_names_and_container_types" {
  command = apply

  variables {
    firewalls = {
      # Deliberately NOT equal to the resource `name`. v0.17.2 keyed the maps
      # by the `var.firewalls` key, not by the Azure resource name, and a
      # consumer indexes with the former.
      hub_uksouth = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-uksouth"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "afw-uksouth"
      }
      hub_ukwest = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-ukwest"
        location            = "ukwest"
        resource_group_name = "rg-test"
        sku_tier            = "Premium"
        name                = "afw-ukwest"
      }
    }
  }

  # --- `resource`: map keyed by the var.firewalls key. v0.17.2 published the
  #     raw `azurerm_firewall.fw` map; this publishes the raw
  #     `azapi_resource.fw` map. Same container, same keying. ---
  #
  # 🔴 `tolist()` on both sides is load-bearing: a bare list literal is a
  # TUPLE, and `tuple == list(string)` is FALSE with nothing but a warning.
  assert {
    condition     = tolist(sort(keys(output.resource))) == tolist(["hub_uksouth", "hub_ukwest"])
    error_message = "output.resource must be keyed by the var.firewalls keys, as azurerm_firewall.fw was at v0.17.2 -- not by the Azure resource name."
  }

  assert {
    condition     = length(output.resource) == 2
    error_message = "output.resource must carry one entry per firewall."
  }

  # --- `resource_ids` / `resource_names`: map(string), same keys ---
  assert {
    condition     = tolist(sort(keys(output.resource_ids))) == tolist(["hub_uksouth", "hub_ukwest"]) && can(tostring(output.resource_ids["hub_uksouth"]))
    error_message = "resource_ids must remain map(string) keyed by the var.firewalls keys."
  }

  assert {
    condition     = output.resource_names["hub_uksouth"] == "afw-uksouth" && output.resource_names["hub_ukwest"] == "afw-ukwest"
    error_message = "resource_names must remain map(string) of the Azure resource names, keyed by the var.firewalls keys."
  }

  # --- `resource_id` / `azure_firewall_resource_names`: LISTS, not maps.
  #     v0.17.2 used `[for fw in ... : fw.id]`, which discards the keys. The
  #     singular name on a plural value is baseline behaviour and is pinned
  #     here so nobody "corrects" it into a map. ---
  assert {
    condition     = length(output.resource_id) == 2 && can(tostring(output.resource_id[0]))
    error_message = "resource_id must remain a LIST of id strings (v0.17.2 shape), despite the singular name."
  }

  assert {
    condition     = tolist(sort(output.azure_firewall_resource_names)) == tolist(["afw-uksouth", "afw-ukwest"])
    error_message = "azure_firewall_resource_names must remain a LIST of names (v0.17.2 shape)."
  }

  # --- `private_ip_address`: map(string). v0.17.2 read the azurerm Computed
  #     TypeString `virtual_hub.0.private_ip_address`. ---
  assert {
    condition     = tolist(sort(keys(output.private_ip_address))) == tolist(["hub_uksouth", "hub_ukwest"]) && can(tostring(output.private_ip_address["hub_uksouth"]))
    error_message = "private_ip_address must remain map(string), keyed by the var.firewalls keys."
  }

  # --- `public_ip_addresses`: map(list(string)) -- a list of BARE STRINGS, as
  #     azurerm's Computed TypeList of TypeString was. Not a list of the
  #     `{address = ...}` objects ARM actually returns. ---
  assert {
    condition     = can(tostring(output.public_ip_addresses["hub_uksouth"][0]))
    error_message = "public_ip_addresses must remain map(list(string)) -- bare address strings, not ARM's {address = ...} objects."
  }

  # --- `resource_object`: map(object({id, name, virtual_hub})) where
  #     `virtual_hub` is a ONE-ELEMENT list. v0.17.2 passed azurerm's
  #     `MaxItems: 1` block through raw; modules/virtual-wan/outputs.tf
  #     indexes it positionally at [0]. ---
  assert {
    condition     = length(output.resource_object["hub_uksouth"].virtual_hub) == 1
    error_message = "resource_object.virtual_hub must keep azurerm's one-element block shape; modules/virtual-wan/outputs.tf indexes it at [0]."
  }

  assert {
    condition     = output.resource_object["hub_uksouth"].id == output.resource_ids["hub_uksouth"] && output.resource_object["hub_uksouth"].name == "afw-uksouth"
    error_message = "resource_object entries must still carry `id` and `name` alongside `virtual_hub`."
  }

  # --- `diagnostic_settings_resource_ids`: the ONE v0.17.2 output with no
  #     null guard. It keys off the diagnostic-setting resource, so with no
  #     diagnostic settings it is `{}` -- never null. ---
  assert {
    condition     = length(output.diagnostic_settings_resource_ids) == 0
    error_message = "diagnostic_settings_resource_ids must be an empty MAP when there are no diagnostic settings; v0.17.2 never guarded it and never returned null."
  }
}

# ---------------------------------------------------------------------------
# 4. THE ELEMENT-TYPE DIVERGENCE, asserted rather than glossed over.
#
# `output "resource"` republishes whatever the writer resource is. At v0.17.2
# that was `azurerm_firewall`; it is now `azapi_resource`. These runs pin the
# exact boundary: which members a v0.17.2 consumer can still read, and which
# ones are definitively gone. If a future azapi release grows one of the
# "gone" names back, the second assertion fires and this comment gets revisited
# deliberately instead of by accident.
# ---------------------------------------------------------------------------
run "resource_element_type_divergence_from_azurerm" {
  command = apply

  variables {
    firewalls = {
      hub_uksouth = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-uksouth"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "afw-uksouth"
        tags                = { env = "test" }
      }
    }
  }

  # SURVIVING members -- the intersection of the two schemas. These are the
  # only reads a v0.17.2 consumer can carry over unchanged.
  assert {
    condition = alltrue([
      can(output.resource["hub_uksouth"].id),
      can(output.resource["hub_uksouth"].name),
      can(output.resource["hub_uksouth"].location),
      can(output.resource["hub_uksouth"].tags),
    ])
    error_message = "The azurerm/azapi intersection -- id, name, location, tags -- must survive on output.resource elements. Losing one of these breaks every v0.17.2 consumer, not just the deep ones."
  }

  # 🔴 `tags` is asserted for PRESENCE above but not for VALUE here. It is
  # Optional+Computed in the azapi schema, so under `command = apply` the mock
  # provider substitutes its own generated value and the configured `{env =
  # "test"}` never reaches the output. The configured value IS asserted, under
  # `command = plan` where the mock does not intervene, in
  # `null_optionals.tftest.hcl`.
  assert {
    condition     = output.resource["hub_uksouth"].name == "afw-uksouth" && output.resource["hub_uksouth"].location == "uksouth"
    error_message = "The surviving members must carry real values, not just resolve."
  }

  # GONE members -- present on `azurerm_firewall` at v0.17.2, absent from
  # `azapi_resource`. Their data now lives under `.body`, or in the dedicated
  # outputs (`private_ip_address`, `public_ip_addresses`, `resource_object`).
  assert {
    condition = alltrue([
      !can(output.resource["hub_uksouth"].sku_name),
      !can(output.resource["hub_uksouth"].sku_tier),
      !can(output.resource["hub_uksouth"].firewall_policy_id),
      !can(output.resource["hub_uksouth"].virtual_hub),
      !can(output.resource["hub_uksouth"].ip_configuration),
      !can(output.resource["hub_uksouth"].threat_intel_mode),
      !can(output.resource["hub_uksouth"].dns_servers),
      !can(output.resource["hub_uksouth"].resource_group_name),
    ])
    error_message = "These azurerm_firewall members are expected to be ABSENT on the azapi element type. If one came back, the documented divergence boundary is stale -- update the comment in this file and the description on output \"resource\" together."
  }

  # The azapi-native replacements a migrated consumer must use instead.
  assert {
    condition     = output.resource["hub_uksouth"].body.properties.sku.tier == "Standard" && output.resource["hub_uksouth"].type == "Microsoft.Network/azureFirewalls@2025-07-01"
    error_message = "The azapi element type must expose `.body` and `.type`; these are where the members lost from the azurerm schema now live."
  }
}

# ---------------------------------------------------------------------------
# 3. THE NULL CONTRACT -- the regression guard for the `output "resource"` edit.
#
# v0.17.2's false-branch convention was INCONSISTENT, and that inconsistency is
# the contract:
#   `[]`   azure_firewall_resource_names, resource_id
#   `{}`   resource, resource_object
#   null   private_ip_address, public_ip_addresses, resource_ids, resource_names
#   (diagnostic_settings_resource_ids had no guard at all)
#
# So `length(module.firewalls.resource_ids)` blows up on a null input while
# `length(module.firewalls.resource_id)` does not. Ugly, and load-bearing:
# normalising the four nulls to `{}` would be a silent breaking change.
#
# `var.firewalls` has `default = {}` and NO `nullable = false`, at v0.17.2 and
# now, so an explicit `null` from a caller is reachable and is what this run
# exercises. Dropping the guard from `output "resource"` had to leave this
# column untouched -- it does, because `local.firewalls` maps null to `{}`.
# ---------------------------------------------------------------------------
run "v0_17_2_null_input_contract" {
  command = apply

  variables {
    firewalls = null
  }

  # The four that MUST still be null.
  assert {
    condition = alltrue([
      output.private_ip_address == null,
      output.public_ip_addresses == null,
      output.resource_ids == null,
      output.resource_names == null,
    ])
    error_message = "private_ip_address, public_ip_addresses, resource_ids and resource_names must still collapse to null on a null input. v0.17.2 returned null, not {}; changing them to {} is a silent breaking change for any consumer branching on null."
  }

  # The four that MUST still be an empty collection -- `resource` among them.
  # This is the assertion that would have caught a bad edit to output
  # "resource": it must be an empty MAP, not null and not an error.
  #
  # Split in two on purpose. `alltrue()` does NOT short-circuit -- every
  # element of the list is evaluated before the function is called -- so a
  # `length()` sitting next to a `!= null` in the same list turns a clean
  # FAILURE into an evaluation ERROR when the output really is null. The
  # null checks therefore go first, in their own assert.
  assert {
    condition = alltrue([
      output.resource != null,
      output.resource_object != null,
      output.azure_firewall_resource_names != null,
      output.resource_id != null,
    ])
    error_message = "resource, resource_object, azure_firewall_resource_names and resource_id must NEVER be null -- v0.17.2 gave them empty-collection false branches ([] or {}), not null. `value = azapi_resource.fw` relies on local.firewalls mapping a null var to {}; if that local ever stops guarding, this fires."
  }

  assert {
    condition = alltrue([
      length(output.resource) == 0,
      length(output.resource_object) == 0,
      length(output.azure_firewall_resource_names) == 0,
      length(output.resource_id) == 0,
    ])
    error_message = "resource, resource_object, azure_firewall_resource_names and resource_id must collapse to EMPTY collections on a null input."
  }

  # The unguarded one.
  assert {
    condition     = output.diagnostic_settings_resource_ids != null && length(output.diagnostic_settings_resource_ids) == 0
    error_message = "diagnostic_settings_resource_ids was never guarded at v0.17.2 and must stay an empty map on a null input."
  }

  assert {
    condition     = length(azapi_resource.fw) == 0 && length(azapi_update_resource.fw) == 0 && length(data.azapi_resource.fw_hub_ip_addresses) == 0
    error_message = "A null var.firewalls must create nothing at all; local.firewalls is what makes the dropped conditional in output \"resource\" safe."
  }
}

# ---------------------------------------------------------------------------
# The same contract via the EMPTY MAP rather than null. `default = {}` means
# this, not the null path, is what an omitting caller actually gets -- and it
# takes the TRUE branch of every remaining guard, so the four null outputs are
# `{}` here and `null` in the run above. Both are v0.17.2 behaviour, and the
# difference between them is a trap worth pinning.
# ---------------------------------------------------------------------------
run "v0_17_2_empty_map_input_contract" {
  command = apply

  variables {
    firewalls = {}
  }

  # Null checks first and separately -- `alltrue()` does not short-circuit, so
  # a `length()` alongside a `!= null` would error instead of failing.
  assert {
    condition = alltrue([
      output.private_ip_address != null,
      output.public_ip_addresses != null,
      output.resource_ids != null,
      output.resource_names != null,
    ])
    error_message = "An EMPTY MAP takes the true branch, so these outputs must be {} -- not the null an explicit null input yields. The asymmetry is v0.17.2 behaviour and consumers of the default path depend on the {} side of it."
  }

  assert {
    condition = alltrue([
      length(output.private_ip_address) == 0,
      length(output.public_ip_addresses) == 0,
      length(output.resource_ids) == 0,
      length(output.resource_names) == 0,
    ])
    error_message = "On an empty firewalls map these outputs must be empty maps."
  }

  assert {
    condition     = output.resource != null && length(output.resource) == 0
    error_message = "An empty firewalls map must yield an empty resource map."
  }
}
