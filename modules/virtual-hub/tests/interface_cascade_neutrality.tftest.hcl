# TFFR6 / TFFR7 / TFFR8 interface cascade -- the CHILD half of the neutrality proof.
#
# `modules/virtual-wan` now passes `resource_types`, `retry`, `timeouts` and `ignore_body_changes`
# into this module. With the consumer setting nothing, the payload it sends is an all-null
# `resource_types` slot, an all-null `retry`, an all-null `timeouts` and an empty
# `ignore_body_changes` list -- that exact payload is pinned at the sending end by
# `modules/virtual-wan/tests/interface_cascade_neutrality.tftest.hcl`.
#
# This file pins the RECEIVING end: given that payload, the resources this module declares must end
# up with this module's OWN declared defaults, not with nulls. That is the property that makes the
# whole cascade behaviour-neutral, and it rests on Terraform substituting an `optional(T, default)`
# attribute's default for a null it receives from a parent.
#
# This module is a deliberate choice of witness. Its `timeouts` defaults are 60m/5m/60m/60m
# (`azurerm` v4.81.0 `virtual_hub_resource.go` L47-52), NOT the 30m used elsewhere in this
# repository and NOT the 90m used by `../site-to-site-gateway`. If a cascaded null were to reach
# the resource as a null, or if the parent's own values were to win, these assertions would see a
# different number.
#
# 🔴 WHY `command = apply`. `timeouts` and `retry` are provider-level arguments, not body content.
# A plan-only run reports them from configuration, which would make the assertions restate the
# config rather than test it. Applying against `mock_provider "azapi"` -- no Azure call, no
# credentials, no cost -- writes them into state and the assertions read them back from there.
#
# 🔴 NOT COVERED: `ignore_body_changes` is a write-only argument (`azapi_resource.go` L255
# `WriteOnly: true`), so its state value is permanently null and no assertion can observe it. The
# empty-list half of the payload is evidenced only at the sending end.

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-cascade"
    }
  }

  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  virtual_hubs = {
    hub_a = {
      name                                   = "vhub-cascade"
      location                               = "uksouth"
      resource_group_name                    = "rg-test"
      address_prefix                         = "10.0.0.0/23"
      virtual_wan_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/vwan-test"
      sku                                    = "Standard"
      hub_routing_preference                 = "ExpressRoute"
      virtual_router_auto_scale_min_capacity = 2
    }
  }

  # VERBATIM the payload `modules/virtual-wan` sends when its own inputs are unset. Written out
  # explicitly rather than omitted, because omitting them would test the module's own defaults --
  # which is not the question. The question is what an explicit null from a parent does.
  resource_types = {
    network_virtual_hubs = null
  }
  ignore_body_changes = {
    network_virtual_hubs = []
  }
  retry = {
    error_message_regex  = null
    interval_seconds     = null
    max_interval_seconds = null
  }
  timeouts = {
    create = null
    read   = null
    update = null
    delete = null
  }
}

run "an_all_null_cascade_payload_lands_on_this_modules_own_defaults" {
  command = apply

  assert {
    condition = (
      azapi_resource.this["hub_a"].type == "Microsoft.Network/virtualHubs@2025-07-01" &&
      azapi_update_resource.this["hub_a"].type == "Microsoft.Network/virtualHubs@2025-07-01"
    )
    error_message = "A null resource_types leaf from the parent must resolve to this module's own declared API version on both writers."
  }

  assert {
    condition = (
      azapi_resource.this["hub_a"].timeouts.create == "60m" &&
      azapi_resource.this["hub_a"].timeouts.read == "5m" &&
      azapi_resource.this["hub_a"].timeouts.update == "60m" &&
      azapi_resource.this["hub_a"].timeouts.delete == "60m"
    )
    error_message = "A null timeouts payload from the parent must resolve to azurerm_virtual_hub's own 60m/5m/60m/60m, not to a null and not to the parent's value."
  }

  # Two separate clauses rather than a comparison against a literal list: `tolist(x) == tolist([])`
  # is unreliable here because the tuple literal converts to `list(dynamic)` while the attribute is
  # `list(string)`, and cty refuses to compare the two.
  assert {
    condition     = azapi_resource.this["hub_a"].retry.error_message_regex != null
    error_message = "A null retry payload from the parent must not leave error_message_regex null; this module declares a default for it."
  }

  assert {
    condition = (
      length(azapi_resource.this["hub_a"].retry.error_message_regex) == 1 &&
      azapi_resource.this["hub_a"].retry.error_message_regex[0] == "ReferencedResourceNotProvisioned" &&
      azapi_resource.this["hub_a"].retry.interval_seconds == 10 &&
      azapi_resource.this["hub_a"].retry.max_interval_seconds == 180
    )
    error_message = "A null retry payload from the parent must resolve to this module's own retry defaults."
  }
}
