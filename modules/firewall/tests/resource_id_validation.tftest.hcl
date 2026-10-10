# TFNFR38 -- Resource ID Variable Validation (Severity-MUST; Class-Resource, Class-Pattern,
# Class-Utility). `firewalls[*].virtual_hub_id` is validated with
# `provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", ...)` rather than a
# hand-rolled regex. These runs pin BOTH directions of that validation.
#
# Variable `validation` blocks are evaluated before any provider is configured, so the failing
# runs never reach the provider at all; `mock_provider` keeps the PASSING runs free of Azure
# calls, credentials and cost. No `command = apply` is needed because nothing here inspects
# resource state -- and note that a precondition reading a resource attribute under
# `command = plan` would resolve to the CONFIG value and pass unconditionally, which is exactly
# why this file tests the variable validation and not a precondition.
#
# ⚠️ `management_group_scoped_hub_id_fails` is not decoration. `parse_resource_id` ACCEPTS a
# management-group-scoped hub ID on its own (measured identically on azapi v2.12.0, the declared
# floor, and v2.13.0), and `locals.tf` takes `split("/", value.virtual_hub_id)[2]` to rebuild
# `parent_id` -- on such an ID that yields "Microsoft.Management" instead of a subscription. The
# `resource_group_name != ""` half of the condition is what stops it, and this run is what stops
# that half being deleted as redundant.

mock_provider "azapi" {}

variables {
  resource_types = {
    insights_diagnostic_settings = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
    network_azure_firewalls      = "Microsoft.Network/azureFirewalls@2025-07-01"
  }
}

run "valid_hub_id_passes" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-valid"
      }
    }
  }

  assert {
    condition     = length(azapi_resource.fw) == 1
    error_message = "A well-formed, resource-group-scoped virtualHubs ID must pass validation and plan one firewall."
  }
}

# ARM resource IDs are case-insensitive and `parse_resource_id` matches the type with
# `strings.EqualFold`, so the casing tolerance the old regex spelled out by hand
# (`[Mm]icrosoft\.[Nn]etwork`) survives the rewrite. Consumers that fed the module a lowercased
# ID before must keep working.
run "lowercased_hub_id_passes" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-hub/providers/microsoft.network/virtualhubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-lower"
      }
    }
  }

  assert {
    condition     = length(azapi_resource.fw) == 1
    error_message = "A lowercased virtualHubs ID must still pass: ARM IDs are case-insensitive and parse_resource_id compares the type with EqualFold."
  }
}

# The null short-circuit. `var.firewalls` has no `nullable = false`, so `null` is a reachable
# input that `locals.tf` normalises to `{}`; the validation must not trip on it.
run "null_firewalls_passes" {
  command = plan

  variables {
    firewalls = null
  }

  assert {
    condition     = length(azapi_resource.fw) == 0
    error_message = "A null `firewalls` map must short-circuit the resource ID validation and create nothing."
  }
}

run "empty_firewalls_passes" {
  command = plan

  variables {
    firewalls = {}
  }

  assert {
    condition     = length(azapi_resource.fw) == 0
    error_message = "An empty `firewalls` map must pass the resource ID validation and create nothing."
  }
}

run "malformed_hub_id_fails" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "not-a-resource-id"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-bad"
      }
    }
  }

  expect_failures = [var.firewalls]
}

run "wrong_resource_type_hub_id_fails" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-wrongtype"
      }
    }
  }

  expect_failures = [var.firewalls]
}

run "management_group_scoped_hub_id_fails" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/providers/Microsoft.Management/managementGroups/mg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-mgscope"
      }
    }
  }

  expect_failures = [var.firewalls]
}

# A second entry with a bad ID must fail the whole variable even when the first is fine --
# `alltrue` over the map, not just over its first element.
run "one_bad_entry_among_many_fails" {
  command = plan

  variables {
    firewalls = {
      fw_good = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-a"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-a"
      }
      fw_bad = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Network/virtualHubs/vhub-b"
        location            = "ukwest"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-b"
      }
    }
  }

  expect_failures = [var.firewalls]
}
