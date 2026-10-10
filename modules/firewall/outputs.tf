# ===========================================================================
# `private_ip_address` and `public_ip_addresses` ARE RESTORED. The migration
# regression that made them `null` was closed on.
#
# WHAT THE REGRESSION WAS. Both are ARM-RESPONSE-ONLY data. AzureRM populated
# them from the `Computed` schema fields `virtual_hub.0.private_ip_address`
# and `virtual_hub.0.public_ip_addresses` (`firewall_resource.go` L214-222,
# flattened at L804-819) out of the CreateOrUpdate/Read response. AzAPI
# surfaces response data in exactly one place -- the computed `output`
# attribute -- and `output` is populated by exactly one thing,
# `response_export_values`. This module will not put a NON-EMPTY export list
# on `azapi_resource.fw`: the attribute is non-skippable (`azapi_resource.go`
# L77) and the computed-output rule rules a computed `.output` out of a module output
# anyway. So the values were published as `null`.
#
# WHY THEY ARE NOT NULL ANY MORE. `main.tf` adds a READ-ONLY
# `data "azapi_resource" "fw_hub_ip_addresses"` with
# `response_export_values = ["properties.hubIPAddresses"]`. It was decided
# decided that a DATA SOURCE is exempt from The computed-output rule: it has no writer, no
# `state.body` and no update path, so there is no adoption diff for
# `response_export_values` to poison. That decision is recorded in full on the
# data source itself -- read it before touching this file.
#
# ✅ SEPARATELY, AND NOW: `azapi_resource.fw` and
# `azapi_resource.diagnostic_setting` DO declare `response_export_values`,
# because AVM spec TFFR4 is Severity-MUST and Class-Pattern and requires the
# attribute on every AzAPI resource "even if empty". They declare `[]`, and
# each pairs it with a `response_export_values` entry in
# `lifecycle.ignore_changes`, which is what removes the null-vs-`[]` adoption
# diff that would otherwise force a stale-body PUT.
#
# ⛔ The NON-EMPTY list is still for the DATA SOURCE ONLY. Giving a writer a
# real export path, or declaring the attribute on a writer WITHOUT the
# matching `ignore_changes` entry, reopens the stale PUT. And a
# future change to any export list in this module needs its own migration,
# because `ignore_changes` pins the prior value: the new list will not take
# effect without a state operation.
#
# The names, types and semantics below are the pre-migration ones, taken from
# `modules/firewall/outputs.tf` at commit 589d10e^ (the last azurerm-based
# revision): `private_ip_address` is a map of firewall key to a single
# address string, `public_ip_addresses` a map of firewall key to a list of
# address strings, and both collapse to `null` when `var.firewalls` is null.
# ===========================================================================

# Null-safety for both outputs lives in `locals.tf`
# (`firewall_private_ip_addresses` / `firewall_public_ip_addresses`).


output "azure_firewall_resource_names" {
  description = "Azure Firewall resource name"
  value       = var.firewalls != null ? [for fw in local.firewall_summaries : fw.name] : []
}

output "diagnostic_settings_resource_ids" {
  description = "Value of the diagnostic settings resource ID for Azure Firewall"
  value = merge(
    { for key, value in azapi_resource.diagnostic_setting : key => value.id },
    merge([for firewall in module.customer_firewalls : firewall.legacy_diagnostic_settings_resource_ids]...)
  )
}

output "full_writer_ignored_attributes" {
  description = "Attributes the create-only full writer must never diff on after create. Audited against azapi v2.12.0 `AzapiResourceModel`; see the comment on `local.full_writer_ignored_attributes`. Published so `terraform test` can assert the list against the literal in `main.tf`'s `lifecycle` block, which HCL will not let a variable or local drive."
  value       = local.full_writer_ignored_attributes
}

output "private_ip_address" {
  description = "Azure Firewall IP addresses"
  value       = var.firewalls != null ? merge(local.firewall_private_ip_addresses, { for key, firewall in module.customer_firewalls : key => firewall.private_ip_address }) : null
}

output "public_ip_addresses" {
  description = "Azure Firewall IP addresses"
  value       = var.firewalls != null ? merge(local.firewall_public_ip_addresses, { for key, firewall in module.customer_firewalls : key => firewall.public_ip_addresses }) : null
}

output "resource" {
  description = "Azure Firewall resource. 🔴 The map values are `azapi_resource` objects, so their members are AzAPI's, not AzureRM's: `.body`, `.id`, `.name`, `.location`, `.tags`, and a computed `.output` that is EMPTY because the writer declares `response_export_values = []` -- the empty list TFFR4 requires, not an export of anything. Do not read `.output` here -- the hub IP addresses come from `private_ip_address` / `public_ip_addresses`, which are fed by a separate read-only data source."
  value       = merge(azapi_resource.fw, { for key, firewall in module.customer_firewalls : key => firewall.legacy_resource })
}

output "resource_id" {
  description = "Azure Firewall resource ID"
  value       = var.firewalls != null ? [for fw in local.firewall_summaries : fw.id] : []
}

output "resource_ids" {
  description = "Azure Firewall resource IDs"
  value       = var.firewalls != null ? { for key, value in local.firewall_summaries : key => value.id } : null
}

output "resource_names" {
  description = "Azure Firewall resource names"
  value       = var.firewalls != null ? { for key, value in local.firewall_summaries : key => value.name } : null
}

output "resource_object" {
  description = "Azure Firewall resource object. The `virtual_hub` list keeps AzureRM's one-element shape because `modules/virtual-wan/outputs.tf` indexes it positionally, and all four of its members carry real values again."
  value = var.firewalls != null ? merge(
    {
      for key, fw in azapi_resource.fw : key => {
        id   = fw.id
        name = fw.name
        # `virtual_hub_id` and `public_ip_count` are rebuilt from CONFIGURATION,
        # not from a response, so they stay known at plan time (
        # observed in testing). The other two are response-only and come from the read-only data
        # source; `main.tf` records why that is allowed.
        virtual_hub = tolist([
          {
            virtual_hub_id      = tostring(local.firewalls[key].virtual_hub_id)
            public_ip_count     = tonumber(local.firewall_public_ip_counts[key])
            private_ip_address  = try(tostring(local.firewall_private_ip_addresses[key]), null)
            public_ip_addresses = tolist([for address in local.firewall_public_ip_addresses[key] : tostring(address)])
          }
        ])
      }
    },
    # Managed and customer-IP firewalls can be mixed across hubs. Both branches
    # must build the same element type, or the conditional below cannot convert
    # the merged object to a map and the plan fails.
    {
      for key, firewall in module.customer_firewalls : key => {
        id   = firewall.resource_id
        name = firewall.name
        virtual_hub = tolist([
          for hub in firewall.virtual_hub : {
            virtual_hub_id      = tostring(hub.virtual_hub_id)
            public_ip_count     = tonumber(hub.public_ip_count)
            private_ip_address  = try(tostring(hub.private_ip_address), null)
            public_ip_addresses = tolist([for address in hub.public_ip_addresses : tostring(address)])
          }
        ])
      }
    }
  ) : {}
}
