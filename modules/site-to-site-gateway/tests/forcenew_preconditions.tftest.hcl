# The four properties AzureRM marked `ForceNew: true` inside
# `body` -- `virtual_hub_id` (vpn_gateway_resource.go L63), `routing_preference` (L71),
# `bgp_settings.asn` (L94) and `bgp_settings.peer_weight` (L100) -- are guarded by
# `lifecycle.precondition` blocks on the MERGE writer, not by
# `replace_triggers_external_values`. See the long note on `azapi_update_resource.this`.
#
# THE SHAPE OF THIS FILE IS LOAD-BEARING. A precondition that reads
# `azapi_resource.this[k].body` can only be exercised once there IS a prior state to read:
# on the first plan, state and config are the same value and every check passes by
# construction. So run 1 APPLIES against the mock provider to create that state, and every
# later run PLANS a mutated config against it. A failed plan does not write state, so all
# of the failing runs chain off the single applied state without interfering.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

# 🔴 THE `id` DEFAULTS ARE REQUIRED, NOT DECORATION. These runs APPLY, and the merge
# writer takes `resource_id = azapi_resource.this[...].id`. Left to itself the mock
# provider invents an opaque string for a computed `id`, and `azapi_update_resource`'s own
# validator rejects it ("invalid resource ID: ... must start with '/'"), failing the apply
# before any precondition is ever reached. Only this file needs them, because only this
# file applies.
mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/vpngw-forcenew"
    }
  }

  mock_resource "azapi_update_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/vpngw-forcenew"
    }
  }
}

variables {
  resource_types = {
    network_vpn_gateways = "Microsoft.Network/vpnGateways@2025-07-01"
  }
}

# The state every later run plans against. `routing_preference` is left UNSET so the run
# below that flips it to "Internet" is a change away from the AzureRM schema default
# ("Microsoft Network", L70-L75) rather than between two explicit values.
#
# `gw_bare` exists ONLY so there is a gateway whose STATE body has `bgpSettings` as a
# whole-object null -- the asymmetric case the asn / peer_weight guards are built around.
# It is re-declared in `bgp_settings_added_fails` and nowhere else; the intervening runs
# simply plan its destruction, which evaluates no preconditions and writes no state.
run "adopt" {
  command = apply

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-forcenew"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
        scale_unit          = 2
        bgp_settings = {
          asn         = 65515
          peer_weight = 0
          instance_0_bgp_peering_address = {
            custom_ips = ["169.254.21.1"]
          }
        }
      }
      gw_bare = {
        name                = "vpngw-bare"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
      }
    }
  }

  # The precondition is only trustworthy if this is the CREATE-TIME value. Assert the two
  # state-body paths the checks below read, so a future change to `vpn_gateway_bodies` that
  # renames or drops one of them fails here rather than silently making a check vacuous.
  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.virtualHub.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
    error_message = "The applied state body must carry the create-time virtual hub ID."
  }

  assert {
    condition     = azapi_resource.this["gw_a"].body.properties.bgpSettings.asn == 65515
    error_message = "The applied state body must carry the create-time ASN."
  }

  # The premise of the addition test below.
  assert {
    condition     = azapi_resource.this["gw_bare"].body.properties.bgpSettings == null
    error_message = "gw_bare's state body must have a null bgpSettings, or the addition test proves nothing."
  }
}

# 🔴 THE GUARDS ARE ASYMMETRIC ON PURPOSE, AND THIS IS THE RUN THAT PROVES IT.
# `gw_bare` was created with no `bgp_settings`, so its STATE body has `bgpSettings = null`.
# Adding an `asn` / `peer_weight` now is the introduction of a ForceNew property, and the
# naive symmetric guard (`state == null || state == config`) would wave it straight
# through. `gw_a` is repeated unchanged so the only thing that can fail is `gw_bare`.
run "bgp_settings_added_fails" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-forcenew"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
        scale_unit          = 2
        bgp_settings = {
          asn         = 65515
          peer_weight = 0
          instance_0_bgp_peering_address = {
            custom_ips = ["169.254.21.1"]
          }
        }
      }
      gw_bare = {
        name                = "vpngw-bare"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
        bgp_settings = {
          asn         = 65515
          peer_weight = 0
        }
      }
    }
  }

  expect_failures = [azapi_update_resource.this["gw_bare"]]
}

# ---------------------------------------------------------------- the four refusals

# The hub name changes; the subscription and resource group do NOT, so `parent_id` is
# unchanged and the only thing the plan can trip over is the precondition itself.
run "virtual_hub_id_change_fails" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-forcenew"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-MOVED"
        scale_unit          = 2
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

  expect_failures = [azapi_update_resource.this["gw_a"]]
}

# Case-only difference on the hub ID: the provider namespace is lower-cased and the hub
# NAME is upper-cased. ARM IDs are case-insensitive and both sides of the precondition are
# `lower()`ed, so this must NOT fail -- a precondition that fired on casing would block
# every consumer whose config spells the ID differently from ARM's readback.
#
# ⚠️ The other segments are left alone deliberately: `variables.tf`'s own regex on
# `virtual_hub_id` only tolerates case variation on `[Mm]icrosoft\.[Nn]etwork`, so
# `resourcegroups` or `virtualhubs` would be rejected by the variable validation before the
# precondition was ever evaluated, and the run would pass for the wrong reason.
run "virtual_hub_id_case_only_passes" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-forcenew"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/microsoft.network/virtualHubs/VHUB-ORIGINAL"
        scale_unit          = 2
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
    condition     = azapi_update_resource.this["gw_a"].body.properties.vpnGatewayScaleUnit == 2
    error_message = "A case-only difference in virtual_hub_id must not trip the precondition."
  }
}

# Unset -> "Internet". The state body holds `isRoutingPreferenceInternet = false`.
run "routing_preference_change_fails" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-forcenew"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
        routing_preference  = "Internet"
        scale_unit          = 2
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

  expect_failures = [azapi_update_resource.this["gw_a"]]
}

# Unset -> the explicit AzureRM default. Not a change to `isRoutingPreferenceInternet`, so
# it must NOT fail: the precondition compares the derived BOOLEAN, not the raw string.
run "routing_preference_explicit_default_passes" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-forcenew"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
        routing_preference  = "Microsoft Network"
        scale_unit          = 2
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
    condition     = azapi_update_resource.this["gw_a"].body.properties.vpnGatewayScaleUnit == 2
    error_message = "Spelling out the AzureRM default routing_preference must not trip the precondition."
  }
}

run "bgp_asn_change_fails" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-forcenew"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
        scale_unit          = 2
        bgp_settings = {
          asn         = 65001
          peer_weight = 0
          instance_0_bgp_peering_address = {
            custom_ips = ["169.254.21.1"]
          }
        }
      }
    }
  }

  expect_failures = [azapi_update_resource.this["gw_a"]]
}

run "bgp_peer_weight_change_fails" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-forcenew"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
        scale_unit          = 2
        bgp_settings = {
          asn         = 65515
          peer_weight = 7
          instance_0_bgp_peering_address = {
            custom_ips = ["169.254.21.1"]
          }
        }
      }
    }
  }

  expect_failures = [azapi_update_resource.this["gw_a"]]
}

# ---------------------------------------------------------------- the deliberate silences

# 🔴 THE OTHER HALF OF THE ASYMMETRY. Dropping `bgp_settings` entirely makes the CONFIG
# side of the asn / peer_weight checks null, and they are skipped. That is correct parity:
# AzureRM's `bgp_settings` is `Optional: true, Computed: true` (L84-L88, `Optional` L86 / `Computed` L87), so removing the
# block produced no diff and no replacement there either. Paired with
# `bgp_settings_added_fails` above, these two runs pin the guard to exactly one direction:
# if this run starts FAILING the guard has been tightened past AzureRM; if that one starts
# PASSING it has been loosened into the vacuous symmetric form.
run "bgp_settings_removed_passes" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                = "vpngw-forcenew"
        location            = "uksouth"
        resource_group_name = "rg-test"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
        scale_unit          = 2
      }
    }
  }

  assert {
    condition     = !can(azapi_update_resource.this["gw_a"].body.properties.bgpSettings)
    error_message = "Removing bgp_settings must leave the merge body without bgpSettings and must not trip a precondition."
  }
}

# Everything a day-2 edit is ALLOWED to touch, changed at once: `scale_unit`,
# `bgp_route_translation_for_nat_enabled`, `tags` and the custom BGP IPs. None of these is
# ForceNew, so the plan must succeed -- this is the run that would catch a precondition
# written against a property that AzureRM's Update could change in place.
run "day2_subset_changes_pass" {
  command = plan

  variables {
    vpn_gateways = {
      gw_a = {
        name                                  = "vpngw-forcenew"
        location                              = "uksouth"
        resource_group_name                   = "rg-test"
        virtual_hub_id                        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-original"
        scale_unit                            = 10
        bgp_route_translation_for_nat_enabled = true
        tags                                  = { env = "prod" }
        bgp_settings = {
          asn         = 65515
          peer_weight = 0
          instance_0_bgp_peering_address = {
            custom_ips = ["169.254.21.9"]
          }
          instance_1_bgp_peering_address = {
            custom_ips = ["169.254.22.9"]
          }
        }
      }
    }
  }

  assert {
    condition     = azapi_update_resource.this["gw_a"].body.properties.vpnGatewayScaleUnit == 10
    error_message = "A scale_unit change must reach the merge writer without tripping a precondition."
  }

  assert {
    condition     = azapi_update_resource.this["gw_a"].body.properties.enableBgpRouteTranslationForNat == true
    error_message = "A bgp_route_translation_for_nat_enabled change must reach the merge writer without tripping a precondition."
  }

  assert {
    condition     = tolist(azapi_update_resource.this["gw_a"].body.properties.bgpSettings.bgpPeeringAddresses[1].customBgpIpAddresses) == tolist(["169.254.22.9"])
    error_message = "Adding a second custom BGP IP instance must not trip a precondition."
  }
}
