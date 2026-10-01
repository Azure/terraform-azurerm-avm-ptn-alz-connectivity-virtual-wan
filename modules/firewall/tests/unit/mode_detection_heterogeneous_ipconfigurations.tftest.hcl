mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
    }
  }
}
mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = { firewalls = [] }
    }
  }
  mock_data "azapi_resource" {
    defaults = {
      output = {
        address           = "203.0.113.10"
        allocation_method = "Static"
        association       = null
        ip_version        = "IPv4"
        location          = "eastus"
        sku               = "Standard"
        tier              = "Regional"
        type              = "Standard"
        virtual_wan_id    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/wan-test"
        zones             = ["1", "2", "3"]
      }
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
      output = {
        properties = {
          hubIPAddresses       = null
          threatIntelMode      = null
          additionalProperties = {}
        }
      }
    }
  }
}

variables {
  enable_telemetry = false
  # Grow attempt: an already-existing customer-mode firewall (discovered below with 2 customer IPs, A+B,
  # in the exact heterogeneous real Azure ipConfigurations shape) requests a same-mode change to 3 customer
  # IPs (A+B+C). This must never cross the managed/customer mode boundary and must be accepted by the
  # cross-mode guard.
  firewalls = {
    hub = {
      name                = "fw-secured-hub"
      location            = "eastus"
      resource_group_name = "rg-multi-ip"
      virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/virtualHubs/hub-test"
      sku_tier            = "Standard"
      ip_configurations = {
        a = {
          name                 = "ip-a"
          public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/publicIPAddresses/pip-multi-a"
        }
        b = {
          name                 = "ip-b"
          public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/publicIPAddresses/pip-multi-b"
        }
        c = {
          name                 = "ip-c"
          public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/publicIPAddresses/pip-multi-c"
        }
      }
    }
  }
}

# Guards modules/firewall/locals.tf's existing_customer_mode against a heterogeneous ipConfigurations
# response. For a secured-hub firewall with two customer public IPs, Azure's ipConfigurations response is
# a HETEROGENEOUS TUPLE: ip-a's properties object carries privateIPAddress (a
# string), ip-b's properties object entirely omits that key (ARM key-omission, not null) - alongside
# both elements' nested publicIPAddress objects. Terraform's coalesce() requires all arguments to convert
# to one common element type; this specific mix (a key present-with-string-value on one element, absent on
# the other, both nested under an object with its own nested object field) cannot be unified, so
# `coalesce(firewall.properties.ipConfigurations, [])` errors, and an enclosing try(..., []) would silently
# swallow that error and substitute an empty list. existing_customer_mode would then be computed over that
# empty list and evaluate to false - a genuine customer-mode firewall misclassified as "managed" - and
# the cross-mode guard in modules/firewall/main.tf's terraform_data.public_ip_mode precondition would
# reject an ordinary same-mode grow (adding a third customer IP) as though it were an illegal
# managed<->customer conversion.
#
# NOTE: this is NOT triggered by heterogeneity alone -
# a uniformly-shaped or superficially-"different" mock does not reproduce it, because Terraform's type
# unifier can still find a common object type for many mixed-but-compatible shapes. The trigger is
# specifically UNIFICATION-IMPOSSIBLE heterogeneity: one key present with a string value on one element,
# entirely absent (not null) on another, alongside a nested object field on every element. This fixture
# reproduces that exact shape, not merely "some heterogeneity."
run "grow_third_customer_ip_on_existing_two_ip_firewall_with_heterogeneous_ipconfigurations" {
  command = plan
  override_data {
    target = data.azapi_resource_list.firewalls[0]
    values = {
      output = {
        firewalls = [{
          id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/azureFirewalls/fw-secured-hub"
          name = "fw-secured-hub"
          properties = {
            ipConfigurations = [
              {
                name = "ip-a"
                properties = {
                  privateIPAddress = "10.224.10.132"
                  publicIPAddress  = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/publicIPAddresses/pip-multi-a" }
                }
              },
              {
                name = "ip-b"
                properties = {
                  # privateIPAddress key is intentionally absent here, matching the Azure response
                  # exactly (key omitted, not set to null) - this is what makes the tuple
                  # unification-impossible when combined with ip-a's string-valued privateIPAddress above.
                  publicIPAddress = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/publicIPAddresses/pip-multi-b" }
                }
              }
            ]
          }
        }]
      }
    }
  }
  assert {
    condition     = local.existing_customer_mode["hub"] == true
    error_message = "An existing firewall with real (heterogeneous) customer ipConfigurations must be detected as customer mode, not misclassified as managed via a silently-swallowed coalesce() error."
  }
}

# Explicit control, in the SAME file as the heterogeneous case above: the ipConfigurations body Azure
# returns for a secured-hub firewall with one customer public IP, whose single element is
# internally uniform (one element, one shape - nothing to unify against). This proves the defect is
# specifically about UNIFICATION-IMPOSSIBLE heterogeneity across multiple elements, not "any
# ipConfigurations list" or "any customer-mode firewall" - the same existing_customer_mode expression must
# correctly read this shape as customer mode via a bare coalesce() that succeeds (no try()-swallowed error
# involved at all), side-by-side in this file with the heterogeneous case that requires the
# try()-wrapped for-expression.
#
# NOTE: the id below is placed in the SAME resource group ("rg-multi-ip") that this file's
# `firewalls.hub` variable requests, so this control isolates existing_customer_mode's own
# coalesce/unification behavior from existing_firewalls' resource-group filter, which is a separate
# concern.
run "single_uniform_customer_ip_control_is_detected_without_needing_the_fix" {
  command = plan
  override_data {
    target = data.azapi_resource_list.firewalls[0]
    values = {
      output = {
        firewalls = [{
          id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-multi-ip/providers/Microsoft.Network/azureFirewalls/fw-secured-hub"
          name = "fw-secured-hub"
          properties = {
            ipConfigurations = [
              {
                name = "customer-owned-ip-config"
                properties = {
                  privateIPAddress = "10.224.8.132"
                  publicIPAddress  = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-single-ip/providers/Microsoft.Network/publicIPAddresses/pip-single" }
                }
              }
            ]
          }
        }]
      }
    }
  }
  assert {
    condition     = local.existing_customer_mode["hub"] == true
    error_message = "A real single-IP customer-mode firewall body (internally uniform, no unification conflict) must be detected as customer mode - this control proves the bug is specific to unification-impossible heterogeneity, not to customer mode itself."
  }
}
