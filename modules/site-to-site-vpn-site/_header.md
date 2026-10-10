# Basic example

This submodule deploys an Azure site-to-site Gateway site in the Virtual Hub

## Design notes

### Per-resource timeout defaults

`var.timeouts` keeps its published shape -- same variable name, same four attributes, same
types -- but its attributes no longer carry a blanket `"30m"`/`"5m"` default. Each is now
`optional(string)` (null when unset) and falls back, per resource, to the timeout default of the
`azurerm` resource this module replaced. A consumer that sets `var.timeouts` today keeps working
unchanged; only the *unset* attributes changed meaning.

The fallbacks live in `local.timeouts` in `main.tf` and are cited against
`terraform-provider-azurerm@5782a75422c68a0d0804ac16d97dcaf3df5ee2fa` (v4.81.0):

| `azapi_resource` | AzureRM resource | Source | Create | Read | Update | Delete |
| --- | --- | --- | --- | --- | --- | --- |
| `this` | `azurerm_vpn_site` | `vpn_site_resource.go` L39-L44 | 30m | 5m | 30m | 30m |

Passing `var.timeouts = null` still omits the `timeouts` block entirely, exactly as before.
