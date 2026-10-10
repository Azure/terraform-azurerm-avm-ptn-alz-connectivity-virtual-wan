# TFNFR38 -- Resource ID Variable Validation (Severity-MUST; Class-Resource, Class-Pattern,
# Class-Utility). `vpn_sites[*].virtual_wan_id` is validated with
# `provider::azapi::parse_resource_id("Microsoft.Network/virtualWans", ...)` rather than a
# hand-rolled regex. See `modules/firewall/tests/resource_id_validation.tftest.hcl` for the
# full rationale, including why the management-group run exists.
#
# Variable `validation` runs before any provider is configured, so the failing runs never reach
# the provider; `mock_provider` keeps the passing runs free of Azure calls and cost.

mock_provider "azapi" {}

variables {
  resource_types = {
    network_vpn_sites = "Microsoft.Network/vpnSites@2025-07-01"
  }
}

run "valid_wan_id_passes" {
  command = plan

  variables {
    vpn_sites = {
      site_a = {
        location            = "eastus"
        name                = "vpnsite-valid"
        resource_group_name = "rg-test"
        virtual_wan_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-wan/providers/Microsoft.Network/virtualWans/vwan-test"
        links = [
          {
            name = "link-a"
          }
        ]
      }
    }
  }

  assert {
    condition     = azapi_resource.this["site_a"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    error_message = "A valid WAN ID must pass validation and still feed the parent_id reconstruction that the validation exists to protect."
  }
}

# `parse_resource_id` matches the type with `strings.EqualFold`, so the casing tolerance the old
# regex spelled out by hand (`[Mm]icrosoft\.[Nn]etwork`) survives the rewrite.
run "lowercased_wan_id_passes" {
  command = plan

  variables {
    vpn_sites = {
      site_a = {
        location            = "eastus"
        name                = "vpnsite-lower"
        resource_group_name = "rg-test"
        virtual_wan_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-wan/providers/microsoft.network/virtualwans/vwan-test"
        links = [
          {
            name = "link-a"
          }
        ]
      }
    }
  }

  assert {
    condition     = length(azapi_resource.this) == 1
    error_message = "A lowercased virtualWans ID must still pass: ARM IDs are case-insensitive."
  }
}

# The null short-circuit. `var.vpn_sites` is a REQUIRED variable with no `nullable = false`, so
# `null` is a reachable input that `main.tf` normalises to `{}`; validation must not trip on it.
run "null_sites_passes" {
  command = plan

  variables {
    vpn_sites = null
  }

  assert {
    condition     = length(azapi_resource.this) == 0
    error_message = "A null `vpn_sites` map must short-circuit the resource ID validation and create nothing."
  }
}

run "empty_sites_passes" {
  command = plan

  variables {
    vpn_sites = {}
  }

  assert {
    condition     = length(azapi_resource.this) == 0
    error_message = "An empty `vpn_sites` map must pass the resource ID validation and create nothing."
  }
}

run "malformed_wan_id_fails" {
  command = plan

  variables {
    vpn_sites = {
      site_a = {
        location            = "eastus"
        name                = "vpnsite-bad"
        resource_group_name = "rg-test"
        virtual_wan_id      = "not-a-resource-id"
        links = [
          {
            name = "link-a"
          }
        ]
      }
    }
  }

  expect_failures = [var.vpn_sites]
}

# The nearest wrong type there is: a Virtual Hub rather than a Virtual WAN. The old regex
# distinguished these with `virtualWans` vs `virtualHubs` in the pattern; the literal type
# argument to `parse_resource_id` does the same job.
run "wrong_resource_type_wan_id_fails" {
  command = plan

  variables {
    vpn_sites = {
      site_a = {
        location            = "eastus"
        name                = "vpnsite-wrongtype"
        resource_group_name = "rg-test"
        virtual_wan_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-wan/providers/Microsoft.Network/virtualHubs/vhub-test"
        links = [
          {
            name = "link-a"
          }
        ]
      }
    }
  }

  expect_failures = [var.vpn_sites]
}

# `split("/", virtual_wan_id)[2]` would yield "Microsoft.Management" here, not a subscription.
run "management_group_scoped_wan_id_fails" {
  command = plan

  variables {
    vpn_sites = {
      site_a = {
        location            = "eastus"
        name                = "vpnsite-mgscope"
        resource_group_name = "rg-test"
        virtual_wan_id      = "/providers/Microsoft.Management/managementGroups/mg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        links = [
          {
            name = "link-a"
          }
        ]
      }
    }
  }

  expect_failures = [var.vpn_sites]
}

run "one_bad_entry_among_many_fails" {
  command = plan

  variables {
    vpn_sites = {
      site_good = {
        location            = "eastus"
        name                = "vpnsite-a"
        resource_group_name = "rg-test"
        virtual_wan_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-wan/providers/Microsoft.Network/virtualWans/vwan-a"
        links = [
          {
            name = "link-a"
          }
        ]
      }
      site_bad = {
        location            = "westus"
        name                = "vpnsite-b"
        resource_group_name = "rg-test"
        virtual_wan_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Network/virtualWans/vwan-b"
        links = [
          {
            name = "link-b"
          }
        ]
      }
    }
  }

  expect_failures = [var.vpn_sites]
}
