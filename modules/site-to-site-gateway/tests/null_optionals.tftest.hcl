# See `modules/site-to-site-vpn-site/tests/null_optionals.tftest.hcl` for why this exists:
# An earlier test apply failed at apply, not at plan, because the inputs were unknown at plan
# time and the locals were never evaluated. Known inputs force evaluation.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

mock_provider "azapi" {}

variables {
  resource_types = {
    network_vpn_gateways = "Microsoft.Network/vpnGateways@2025-07-01"
  }
}

# Every optional on the gateway left unset. This is the run that pins the schema defaults
# AzureRM applied BEFORE its Create func ran and then sent unconditionally as a struct
# literal (`vpn_gateway_resource.go` L249-L261) -- the values a consumer never typed and
# would never notice going missing until the first post-upgrade apply reset them.
run "all_optionals_null" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-null"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
      }
    }
  }

  # Schema L78-L82 Default false, sent at L252 whatever the consumer passed.
  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.enableBgpRouteTranslationForNat == false
    error_message = "enableBgpRouteTranslationForNat must be the AzureRM schema default false when unset."
  }

  # Schema L191-L196 Default 1, sent at L257. A gateway created with 0 scale units is a
  # gateway that cannot pass traffic, so this default is load-bearing.
  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.vpnGatewayScaleUnit == 1
    error_message = "vpnGatewayScaleUnit must be the AzureRM schema default 1 when unset."
  }

  # Schema L67-L76 Default "Microsoft Network", turned into a BOOLEAN at L258 by comparing
  # against "Internet". So the literal AzureRM sent when the consumer said nothing is
  # `false` -- not an absent key, and not `true`.
  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.isRoutingPreferenceInternet == false
    error_message = "isRoutingPreferenceInternet must be false when routing_preference is unset, matching the AzureRM default \"Microsoft Network\"."
  }

  # `expandVPNGatewayBGPSettings` returns NIL for an empty list (L451-L453), so the key is
  # absent rather than `{}`. `ignore_null_property` prunes the null this module emits.
  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.bgpSettings == null
    error_message = "bgpSettings must be null (and so pruned) when bgp_settings is unset, matching expandVPNGatewayBGPSettings returning nil."
  }

  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.virtualHub.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
    error_message = "virtualHub.id must carry the configured virtual_hub_id."
  }

  # `parent_id` is reconstructed from the subscription in `virtual_hub_id` plus the
  # configured resource group, because AzAPI needs an ID where AzureRM needed a name.
  assert {
    condition     = azapi_resource.this["gw_a"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    error_message = "parent_id must be reconstructed from the subscription in virtual_hub_id and the configured resource group."
  }

  # 🔴 With neither peering-address block set, AzureRM made NO second create PUT
  # (L285: `if len(input0) > 0 || len(input1) > 0`) and its Update skipped both branches
  # (L343, L349). The merge writer must therefore not mention `bgpSettings` at all --
  # if it did, it would push a two-element array at the live gateway's peering addresses
  # and, via the positional merge branch, could blank the `customBgpIpAddresses` ARM
  # assigned.
  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.properties.bgpSettings)
    error_message = "The merge writer must omit bgpSettings entirely when no instance peering address is configured."
  }

  # 🔴 REG-1. `tags` is absent from the merge body ALWAYS as of 0.19.0, set or unset, so the
  # merge cannot touch live tags at all. It used to be spliced in when non-null, and that is
  # what made REG-1: the merge preserves every undeclared key of the live object
  # (`utils/json.go` L52-L53), so it could add or change a tag but never REMOVE one.
  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.tags)
    error_message = "The merge writer must never carry a tags key: a merge writer can never remove a tag (REG-1). Tags belong on azapi_resource_action.tags."
  }

  # The `{}` is AzureRM parity -- `tags.Expand(nil)` returns a pointer to an EMPTY map and never
  # nil -- and it matters more here than it did on the merge writer: this PUT REPLACES the whole
  # tag set, so an omitted key would mean "send no tags at all".
  assert {
    condition     = azapi_resource_action.tags["gw_a"].body.properties.tags != null && length(azapi_resource_action.tags["gw_a"].body.properties.tags) == 0
    error_message = "With tags unset the tag writer must PUT an empty map, never a null and never an omitted key."
  }

  # AzureRM's flatten returned `[]` for nil bgp settings (L463-L465).
  assert {
    condition     = length(output.resource_object["gw_a"].bgp_settings) == 0
    error_message = "bgp_settings must be an empty list when unset, matching flattenVPNGatewayBGPSettings on nil."
  }
}

# 🔴 THE RUN THAT MATTERS. Every optional set, including both peering-address blocks --
# the shape that exercises the two-element `bgpPeeringAddresses` array, the boolean
# conversion of `routing_preference`, and the list comparisons that need `tolist()` on
# BOTH sides (a bare `["a","b"]` literal is a TUPLE, and `tuple == list(string)` is false
# with only a warning, which is how a real type-unification bug got through once before).
run "all_optionals_set" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                                  = "vpngw-full"
        location                              = "uksouth"
        resource_group_name                   = "rg-test"
        virtual_hub_id                        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        tags                                  = { env = "test" }
        bgp_route_translation_for_nat_enabled = true
        routing_preference                    = "Internet"
        scale_unit                            = 4
        bgp_settings = {
          asn         = 65515
          peer_weight = 5
          instance_0_bgp_peering_address = {
            custom_ips = ["169.254.21.1"]
          }
          instance_1_bgp_peering_address = {
            custom_ips = ["169.254.22.1", "169.254.22.5"]
          }
        }
      }
    }
  }

  # 🔴 `expandVPNGatewayBGPSettings` (L456-L459) returns ONLY `{Asn, PeerWeight}`. It never
  # populates `BgpPeeringAddresses`, because ARM rejects them on create -- AzureRM says so
  # in its own comment at L268-L269. If the create body ever starts carrying them, create
  # fails against real ARM and the mock provider will not tell you.
  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.bgpSettings.asn == 65515
    error_message = "bgpSettings.asn must carry the configured ASN."
  }

  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.bgpSettings.peerWeight == 5
    error_message = "bgpSettings.peerWeight must carry the configured peer weight."
  }

  assert {
    condition     = !can(azapi_resource.this["gw_a"].body.properties.bgpSettings.bgpPeeringAddresses)
    error_message = "The create body must NOT carry bgpPeeringAddresses -- ARM rejects them on create (vpn_gateway_resource.go L268-L269)."
  }

  # The string-to-boolean conversion at L258.
  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.isRoutingPreferenceInternet == true
    error_message = "isRoutingPreferenceInternet must be true when routing_preference is \"Internet\"."
  }

  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.vpnGatewayScaleUnit == 4
    error_message = "vpnGatewayScaleUnit must carry the configured scale unit."
  }

  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.enableBgpRouteTranslationForNat == true
    error_message = "enableBgpRouteTranslationForNat must carry the configured value."
  }

  # 🔴 EXACTLY TWO ELEMENTS, ALWAYS. `mergeObjectAtPath` (azapi `utils/json.go` L61-L104)
  # finds no identifier key on these items, so it falls to the positional branch, which
  # merges element-by-element ONLY when the lengths match and otherwise REPLACES the live
  # array wholesale. ARM returns exactly two ("Instance0", "Instance1") -- measured in
  # a captured live 2025-07-01 response.
  assert {
    condition     = length(azapi_update_resource.this["gw_a"].body.properties.bgpSettings.bgpPeeringAddresses) == 2
    error_message = "bgpPeeringAddresses must always be exactly two elements so the merge takes the positional branch rather than replacing the live array."
  }

  # 🔴 `tolist()` ON BOTH SIDES. `custom_ips` is `list(string)`; the literal on the right is
  # a TUPLE. `tuple == list(string)` evaluates to FALSE and Terraform reports it as a
  # warning, not an error -- an assertion written without this passes for the wrong reason.
  assert {
    condition     = tolist(azapi_update_resource.this["gw_a"].body.properties.bgpSettings.bgpPeeringAddresses[0].customBgpIpAddresses) == tolist(["169.254.21.1"])
    error_message = "Instance 0 customBgpIpAddresses must carry the configured custom_ips."
  }

  assert {
    condition     = tolist(azapi_update_resource.this["gw_a"].body.properties.bgpSettings.bgpPeeringAddresses[1].customBgpIpAddresses) == tolist(["169.254.22.1", "169.254.22.5"])
    error_message = "Instance 1 customBgpIpAddresses must carry the configured custom_ips."
  }

  # The merge writer carries the day-2 subset only. `virtualHub`, `isRoutingPreferenceInternet`
  # and the `asn`/`peerWeight` pair were all ForceNew under AzureRM (L63, L71, L94, L100), so
  # they could never appear in an AzureRM update body. Declaring them here would silently
  # convert a replacement into an in-place change.
  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.properties.virtualHub)
    error_message = "The merge writer must not declare virtualHub -- it was ForceNew under AzureRM."
  }

  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.properties.isRoutingPreferenceInternet)
    error_message = "The merge writer must not declare isRoutingPreferenceInternet -- routing_preference was ForceNew under AzureRM."
  }

  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.properties.bgpSettings.asn)
    error_message = "The merge writer must not declare bgpSettings.asn -- it was ForceNew under AzureRM."
  }

  # 🔴 REG-1's remedy, and the inversion of what this assertion used to say. AzureRM's Update
  # assigned the WHOLE tag map (L332-L333), which a merge writer cannot reproduce, so the
  # configured tags moved to the tag writer and the merge writer must carry none.
  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.tags)
    error_message = "The merge writer must never carry a tags key: a merge writer can never remove a tag (REG-1)."
  }

  assert {
    condition     = azapi_resource_action.tags["gw_a"].body.properties.tags.env == "test"
    error_message = "The tag writer must carry the configured tags, matching AzureRM's Update at L332-L333."
  }

  # Constructed, never read back. See the note in `outputs.tf`.
  assert {
    condition     = tolist(output.ip_configuration_ids["gw_a"]) == tolist(["Instance0", "Instance1"])
    error_message = "ip_configuration_ids must be the literal ARM-assigned Instance0/Instance1 values, known at plan time."
  }

  assert {
    condition     = output.resource_object["gw_a"].bgp_settings[0].instance_1_bgp_peering_address[0].ip_configuration_id == "Instance1"
    error_message = "The flattened bgp_settings must carry the per-instance ip_configuration_id in AzureRM's shape."
  }

  # 🔴 THE SILENCE CONTRACT. `lifecycle` blocks cannot reference a local, so the list is
  # written out twice -- once in `local.full_writer_ignored_attributes` with the per-entry
  # audit, once in the `lifecycle` block that actually does the work. This assertion is the
  # only thing keeping the two in step, and 16 is the count enumerated against azapi
  # v2.12.0 `AzapiResourceModel` L58-L91. A provider bump that adds a non-skippable
  # configurable field makes this number wrong, and that is the point.
  assert {
    condition     = length(local.full_writer_ignored_attributes) == 17
    error_message = "The full writer's ignore_changes list must hold all 16 non-skippable configurable azapi_resource attributes."
  }

  # `response_export_values` is the entry that bit the candidate-1 gateway fixture in test
  # (ii) -- its absence from the ignore list is what dragged the full writer into an update.
  assert {
    condition     = contains(local.full_writer_ignored_attributes, "response_export_values")
    error_message = "response_export_values must be in the full writer's ignore_changes list -- it is the attribute that drove the measured spurious update."
  }

  # `timeouts` carries `skip_on:\"update\"` (azapi_resource.go L81), so a diff on it never
  # reaches ARM. Silencing it would cost real behaviour for no safety gain.
  assert {
    condition     = !contains(local.full_writer_ignored_attributes, "timeouts")
    error_message = "timeouts must NOT be silenced -- it is skip_on:update, so a diff on it makes no ARM call."
  }

  # AzureRM's own per-resource timeouts, L41-L46. Not the repo-wide 30m.
  assert {
    condition     = var.timeouts.create == "90m" && var.timeouts.update == "90m" && var.timeouts.delete == "90m" && var.timeouts.read == "5m"
    error_message = "The timeout defaults must be AzureRM's own for azurerm_vpn_gateway: 90m create, 5m read, 90m update, 90m delete."
  }
}

# Only one peering-address block set. AzureRM touched `[0]` and left `[1]` alone
# (L344-L347 vs L350-L353), so the second element has to be an EMPTY OBJECT -- the map
# branch of the merge (`utils/json.go` L45-L58) keeps every key the new item does not
# mention, which is exactly "leave instance 1 as ARM has it". A null would blank it,
# because `mergeObjectAtPath` returns `new` outright when `new` is nil (L40-L42) and
# `azapi_update_resource` has no `ignore_null_property` to prune it.
run "single_instance_peering_address" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-one-instance"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        bgp_settings = {
          asn         = 65515
          peer_weight = 0
          instance_0_bgp_peering_address = {
            custom_ips = ["169.254.21.1"]
          }
        }
      }
    }
  }

  assert {
    condition     = length(azapi_update_resource.this["gw_a"].body.properties.bgpSettings.bgpPeeringAddresses) == 2
    error_message = "bgpPeeringAddresses must still be two elements when only one instance is configured, or the merge replaces the live array."
  }

  assert {
    condition     = tolist(azapi_update_resource.this["gw_a"].body.properties.bgpSettings.bgpPeeringAddresses[0].customBgpIpAddresses) == tolist(["169.254.21.1"])
    error_message = "The configured instance must carry its custom_ips."
  }

  # 🔴 EMPTY OBJECT, NOT NULL, NOT AN OBJECT WITH A NULL KEY.
  assert {
    condition     = length(keys(azapi_update_resource.this["gw_a"].body.properties.bgpSettings.bgpPeeringAddresses[1])) == 0
    error_message = "The unconfigured instance must be an empty object so the merge leaves the live peering address untouched."
  }

  # The unconfigured instance flattens to an empty list, matching AzureRM's
  # `instance_1_bgp_peering_address` being absent from the configuration.
  assert {
    condition     = length(output.resource_object["gw_a"].bgp_settings[0].instance_1_bgp_peering_address) == 0
    error_message = "The unconfigured instance must flatten to an empty list."
  }
}

# 🔴 TWO GATEWAYS OF DIFFERENT SHAPES IN ONE MAP. Every local and output here is a
# `for` expression, and the per-key values have DIFFERENT types once one gateway has
# `bgp_settings` and the other does not -- `bgpSettings` present vs null in the body,
# a one-element vs empty `bgp_settings` list in the outputs. HCL has to unify those,
# and a bad unification either errors or silently coerces a value. A single-entry map
# cannot catch it because there is nothing to unify against.
run "mixed_map" {
  command = plan

  variables {
    vpn_gateways = {
      gw_bare = {
        name                = "vpngw-bare"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a"
      }
      gw_bgp = {
        name                = "vpngw-bgp"
        location            = "ukwest"
        resource_group_name = "rg-other"
        virtual_hub_id      = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-other/providers/Microsoft.Network/virtualHubs/vhub-b"
        tags                = { env = "test" }
        scale_unit          = 2
        bgp_settings = {
          asn         = 65515
          peer_weight = 0
          instance_1_bgp_peering_address = {
            custom_ips = ["169.254.22.1"]
          }
        }
      }
    }
  }

  # Each gateway's parent_id is reconstructed from ITS OWN virtual_hub_id, so a map
  # spanning two subscriptions does not collapse onto one.
  assert {
    condition     = azapi_resource.this["gw_bgp"].parent_id == "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-other"
    error_message = "parent_id must be derived per gateway, not shared across the map."
  }

  assert {
    condition     = azapi_resource.this["gw_bare"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    error_message = "parent_id must be derived per gateway, not shared across the map."
  }

  # The null and non-null `bgpSettings` bodies must survive unification unchanged.
  assert {
    condition     = azapi_resource.this["gw_bare"].body.properties.bgpSettings == null
    error_message = "A gateway without bgp_settings must still emit a null bgpSettings when another gateway in the map has one."
  }

  assert {
    condition     = azapi_resource.this["gw_bgp"].body.properties.bgpSettings.asn == 65515
    error_message = "A gateway with bgp_settings must keep its asn when another gateway in the map has none."
  }

  # Instance 0 unconfigured, instance 1 configured -- the mirror of the single-instance
  # run, which catches an index swap that a symmetric fixture would not.
  assert {
    condition     = length(keys(azapi_update_resource.this["gw_bgp"].body.properties.bgpSettings.bgpPeeringAddresses[0])) == 0
    error_message = "Instance 0 must stay an empty object when only instance 1 is configured."
  }

  assert {
    condition     = tolist(azapi_update_resource.this["gw_bgp"].body.properties.bgpSettings.bgpPeeringAddresses[1].customBgpIpAddresses) == tolist(["169.254.22.1"])
    error_message = "Instance 1 must carry its custom_ips when instance 0 is unconfigured."
  }

  assert {
    condition     = !can(azapi_update_resource.this["gw_bare"].body.properties.bgpSettings)
    error_message = "The bare gateway's merge writer must still omit bgpSettings entirely."
  }

  # Differing `bgp_settings` list lengths across the map, unified into one output value.
  assert {
    condition     = length(output.resource_object["gw_bare"].bgp_settings) == 0 && length(output.resource_object["gw_bgp"].bgp_settings) == 1
    error_message = "resource_object must carry a per-gateway bgp_settings list of the right length across a mixed map."
  }

  assert {
    condition     = length(output.ip_configuration_ids) == 2
    error_message = "ip_configuration_ids must have an entry for every gateway."
  }
}

run "empty_map" {
  command = plan

  variables {
    vpn_gateways = {}
  }

  assert {
    condition     = length(azapi_resource.this) == 0
    error_message = "An empty vpn_gateways map must create no resources."
  }

  assert {
    condition     = length(azapi_update_resource.this) == 0
    error_message = "An empty vpn_gateways map must create no merge writers."
  }

  assert {
    condition     = length(output.ip_configuration_ids) == 0
    error_message = "An empty vpn_gateways map must produce no ip_configuration_ids."
  }
}
