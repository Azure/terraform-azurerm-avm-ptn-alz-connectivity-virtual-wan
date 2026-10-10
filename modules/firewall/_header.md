# Basic example

This submodule deploys an Azure Firewall in the Virtual Hub to make it secured vHUB.

## Provider migration notes (`hashicorp/azurerm` -> `Azure/azapi`)

This submodule was migrated in place. Every public variable keeps its previous
name, type and default, and the request bodies reproduce
`hashicorp/azurerm` v4.81.0 (commit `5782a75422c68a0d0804ac16d97dcaf3df5ee2fa`)
member for member, including the members that provider sent unconditionally.
Three consequences are visible from outside the module:

- **`private_ip_address` and `public_ip_addresses` return real values.** Both
  are ARM-response-only data, and an earlier revision of this module published
  them as `null`. That regression was closed on by a **read-only**
  `data "azapi_resource" "fw_hub_ip_addresses"` carrying
  `response_export_values = ["properties.hubIPAddresses"]`. A data source has no
  writer, no `state.body` and no update path, so it has no adoption diff to
  poison — the **non-empty export list** is for the data source only. Both
  writers declare `response_export_values = []`, which is what TFFR4 requires;
  see the note below. The output names and the
  `resource_object[*].virtual_hub[0]` shape are unchanged. See the block at the
  top of `outputs.tf`.
- **The firewall is written by two resources.** `azapi_resource.fw` creates it
  and then goes inert (`lifecycle.ignore_changes` over its whole configurable
  surface); `azapi_update_resource.fw` owns every later write and does a
  GET-then-merge, so body members this module does not declare are preserved
  rather than dropped by a full PUT.
- **Tags are written by a separate `Microsoft.Resources/tags` `PUT`.** In
  0.17.x they rode on the merge writer, which can add or change a tag but
  cannot delete one, so removing a key was a silent no-op (`REG-1`). As of
  0.19.0 `azapi_resource_action.tags` `PUT`s at
  `Microsoft.Resources/tags/default` and **replaces the whole tag set**,
  matching AzureRM. A tag set out of band is therefore **removed** on the next
  apply — and is **not reported as drift**, because that resource's read issues
  no `GET`.
- **Merge is still additive for everything else, so it cannot un-set.** Setting
  `firewall_policy_id` back to `null` is a no-op against Azure even though the
  plan looks like it applied. `sku_name` and `zones` are the two AzureRM
  ForceNew properties that live inside `body`, so AzAPI cannot replace on them
  either — but they no longer apply *silently*: `lifecycle` preconditions on the
  merge writer fail the plan with an error naming the property and the exact
  `-replace` command to run. Change either deliberately, never in place.

`Microsoft.Network/azureFirewalls` has no row in the child-collection registry,
so the survival of its undeclared body members is **unmeasured**. `main.tf`
enumerates each path and says so explicitly.

## Notes on `main.tf`

> These decisions used to live as comment blocks inside `main.tf`. The AVM
> toolchain's `transform` step (mapotf) reorders resource attributes and drops
> free-standing comment blocks that are not attached to a surviving attribute
> line, so they were silently stripped by `avm pre-commit`. They are recorded
> here instead, where the toolchain does not rewrite them. **Sections 2 and 3
> are deliberate choices, not omissions — do not "fix" either by adding the
> attribute back.**

### 1. `response_export_values = []` on every writer, paired with `ignore_changes`

**This decision was reversed.** An earlier revision removed the
attribute from `azapi_resource.fw` and `azapi_resource.diagnostic_setting`
entirely — "not `["*"]`, not `[]`, not present at all". AVM spec **TFFR4** is
`Severity-MUST` and tagged `Class-Pattern`, so it binds this module:

> Authors **MUST** specify the `response_export_values` argument when using the
> AzAPI provider — `response_export_values = []`, even if empty.

Removing it breached a MUST. That earlier change is **retracted**; both
writers now declare `response_export_values = []`.

**The hazard the earlier change was reacting to is real, and `ignore_changes` is what
defuses it.** The attribute carries no `skip_on` tag (`azapi_resource.go` L77),
so `skip.CanSkipExternalRequest` (`skip.go` L14-56, called at `azapi_resource.go`
L826) returns false the moment it differs between plan and state. At **adoption**
the imported state holds `null` while the config holds `[]` — `[]` is not `null`,
so that is a difference — and it alone would drag the resource into `["update"]`
and PUT the stale `state.body`, which by the stale-body behaviour is whatever import wrote and
is never refreshed. Testing showed exactly that. `response_export_values` is
therefore in `local.full_writer_ignored_attributes` and in the `lifecycle`
blocks of **both** `azapi_resource` addresses: `ignore_changes` keeps the prior
value, so there is no adoption diff and no stale-body PUT.

⛔ **Never declare this attribute on an `azapi_resource` without the matching
`ignore_changes` entry.** The two changes are one change.

The value is `[]` and not an export path because nothing downstream needs one.
`outputs.tf` publishes `.id` and `.name` and constructs child IDs by string,
both of which stay known at plan time (the computed-output rule rules a computed `.output` out
of a module output entirely). The hub IP addresses come from the separate
read-only data source described above.

🔴 **A future change to either export list needs its own migration.** Because
`ignore_changes` pins the prior value, editing the list is a no-op on an
already-managed resource: the new value does not take effect without a state
operation (`terraform state rm` + re-import, or `-replace`). Treat it as a
breaking change with an upgrade-guide entry.

`avm_azapi_response_export_values_required` fires on **absence** and is now
satisfied. Note that the pinned AVM base tflint config sets it to
`severity = "notice"`, as it does for **all eight** enabled `avm_*` rules — so a
green `avm pr-check` is **not** evidence of MUST compliance, and never was. The
spec text is the authority, not the linter's exit code.

### 2. Neither replacement trigger is set

`replace_triggers_refs` (`azapi_resource.go` L76) is a **deviation** from
`modules/virtual-network-connection`, which does set it. That module is a single
full writer, so a PUT at adoption is its ordinary behaviour. This one is
create-only, and the attribute is non-skippable in exactly the same way
`response_export_values` is — a null-to-list difference at adoption would reopen
the update path this file exists to keep shut. The difference is that TFFR4
forces `response_export_values` to be declared, so it is declared and then
silenced in `ignore_changes`; `replace_triggers_refs` is not required by any
spec, and silencing replacement machinery in `ignore_changes` would HIDE a
replacement, so it is simply not set.

`replace_triggers_external_values` (`azapi_resource.go` L75) is **ruled out**,
not merely unused, and the reason is specific to adoption:

- its plan modifier is `RequiresReplaceIfNotNull`
  (`planmodifierdynamic/dynamic_requires_replace.go`, wired at L288), and that
  modifier **does not replace when the state value is null**;
- after `terraform import` the state value *is* null, so the first plan against
  an adopted firewall is an UPDATE, not a replacement;
- and the attribute carries no `skip_on:"update"` tag, so that null-to-value
  difference alone defeats `skip.CanSkipExternalRequest` and forces a full PUT
  of the stale `state.body` — the exact failure observed in testing.

So it buys nothing at adoption and costs the one thing this file exists to
prevent. Do not add it back.

**What replaces both:** `lifecycle` preconditions on the merge writer. They
cannot force a replacement — nothing in AzAPI can, for a property inside `body`
that `ignore_changes` silences — but they turn the silent no-op into a hard
plan-time **error** naming the property.

The residual price, stated where it is paid: AzureRM marked `name`
(`firewall_resource.go` L61), `sku_name` (L73), `zones` (L227) and `location`
ForceNew. `name` and `location` are AzAPI **attributes** and still force
replacement. `sku_name` and `zones` live inside `body`, which `ignore_changes`
silences, so changing either still does not REPLACE — but the preconditions fail
the plan and tell the consumer to use `-replace` deliberately.

### 3. Scale-down deviation on `azapi_update_resource.fw`, recorded rather than fixed

`firewall_resource.go` L764-771 truncated the live `addresses` array to the first
`newCount` entries when the public IP count shrank, and sent the truncated array
alongside the new count. This writer sends `count` only, so the merge preserves
the **full** live `addresses` array next to a smaller `count`. What ARM does with
that pairing is **UNMEASURED**.

Scale-**up** is unaffected: AzureRM passed the live array through unchanged
there, which is what a merge that omits the key also achieves.
The existing keyed `azurerm_firewall.fw` and diagnostic-setting resources remain the managed-IP implementation. A nonempty `firewalls[key].ip_configurations` map selects a separate, single-firewall AzAPI child. Each entry requires an explicit `name` and `public_ip_address_id`; stable keys must be known at plan time, while IDs may be computed.

Null `vhub_public_ip_count` remains one managed IP for an empty map, or customer-only mode for a nonempty map. Explicit zero is accepted only with customer IPs. Counts retain their string input type and are converted internally to numbers.

Customer opt-in requires subscription-scoped firewall read permission for AzAPI inventory. The helper reads the AzureRM provider's local client configuration solely to identify the subscription used by its existing resources; this does not perform a new Azure control-plane operation. Managed-only callers instantiate neither this metadata read nor the inventory data source.

The state-only `terraform_data.public_ip_mode` record deliberately keeps its original input. Its postcondition raises an error for a requested mode change even when the marker otherwise has no planned changes. No Azure resource/IP drift is ignored. Keep this resource address stable in future refactors. Removing a firewall also removes the marker normally; no manual state migration is required.

Old resource, virtual-hub, null/empty and diagnostic composite-ID output contracts remain available. Customer maintenance is not guaranteed to be outage-free. The root documentation describes prerequisites and maintenance guidance.
