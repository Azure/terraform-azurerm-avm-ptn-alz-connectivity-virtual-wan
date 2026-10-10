# Basic example

This submodule deploys an Azure ExpressRoute Gateway in the Virtual Hub

## Provider migration: AzureRM to AzAPI

This module now creates `Microsoft.Network/expressRouteGateways` through the AzAPI provider
instead of `azurerm_express_route_gateway`. The input variable `expressroute_gateways` is
**unchanged** — no consumer edit is required.

### The shape, and why it is this shape

The gateway carries `properties.expressRouteConnections`, but the connections themselves are
created by a **different** module (`modules/expressroute-gateway-connection`). A full `PUT`
against the gateway that omits that array **deletes every ExpressRoute connection on it**. The
AzureRM resource avoided this by listing the connections and re-attaching them to the payload
on both the create and the update path; a Terraform module cannot, because
`expressRouteCircuitPeering` is a required field on every connection and those peerings are
routinely owned by another team, subscription or tenant.

So the module uses two writers:

- **`azapi_resource.this` — create-only.** It creates the gateway and then goes inert: a
  17-entry `lifecycle { ignore_changes = [...] }` list pins every `azapi_resource` attribute
  that could otherwise drag it back onto the `PUT` path. It never declares the connections
  array.
- **`azapi_update_resource.this` — day 2.** It `GET`s the live gateway and merges, so it
  preserves `expressRouteConnections` without ever naming them. It declares exactly the three
  things AzureRM's `Update` could change: scale units, non-Virtual-WAN traffic, and tags.

### Behaviour notes

- **`resource` output element type changed.** It is still a list, in the same order and with
  the same cardinality, but each element is an `azapi_resource` object rather than an
  `azurerm_express_route_gateway` one. Per-attribute reads such as `.scale_units` are no
  longer available on it; `.id`, `.name` and `.location` are. `resource_id` and
  `resource_object` are unchanged, and `resource_object` still carries `scale_units` and
  `resource_group` — projected from configuration rather than read back, so they stay known at
  plan time.
- **`virtual_hub_id` must now be a full resource ID.** It always was in practice; it is now
  *validated*, because the AzAPI `parent_id` is reconstructed from the subscription segment of
  that ID plus `resource_group_name`.
- **Tags are written by a separate `Microsoft.Resources/tags` `PUT`.** In 0.17.x, tags rode on
  the day-2 merge writer, which can add or change a tag but *cannot delete one* — removing a key
  from `tags` was a silent no-op in Azure (`REG-1`). As of 0.19.0 tags travel on
  `azapi_resource_action.tags`, which `PUT`s at `Microsoft.Resources/tags/default` and
  **replaces the whole tag set**, matching AzureRM. Two consequences: a tag set **out of band is
  removed** on the next apply, the same as AzureRM would have done; and out-of-band tags are
  **not reported as drift**, because that resource's read issues no `GET`.
- **`response_export_values` is set to `[]` on both writers.** AVM spec TFFR4 is
  `Severity-MUST` and tagged `Class-Pattern`, so it binds this module: the attribute must be
  declared, even when empty. An earlier change that removed it repo-wide breached that MUST
  and has been retracted. It is safe here only because `response_export_values` is also in the
  full writer's `lifecycle.ignore_changes`: the attribute is non-skippable in azapi, so the
  null-vs-`[]` difference at adoption would otherwise drive the create-only writer into an
  update and issue a stale `PUT`, and on this resource type that `PUT` is the connection
  deletion above. **A future change to the export list needs its own migration** —
  `ignore_changes` pins the prior value, so a new list does not take effect without a state
  operation. Note also that `avm_azapi_response_export_values_required` runs at `notice`
  severity under the pinned AVM base config, so a green `avm pr-check` is not evidence of
  MUST compliance.
