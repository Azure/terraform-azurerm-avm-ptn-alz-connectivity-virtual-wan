# Basic example

This submodule deploys an Azure ExpressRoute Connection between ExpressRoute Gateway and ExpressRoute Circuit in the Virtual Hub

## Provider migration: AzureRM to AzAPI

This module now creates `Microsoft.Network/expressRouteGateways/expressRouteConnections` through
the AzAPI provider instead of `azurerm_express_route_connection`. The input variable
`er_circuit_connections` is **unchanged** — no consumer edit is required.

Two behaviour notes:

- **`resource` output element type changed.** It is still a list, in the same order and with the
  same cardinality, but each element is an `azapi_resource` object rather than an
  `azurerm_express_route_connection` one. Per-attribute reads such as `.routing_weight` are no
  longer available; `.id` and `.name` are. `resource_id` is unchanged.
- **`express_route_gateway_bypass_enabled` is still inert, on purpose.** The variable is accepted
  and documented but has never been wired to the resource, so AzureRM sent the schema default
  `false` on every create. The AzAPI module reproduces that literal rather than starting to honour
  the input, because honouring it could enable ExpressRoute Fast Path on existing connections at
  the first post-migration apply. Making the input live is a separate, deliberate change.

## Design notes

### Per-resource timeout defaults

`var.timeouts` keeps its published shape -- same variable name, same four attributes, same
types -- but its attributes no longer carry a blanket `"30m"`/`"5m"` default. Each is now
`optional(string)` (null when unset) and falls back to the timeout default of the `azurerm`
resource this module replaced. A consumer that sets `var.timeouts` today keeps working
unchanged; only the *unset* attributes changed meaning.

Cited against `terraform-provider-azurerm@5782a75422c68a0d0804ac16d97dcaf3df5ee2fa` (v4.81.0):

| `azapi_resource` | AzureRM resource | Source | Create | Read | Update | Delete |
| --- | --- | --- | --- | --- | --- | --- |
| `this` | `azurerm_express_route_connection` | `express_route_connection_resource.go` L34-L39 | 30m | 5m | 30m | 30m |

The effective values are unchanged for this module -- the AzureRM defaults happened to be the
blanket ones -- but they are now sourced rather than assumed.

Passing `var.timeouts = null` still omits the `timeouts` block entirely, exactly as before.
