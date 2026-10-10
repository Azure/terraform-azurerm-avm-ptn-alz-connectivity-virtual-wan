# ForceNew guard tests for the azurerm -> azapi migration of `modules/virtual-hub`.
#
# `azurerm_virtual_hub` had six ForceNew inputs at v4.81.0
# (`5782a75422c68a0d0804ac16d97dcaf3df5ee2fa`, `internal/services/network/virtual_hub_resource.go`).
# Three map onto attributes that are already ForceNew on `azapi_resource` (`name` L58,
# `resource_group_name` L62, `location` L64) and need no guard. The other three live inside `body`,
# which the full writer ignores, so a change to them would be a SILENT no-op:
#
#   `address_prefix` L69 -> body.properties.addressPrefix
#   `sku`            L82 -> body.properties.sku
#   `virtual_wan_id` L92 -> body.properties.virtualWan.id
#
# The FORCENEW GUARD preconditions on the merge writer turn that silence into a plan failure. These
# runs prove each one both FIRES on a change and STAYS QUIET when nothing moved.
#
# 🔴 HOW THESE TESTS WORK, and why `run "genesis"` is an apply. The preconditions read
# `azapi_resource.this[...].body`, which `ignore_changes = [body]` pins to the PRIOR STATE body.
# There is no prior state inside a single plan-only run, so the first run must APPLY (against the
# mock provider - no Azure call, no credentials, no cost) to lay down a state body. `terraform test`
# carries state across runs in a file, so every later `command = plan` run diffs against it. A run
# that only planned would compare the config against itself and pass unconditionally.

# 🔴 `mock_resource` IS REQUIRED HERE, unlike in `null_optionals.tftest.hcl`. Those runs are
# plan-only, so `azapi_resource.this.id` stays unknown and is never validated. This file applies,
# and the mock provider's generated value for a computed string is a random 8-character token —
# which `azapi_update_resource.resource_id` rejects with "resource id '...' must start with '/'".
# The override below supplies a well-formed ARM ID instead. It is a fixture, not an assertion.
mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-forcenew"
    }
  }

  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  resource_types = {
    network_virtual_hubs = "Microsoft.Network/virtualHubs@2025-07-01"
  }

  virtual_hubs = {
    hub_a = {
      name                                   = "vhub-forcenew"
      location                               = "uksouth"
      resource_group_name                    = "rg-test"
      address_prefix                         = "10.0.0.0/23"
      virtual_wan_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
      sku                                    = "Standard"
      hub_routing_preference                 = "ExpressRoute"
      virtual_router_auto_scale_min_capacity = 2
    }
  }
}

# Lays down the state body every later run diffs against. At create the preconditions compare the
# about-to-be-written body with itself, so they must not fire here.
run "genesis" {
  command = apply

  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.addressPrefix == "10.0.0.0/23"
    error_message = "the state body must carry the configured address prefix for the later guard runs to be meaningful."
  }

  assert {
    condition     = azapi_resource.this["hub_a"].body.properties.sku == "Standard"
    error_message = "the state body must carry the configured sku for the later guard runs to be meaningful."
  }
}

# ── the guard FIRES ─────────────────────────────────────────────────────────────────────────────

# `address_prefix` L69.
run "address_prefix_change_fails" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                                   = "vhub-forcenew"
        location                               = "uksouth"
        resource_group_name                    = "rg-test"
        address_prefix                         = "10.9.0.0/23"
        virtual_wan_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        sku                                    = "Standard"
        hub_routing_preference                 = "ExpressRoute"
        virtual_router_auto_scale_min_capacity = 2
      }
    }
  }

  expect_failures = [azapi_update_resource.this]
}

# `sku` L82. AzureRM's `StringInSlice([...], false)` (L83-86) is case-SENSITIVE, so this is a
# value change in exactly the sense AzureRM meant.
run "sku_change_fails" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                                   = "vhub-forcenew"
        location                               = "uksouth"
        resource_group_name                    = "rg-test"
        address_prefix                         = "10.0.0.0/23"
        virtual_wan_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        sku                                    = "Basic"
        hub_routing_preference                 = "ExpressRoute"
        virtual_router_auto_scale_min_capacity = 2
      }
    }
  }

  expect_failures = [azapi_update_resource.this]
}

# 🔴 The null-handling case the `try(..., null)` wrapper must NOT swallow: the state body has a
# `sku`, the new config does not. `d.GetOk` omits the key entirely, so the left side is "Standard"
# and the right side is null. If this run ever passes, the guard has been made vacuous.
run "sku_removal_fails" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                                   = "vhub-forcenew"
        location                               = "uksouth"
        resource_group_name                    = "rg-test"
        address_prefix                         = "10.0.0.0/23"
        virtual_wan_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        sku                                    = null
        hub_routing_preference                 = "ExpressRoute"
        virtual_router_auto_scale_min_capacity = 2
      }
    }
  }

  expect_failures = [azapi_update_resource.this]
}

# `virtual_wan_id` L92.
run "virtual_wan_id_change_fails" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                                   = "vhub-forcenew"
        location                               = "uksouth"
        resource_group_name                    = "rg-test"
        address_prefix                         = "10.0.0.0/23"
        virtual_wan_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-OTHER"
        sku                                    = "Standard"
        hub_routing_preference                 = "ExpressRoute"
        virtual_router_auto_scale_min_capacity = 2
      }
    }
  }

  expect_failures = [azapi_update_resource.this]
}

# ── the guard STAYS QUIET ───────────────────────────────────────────────────────────────────────

# Every ForceNew input unchanged; only the day-2-mutable ones move. AzureRM's update path could
# change exactly these (`hub_routing_preference` L285, `tags` L289,
# `virtual_router_auto_scale_min_capacity` L292), so the plan must succeed.
run "mutable_changes_pass" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                                   = "vhub-forcenew"
        location                               = "uksouth"
        resource_group_name                    = "rg-test"
        address_prefix                         = "10.0.0.0/23"
        virtual_wan_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        sku                                    = "Standard"
        hub_routing_preference                 = "ASPath"
        tags                                   = { env = "test" }
        virtual_router_auto_scale_min_capacity = 4
      }
    }
  }

  assert {
    condition     = azapi_update_resource.this["hub_a"].body.properties.hubRoutingPreference == "ASPath"
    error_message = "a day-2-mutable change must reach the merge body without tripping the ForceNew guard."
  }
}

# `virtualWan.id` is an ARM resource ID and genuinely case-insensitive, so `lower()` is applied to
# both sides and a case-only difference must NOT fire the guard. This is the one property where
# that is true; `sku` and `address_prefix` are compared exactly.
run "virtual_wan_id_case_only_passes" {
  command = plan

  variables {
    virtual_hubs = {
      hub_a = {
        name                                   = "vhub-forcenew"
        location                               = "uksouth"
        resource_group_name                    = "rg-test"
        address_prefix                         = "10.0.0.0/23"
        virtual_wan_id                         = "/SUBSCRIPTIONS/00000000-0000-0000-0000-000000000000/RESOURCEGROUPS/rg-test/PROVIDERS/Microsoft.Network/VIRTUALWANS/vwan-test"
        sku                                    = "Standard"
        hub_routing_preference                 = "ExpressRoute"
        virtual_router_auto_scale_min_capacity = 2
      }
    }
  }

  assert {
    condition     = azapi_update_resource.this["hub_a"].resource_id == azapi_resource.this["hub_a"].id
    error_message = "a case-only Virtual WAN ID difference must not trip the ForceNew guard: ARM resource IDs are case-insensitive and both sides are lowered."
  }
}
