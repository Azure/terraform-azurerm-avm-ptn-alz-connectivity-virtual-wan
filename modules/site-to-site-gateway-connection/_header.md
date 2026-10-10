# Basic example

This submodule deploys an Azure site-to-site connection between site-to-site Gateway and remote gateway in the Virtual Hub

## Routing on existing connections

When `routing` is omitted, the module reads the existing connection and preserves
its writable ARM routing. A missing connection leaves routing absent so Azure
can apply its defaults. Explicit `routing` remains authoritative and does not
require this read. The read-only `vnetRoutes.bgpConnections` back-reference is
excluded from preserved routing; writable route tables, route maps and static
route settings are retained.

## The pre-shared key is now write-only — and rotation still produces a plan

This module previously used the AzureRM provider, where `shared_key` was an ordinary schema
field: it was written to Terraform state and printed in plan output.

It now uses the AzAPI provider and sends the key through the **write-only** `sensitive_body`
argument. The key is no longer persisted in state and no longer appears in plan output.
Measured on the test fixture, the key occurs **zero** times in `resource_changes` in
both the human-readable and JSON plan.

**Write-only does not mean undetectable.** AzAPI stores a SHA-256 of the write-only body in
Terraform *private* state and diffs the config against it, so changing a `shared_key` and
nothing else still plans `0 to add, 1 to change, 0 to destroy`, and applying it rotates the
key. Measured live on the test fixture: the identical config with the key left alone
plans `No changes`. **Rotating a key needs no extra input and no version marker.**

```hcl
vpn_links = [
  {
    name             = "link-1"
    vpn_site_link_id = module.vpn_site.resource_object["site"].links[0].id
    shared_key       = var.new_pre_shared_key # change it; the plan shows an update
  },
]
```

### This module does not expose `sensitive_body_version`

AzAPI's `sensitive_body_version` is a map of version markers, one per write-only body path,
offered as an alternative way to signal that a secret has changed. **This module does not accept
one, at either the per-link or the whole-resource level, and does not set one on the underlying
`azapi_resource`.** That is deliberate, and it is a deviation from the AVM AzAPI guidance
(`.github/skills/avm-tf-azapi/SKILL.md` L222, *"use `sensitive_body_version` to make changes
detectable without persisting secret values"*) rather than an omission.

Two inputs were removed on the migration branch **before release**, so no published version of
this module accepts either: a per-link `shared_key_version`, and a whole-resource
`var.sensitive_body_version`. The AzureRM module had no equivalent of either.

**The goal of the guidance is already met without it.** Detectability is what L222 asks for, and
leaving the version null is what delivers it: AzAPI keeps a SHA-256 of the write-only body in
private state *only while the version is null*, and diffs against it. Measured live — rotating a
key with no version plans `1 to change`; the identical rotation with a version set plans
`No changes`.

Setting a version does not add a check, it **replaces an automatic one with a manual one**, and
it opens two failure modes that have no equivalent in the null regime:

- **A version that is set and not bumped empties the link list.** Any later apply that changes
  something else on the connection sends `properties.vpnLinkConnections: []`, replacing the live
  links with nothing. Measured: `400 MissingLinkConnectionForVpnConnection`. Only ARM's
  minimum-one-link rule turned a silent child-collection deletion into a visible failure, and
  every static check had already passed, because the emptying happens inside the provider at
  apply time.
- **A version keyed on the secret itself is worse.** Versioning
  `properties.vpnLinkConnections[0].properties.sharedKey` — the intuitive thing to write — makes
  the provider strip every sibling property it was not told to keep, **including `name`**. With
  no identifier to match on, the merge replaces the entire live link list with that one stripped
  element. No staleness needed, and nothing warns you.

If you genuinely need per-path version control on this resource, set it on an `azapi_resource`
you manage yourself rather than through this module, and address **whole array elements**
(`properties.vpnLinkConnections[0]`), never the `sharedKey` leaf.

### Two other consequences of the same change

- **Terraform 1.11 or later is required**, for every consumer of this module, not only those
  that set a key: `sensitive_body` is a write-only attribute and an older CLI fails while
  loading the provider schema, at plan time.
- **`resource_object[*].link[*].shared_key` is now `null`.** Re-emitting the key from
  configuration would put the secret straight back into state through the output.

## Design notes

Rationale that used to live as comments in `main.tf` and `variables.tf`. It was moved here
because the AVM `transform` step (mapotf `reorder_attributes`) rewrites `variable` blocks and
`azapi_resource` bodies and **drops trailing comments** from them, and upstream CI blocks the PR
until the source matches the transform's output. Leading comments attached to an attribute do
survive, so the short pointer comments left at each site are stable.

### `sensitive_body_version` is deliberately unset

⭐ `sensitive_body_version` IS DELIBERATELY NOT SET on `azapi_resource.this`, AND NOT EXPOSED AS
AN INPUT. Not an oversight and not a default: the attribute is unreachable from this module, on
purpose. Leaving it null is what keeps AzAPI's own private-state SHA-256 of the write-only body
alive, which is the mechanism that detects a rotated key -- and it is the only regime in which
the link-list wipe described below cannot happen. Recorded as a deliberate deviation from
`.github/skills/avm-tf-azapi/SKILL.md` L222; see the removal note in `locals` in `main.tf`.

### Removed input: per-link `shared_key_version`

⭐ `shared_key_version` (option A) and its two validations were REMOVED from
`variable "vpn_site_connection"`. Both validations existed to police a rotation
mechanism that is unnecessary and unsafe: AzAPI already detects a `shared_key` change on its own
via a private-state hash, and setting any version turns that detection OFF and makes the next
unrelated apply wipe `vpnLinkConnections`. Measured; see the removal note in `main.tf`.
The attribute was never released (added on the migration branch after v0.17.2), so nothing in the
wild sets it, and Terraform rejects an unknown object attribute with a clear error if anything
does.

### Per-resource timeout defaults

`var.timeouts` keeps its published shape, but its four attributes no longer carry a blanket
`"30m"`/`"5m"` default. Each is now `optional(string)` (null when unset) and falls back, per
resource, to the default of the `azurerm` resource this module replaced. The fallbacks and their
source lines are in `local.timeouts` in `main.tf`, cited against
`terraform-provider-azurerm@5782a75422c68a0d0804ac16d97dcaf3df5ee2fa` (v4.81.0). A consumer that
sets `var.timeouts` today keeps working unchanged; only the *unset* attributes changed meaning.

| `azapi_resource` | AzureRM resource | Source | Create | Read | Update | Delete |
| --- | --- | --- | --- | --- | --- | --- |
| `this` | `azurerm_vpn_gateway_connection` | `vpn_gateway_connection_resource.go` L38-L43 | 30m | 5m | 30m | 30m |

The effective values are unchanged for this module -- the AzureRM defaults happened to be the
blanket ones -- but they are now sourced rather than assumed. Passing `var.timeouts = null`
still omits the `timeouts` block entirely, exactly as before.
