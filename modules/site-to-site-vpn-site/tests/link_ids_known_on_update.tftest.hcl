# Why this file exists
# --------------------
# Observed in an earlier test. Flipping ONE TAG on a VPN site made every downstream VPN connection
# plan a full PUT of its `properties.vpnLinkConnections` list, and the governing gate
# FAILed on it.
#
# The cause was in `outputs.tf`: each link ID was read out of
# `azapi_resource.this[key].output`, which is a COMPUTED attribute. Any update makes it
# unknown, so every link ID went unknown, so every consumer's `vpn_site_link_id` went
# unknown, so each connection's whole link-connection array became `(known after apply)`.
# AzureRM kept those IDs known across an in-place update, so this was a MIGRATION
# REGRESSION with a live blast radius: a tag edit re-PUTs every tunnel on the site.
#
# `null_optionals.tftest.hcl` could not have caught it. That file asserts what the body
# CONTAINS; this one asserts what is KNOWN AT PLAN TIME, and only on an UPDATE -- a create
# plan has everything unknown anyway, so the bug is invisible there. That is why this is a
# create run followed by an update run rather than a single plan.
#
# HOW THE ASSERTION WORKS, because it is not obvious: there is no `isknown()` function in
# HCL. Instead each assertion reads the link ID and compares it. If the ID were unknown,
# the condition itself could not be evaluated at plan time and `terraform test` reports the
# run as failed. So an assertion that evaluates AT ALL on an update plan is the proof.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

mock_provider "azapi" {
  # Pin the resource ID so the constructed child ID is an exact, assertable string rather
  # than a randomly generated mock value.
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/vpnsite-known"
    }
  }
}

variables {
  resource_types = {
    network_vpn_sites = "Microsoft.Network/vpnSites@2025-07-01"
  }

  vpn_sites = {
    site_a = {
      location            = "eastus"
      name                = "vpnsite-known"
      resource_group_name = "rg-test"
      virtual_wan_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
      tags                = { stage = "1" }
      links = [
        { name = "link-a" },
        { name = "link-b" },
      ]
    }
  }
}

# Establish state. The mocked apply is what makes the NEXT run an update rather than a
# create -- without it there is nothing to update and the regression cannot appear.
run "create" {
  command = apply

  assert {
    condition     = length(output.links["site_a"]) == 2
    error_message = "The site must expose one link entry per configured link."
  }
}

# 🔴 THE REGRESSION TEST. Only the tag moves. Nothing about the links changes.
run "tag_update_keeps_link_ids_known" {
  command = plan

  variables {
    vpn_sites = {
      site_a = {
        location            = "eastus"
        name                = "vpnsite-known"
        resource_group_name = "rg-test"
        virtual_wan_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
        tags                = { stage = "2" }
        links = [
          { name = "link-a" },
          { name = "link-b" },
        ]
      }
    }
  }

  # If the ID were read from `.output` again, this condition would be unknown on an update
  # plan and the run would fail. That failure IS the regression signal.
  assert {
    condition     = output.links["site_a"][0].id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/vpnsite-known/vpnSiteLinks/link-a"
    error_message = "link-a's ID must be KNOWN at plan time on an update, and must be built deterministically from the site ID. An unknown ID here makes every downstream VPN connection plan a full PUT of its vpnLinkConnections list (observed in testing)."
  }

  assert {
    condition     = output.links["site_a"][1].id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/vpnsite-known/vpnSiteLinks/link-b"
    error_message = "link-b's ID must be KNOWN at plan time on an update. See the note in `modules/site-to-site-vpn-site/outputs.tf`."
  }

  # The parent module indexes this list POSITIONALLY, so order is part of the contract and
  # a deterministic ID must not be allowed to quietly reorder it.
  assert {
    condition     = output.links["site_a"][0].name == "link-a" && output.links["site_a"][1].name == "link-b"
    error_message = "Link order must follow the CONFIGURED order: the parent module indexes this list positionally."
  }
}
