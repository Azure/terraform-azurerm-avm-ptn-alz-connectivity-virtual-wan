# TFNFR38 -- Resource ID Variable Validation (Severity-MUST; Class-Resource, Class-Pattern,
# Class-Utility). `expressroute_gateways[*].virtual_hub_id` is validated with
# `provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", ...)` rather than a
# hand-rolled regex. See `modules/firewall/tests/resource_id_validation.tftest.hcl` for the
# full rationale, including why the management-group run exists.
#
# Variable `validation` runs before any provider is configured, so the failing runs never reach
# the provider; `mock_provider` keeps the passing runs free of Azure calls and cost.

mock_provider "azapi" {}

variables {
  resource_types = {
    network_express_route_gateways = "Microsoft.Network/expressRouteGateways@2025-07-01"
  }
}

run "valid_hub_id_passes" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-valid"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
      }
    }
  }

  assert {
    condition     = azapi_resource.this["gw_a"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    error_message = "A valid hub ID must pass validation and still feed the parent_id reconstruction that the validation exists to protect."
  }
}

# `parse_resource_id` matches the type with `strings.EqualFold`, so the casing tolerance the old
# regex spelled out by hand (`[Mm]icrosoft\.[Nn]etwork`) survives the rewrite.
run "lowercased_hub_id_passes" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-lower"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-hub/providers/microsoft.network/virtualhubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
      }
    }
  }

  assert {
    condition     = length(azapi_resource.this) == 1
    error_message = "A lowercased virtualHubs ID must still pass: ARM IDs are case-insensitive."
  }
}

# The null short-circuit. `var.expressroute_gateways` has no `nullable = false`, and `main.tf`
# normalises null to `{}`, so the validation must not trip on it.
run "null_gateways_passes" {
  command = plan

  variables {
    expressroute_gateways = null
  }

  assert {
    condition     = length(azapi_resource.this) == 0
    error_message = "A null `expressroute_gateways` map must short-circuit the resource ID validation and create nothing."
  }
}

run "empty_gateways_passes" {
  command = plan

  variables {
    expressroute_gateways = {}
  }

  assert {
    condition     = length(azapi_resource.this) == 0
    error_message = "An empty `expressroute_gateways` map must pass the resource ID validation and create nothing."
  }
}

run "malformed_hub_id_fails" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-bad"
        virtual_hub_id      = "not-a-resource-id"
        location            = "uksouth"
        resource_group_name = "rg-test"
      }
    }
  }

  expect_failures = [var.expressroute_gateways]
}

run "wrong_resource_type_hub_id_fails" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-wrongtype"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualWans/vwan-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
      }
    }
  }

  expect_failures = [var.expressroute_gateways]
}

# `split("/", virtual_hub_id)[2]` would yield "Microsoft.Management" here, not a subscription.
run "management_group_scoped_hub_id_fails" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_a = {
        name                = "ergw-mgscope"
        virtual_hub_id      = "/providers/Microsoft.Management/managementGroups/mg-test/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
      }
    }
  }

  expect_failures = [var.expressroute_gateways]
}

run "one_bad_entry_among_many_fails" {
  command = plan

  variables {
    expressroute_gateways = {
      gw_good = {
        name                = "ergw-a"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-a"
        location            = "uksouth"
        resource_group_name = "rg-test"
      }
      gw_bad = {
        name                = "ergw-b"
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Network/virtualHubs/vhub-b"
        location            = "ukwest"
        resource_group_name = "rg-test"
      }
    }
  }

  expect_failures = [var.expressroute_gateways]
}
