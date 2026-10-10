# Upgrade guide: moving this module from AzureRM to AzAPI

This guide covers the upgrade to **v0.19.0**. This release replaces every `hashicorp/azurerm` resource this module declares with `Azure/azapi`
equivalents. The intended upgrade preserves your Virtual WAN, hubs, gateways, connections,
VPN sites and firewall through `moved` blocks. Confirm that preservation in the plan and ARM readback;
the presence of a move block alone is not proof.

Plan with Terraform's default refresh. Never use `-refresh=false`; the
[Known limitations](#known-limitations) section explains why. Stop if the plan shows a destroy or
replacement of a Virtual WAN object. Do not approve it.

## Draft child-module pins

The draft uses immutable commits from the existing `Git-PrinceNagar` forks until
the child modules have compatible registry releases:

| Child | Commit |
|---|---|
| Firewall policy | `8a1086ea84efd6db650d4c7cdb54414175f21587` |
| DNS resolver | `15f11c1019fcf0d81eb30dfd305a37a99b86d2a5` |
| DDoS protection plan | `643795612a4f2147b14e475be65918036601b736` |
| Public IP address | `38014e6831db544cad1105e33b9f4bfebcb36dab` |
| Bastion host | `27407b87ebfc7f8da03babc0b31f014bc253707d` |

The Bastion child pins the same Public IP commit. These updates retain the
inputs and output attributes consumed by this wrapper. They include DDoS
role-assignment condition clearing with JSON nulls, DNS Dynamic endpoints that
leave address assignment to Azure without a list lookup, and Public IP
`ignore_body_changes` handling that is no longer lifecycle-ignored. Bastion's
zone documentation and convergence checker are also updated. Use the child
upgrade guides for their limitations; child-level live checks do not establish
a full vWAN upgrade at this combined revision.

## If you use the ALZ Landing Zones Accelerator

Use a compatible Accelerator starter and verify the generated module pin and `providers` map.
The starter owns both, but a version bump alone does not prove that your exact configuration
has been tested. Re-plan with normal refresh, require no unintended destroys or replacements,
and review all ARM writes against the existing configuration before approving apply.

> ⚠️ **Starter releases up to and including v17.6.0 pass only `azurerm`.** If yours is one of them,
> open `main.connectivity.virtual.wan.tf` in your generated root and replace the `providers` map in
> the `module "virtual_wan"` call by hand before you plan. Without it, every resource lands in the
> wrong subscription and the upgrade plans as a full replacement:
>
> ```hcl
> providers = {
>   azapi = azapi.connectivity
> }
> ```
>
> Remove the `azurerm` line. This release declares no `azurerm` provider, so Terraform reports
> `Reference to undefined provider` if you keep it. Keep the root `azurerm` provider blocks, because
> other starter modules still use them.

## If you call this module directly

### Upgrading an existing repository example

The examples now pin `Azure/avm-res-resources-resourcegroup/azurerm` to `0.4.0`,
whose implementation uses AzAPI, rather than the AzureRM-based `0.2.0`.
The registry suffix is unchanged. Module labels, instance keys, names, tags and
`resource_id` references stay the same. The network-connection example's
virtualnetwork `0.22.2` dependency already uses AzAPI and is unchanged.

The full-multi-region example still configures AzureRM for the remote
Accelerator config-templating utility's `azurerm_client_config` data source.
That utility renders configuration; it does not provision the vWAN resources.
Do not remove the example's AzureRM provider until that upstream utility has
an AzAPI-compatible release. The other examples' resolved graphs contain no
AzureRM dependency.

The resource-group dependency ships a move from `azurerm_resource_group.this`
to `azapi_resource.this` within each existing module instance. If you have
deployed an older example, back up its state, run `terraform init -upgrade` and
plan with normal refresh. Verify the resource-group moves and require no
unintended destroys or replacements before approving a saved plan. Do not
delete the existing resource groups or remove their state to adopt the new
dependency. Local interface tests and validation are not a live upgrade test
of an existing example estate.

### Before you start

1. **Back up your state file and know how to restore it.** The upgrade is one plan and one apply; an
   interrupted apply needs manual repair from the pre-apply state.
2. **Read your child objects back from ARM first.** Compare the counts for `vpnConnections`,
   `natRules` and `expressRouteConnections` afterwards. A plan does not prove that a child survived.
3. **Apply a saved, reviewed plan**, and never re-plan between review and apply.

### 1. You must be on v0.12.0 or later

The supported starting point is **`v0.12.0` or later**. That release introduced
`modules/virtual-wan/` and its eight `moved` blocks, which this release's moves build on.

If you are **below v0.12.0**, upgrade in two steps. First move to **v0.17.2**, the final
AzureRM release. Apply it, confirm `No changes.`, then run this upgrade as a separate change.
Do not combine the hops; a `moved` block cannot cross resource types.

v0.17.2 and v0.18.0 are both direct starting points. The same `moved` blocks apply to both. If you
use the v0.18.0 `ignore_body_changes` keys `virtual_hubs_firewalls`,
`virtual_hubs_firewalls_diagnostic_settings` or `virtual_hubs_route_maps`, you can keep them. This
release accepts them as deprecated aliases and merges them into the new keys.

### 2. Raise your Terraform floor to 1.11

`modules/site-to-site-gateway-connection` declares `required_version = "~> 1.11"`. It sends the
per-link pre-shared key through AzAPI's write-only `sensitive_body`, and write-only attributes do not
exist before Terraform 1.11, so a 1.10 CLI fails while loading the provider schema at plan time.
**The floor binds every caller, whether or not you set a key.**

### 3. Pass the required `azapi` provider

Resource placement used to come from the `azurerm` provider you passed. It now comes from the
`azapi` provider the module receives, and a call that omits it silently inherits your root's default
`azapi` provider. Add the line before you plan:

```hcl
module "virtual_wan" {
  source  = "Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm"
  version = "0.19.0"
  # ... your existing inputs, unchanged

  providers = {
    azapi = azapi.connectivity # REQUIRED
  }
}
```

The module no longer declares an `azurerm` provider. Remove `azurerm` from the `providers` map;
Terraform reports `Reference to undefined provider` if you keep it.

If you have no `azapi` provider for that subscription yet, declare one with
`alias = "connectivity"` and `subscription_id = var.subscription_ids["connectivity"]`.

### 4. Bump the version and plan

```bash
terraform init -upgrade
terraform plan -out=tfplan      # a NORMAL refresh. Never -refresh=false.
```

**That is the whole upgrade.** You write nothing else: no `import` blocks, no addresses to look up,
no artifact, nothing to clean up afterwards. Sixteen in-module `moved` blocks do the state move.

### 5. Review the plan and apply

DNS resolver parent scopes must remain known during planning. The pattern references managed
subnet outputs for both default and custom endpoints instead of placing a broad `depends_on`
on the DNS module. This preserves subnet creation ordering without deferring the child's
provider-context data source. Subnet names not managed by the sidecar module are passed through
unchanged and must refer to existing subnets.

An omitted or explicitly null `allow_branch_to_branch_traffic` resolves to `true`, matching the
AzureRM default. An explicit `false` remains `false`.

`virtual_wan_settings.virtual_wan.office365_local_breakout_category` also keeps
the AzureRM default `None` and supports `Optimize`, `OptimizeAndAllow` and `All`.
The Virtual WAN writer sends the selected value rather than silently ignoring it.
Its embedded AzAPI schema validation is disabled because the schema marks this
writable property read-only. The exception affects the whole WAN body, not other
resources. See [migration deviations](MIGRATION-DEVIATIONS.md). If you supply an
existing `virtual_wan.id`, this module does not manage that WAN's category.

An omitted connection `routing` preserves the configuration read from the existing matching
connection, including custom routes and returned legacy transit flags. Explicit routing takes
precedence; new connections continue to use Azure defaults. These routing reads require list
access to hub connections. The connection request excludes the read-only
`routingConfiguration.vnetRoutes.bgpConnections` back-reference returned when a hub BGP
connection references it. Static routes and their configuration, associated and propagated
tables, and inbound/outbound route maps remain intact. Embedded schema validation stays enabled.
This omission is covered by mocked plans; a refreshed upgrade plan on an existing BGP/NVA
estate is still required to confirm the live migration.

The DNS child leaves Dynamic inbound IP assignment to Azure;
it does not list existing endpoints or resend a server-assigned IP in its request body.
A Dynamic endpoint adopted from AzureRM can require one in-place update to remove the
previously recorded IP from the request body. That adoption path has not been tested live.

These changes alone do not prove a migration plan safe. Compare the evaluated routing and
Dynamic inbound endpoint IPs against the existing ARM configuration before and after apply.
Do not ignore the entire endpoint IP configuration list to conceal a server-assigned IP diff,
as that would also hide subnet and Static IP changes.

```bash
terraform show -json tfplan > tfplan.json
terraform apply tfplan
```

**Zero destroys and replacements are necessary, not sufficient.** Review every in-place ARM body
change and existing-resource writer. Confirm route-table association and propagation, static routes,
transit settings, endpoint IP allocation and assigned IPs, firewall-policy DNS servers, and enabled
features against the captured baseline. An unknown value is a deferred verification, not a match.

The plan adds day-2 writers that had no AzureRM counterpart. They do not create Azure resources to
replace existing ones. The reference upgrades below had zero destroys and zero replacements. Each
one re-planned to `No changes.` after apply:

| from | estate | plan |
|---|---|---|
| v0.16.1 | direct call to `modules/virtual-wan` | `4 to add, 7 to change, 0 to destroy` |
| v0.16.1 | full Accelerator estate | `14 to add, 206 to change, 0 to destroy` |
| v0.17.2 | full Accelerator estate | `44 to add, 246 to change, 0 to destroy` |
| v0.17.2 | root module with every optional feature (two hubs, firewalls, VPN, ExpressRoute gateway, P2S, BGP, routing intent, DNS resolver, Bastion, sidecar networks) | `13 to add, 29 to change, 0 to destroy` |
| v0.18.0 | root module with customer firewall public IPs and a firewall policy in a different region | `6 to add, 8 to change, 0 to destroy` |

The adds include a state-only `terraform_data.public_ip_mode` marker per firewall.

Three plan shapes have known causes:

| what you see | cause | what to do |
|---|---|---|
| `must be replaced` with `+ location = "…" # forces replacement` | you planned with `-refresh=false` | re-plan with a normal refresh |
| `must be replaced` with `replace_paths = [["parent_id"]]` | wrong provider scope, or a deferred data source made the scope unknown | verify the `azapi` provider map and dependency graph; do not assume one cause |
| a `destroy` with no matching create | an address no `moved` block covers | **stop and report it**. The 16 moves should cover every resource. |

### 6. After the apply

1. Read the resources and their children back from ARM and compare functional properties with
   your pre-apply readback, including values that were unknown in the plan.
2. Re-plan **with a normal refresh** and confirm `No changes.`

## Breaking changes

### 1. The `azapi` provider must be passed to the module call

See [step 3](#3-pass-the-required-azapi-provider). Omitting it points every resource
at the wrong subscription and plans a replace of all of them, with
`replace_paths = [["parent_id"]]`. The `moved` blocks do not protect you from this.

### 2. The `resource` output of `modules/firewall` and `modules/route-map`

**Only affects callers who instantiate those submodules directly.** If you consume the root module,
your output surface is unchanged.

The output keeps its name and cardinality, but each element is now an `azapi_resource` object, so the
AzureRM-specific members are gone: `sku_name`, `sku_tier`, `firewall_policy_id`, `virtual_hub` (and
its nested members), `ip_configuration`, `management_ip_configuration`, `dns_servers`,
`dns_proxy_enabled`, `private_ip_ranges`, `threat_intel_mode`, `zones`, `resource_group_name`.
`id`, `name`, `location` and `tags` remain.

| you used to read | read this instead |
|---|---|
| `resource[key].virtual_hub[0].private_ip_address` | `private_ip_address[key]` |
| `resource[key].virtual_hub[0].public_ip_addresses` | `public_ip_addresses[key]` |
| `resource[key].id` / `.name` | `resource_ids[key]` / `resource_names[key]` |
| anything else | `resource_object[key]`, or `resource[key].body.properties.*` |

`resource_object` is the intended replacement. It is an explicitly projected object whose shape this
module owns. The computed `output` attribute is **empty** (`response_export_values = []`), so do not
read it to recover the lost members. Both `resource` outputs go in the next major.

### 3. Output element types change on four more submodules

`modules/site-to-site-vpn-site`, `modules/virtual-network-connection`,
`modules/site-to-site-gateway-connection` and `modules/expressroute-gateway-connection` keep the same
container shape, order and cardinality for their `resource` output, but each element is now an
`azapi_resource`. `.id`, `.name` and `resource_id` are unchanged; per-attribute reads such as
`.routing_weight` or `.address_cidrs` no longer resolve. `shared_key` is deliberately no longer
returned by the gateway-connection output, because re-emitting it would put the secret back in state.

## Behaviour that changes after the upgrade

- **Tags** are written by one `Microsoft.Resources/tags` PUT per gateway, hub, firewall and P2S
  gateway, which **replaces the whole tag set**. Tags applied out of band are removed at upgrade,
  and **tag drift is never reported in a plan** because the tag writer does not read from ARM.
- The **perpetual `vpn_link.shared_key` diff disappears** for connections this module manages; one
  you declare outside this module is unaffected and keeps diffing.
- **Do not set `sensitive_body_version`.** The module neither accepts nor sets it; key rotation is
  detected automatically, and a stale version was measured to wipe every link on a connection.
- **`routing.inbound_route_map_id` / `routing.outbound_route_map_id` stay silently inert.** The
  module always dropped them. Wiring them up would change live infrastructure on your first apply.
- **`express_route_gateway_bypass_enabled` stays inert** and still sends an explicit `false` on
  create, exactly as AzureRM did.
- **`sa_data_size_kb` / `sa_lifetime_sec`**: a non-numeric string now fails with a `tonumber()`
  error instead of a provider schema error.
- **`vpn_site_link_id` and per-link `bgp_enabled` are no longer ForceNew**; what ARM does when you
  change them in place is untested.
- **`terraform apply` can return while ARM is still working.** A tags-only change completes in
  seconds and can leave the resource `Updating` for minutes.
- **Hub tags are written after the firewall policy writes.** A hub tag write puts the hub in
  `Updating` for about four minutes. A firewall policy write in the same window fails with
  `FirewallPolicyUpdateFailed` ("faulted referenced firewalls"), because the firewall cannot update
  while its hub is not `Succeeded`. The module now orders the hub tag writes after the firewall
  policies it creates, so a tag change on hubs and policies in one apply succeeds.
- **Per-path drift suppression is unavailable on the day-2 update writers** (the provider offers no
  such argument there); the only lever is the whole resource.
- **A pre-shared key passed through a root variable still appears in plan JSON** at the variable
  level. This is unchanged by the upgrade.

## Customer-provided firewall public IPs

A firewall whose `ip_configurations` map is non-empty uses the caller-owned public IPs and is written by
`modules/firewall-customer-ip`; a firewall with an empty map keeps the managed public IPs and the writers above.
The mode is recorded in state and cannot be changed by a normal apply: moving an existing firewall between managed
and customer modes fails with an error and needs a separately planned migration. Customer mode reads the firewall
inventory of the subscription, so the identity needs subscription-scoped read access on `Microsoft.Network/azureFirewalls`.

## Other changes in v0.19.0

- Root `retry` and `timeouts` now reach `module.virtual_wan` and all of its resources, including
  both firewall modes. An attribute you leave unset arrives as null, and each receiving module keeps
  its own default, so nothing changes if you set neither. The firewall keeps 90m for create, update
  and delete and 5m for read. The firewall policies do not receive root `retry`. They keep the
  default of the firewall policy module.
- A labelled `virtual_hub_route_table` with no `routes` now plans. Before this fix it failed with
  `Cannot use a null value in for_each`. The defect has existed since v0.16.1. Configurations that
  worked before see no change.
- A root module with both firewall modes (managed and customer public IPs) now returns its firewall
  outputs. Before this fix the outputs failed with an inconsistent conditional result type.

## How to check the upgrade yourself

1. Deploy the version you run today (`>= v0.12.0`, ideally `v0.17.2`) from your own configuration or from
   `examples/minimal-config` into a test subscription, and keep the state.
2. Change only `version` and the `providers` map, then run `terraform init -upgrade` and
   `terraform plan -out=tfplan` with a normal refresh. Expect `0 to destroy`, nothing replaced, and a
   `has moved to` line for each of your Virtual WAN objects.
3. Save the live objects before and after with `az rest --method get` on each object ID (same `api-version`) and
   compare them leaf by leaf; `etag` and `provisioningState` are expected to differ.
4. Apply the saved plan, then re-plan and expect `No changes.`
5. The module's `terraform test` suites (`tests/unit`, `modules/*/tests`) cover input validation, the firewall
   customer-IP mode and the output shapes without any Azure access.

### Credential-free repair regressions

From the repository root, initialize the root tests with
`terraform init -backend=false -test-directory=tests/unit`, then run
`avm test unit`. The Office365 forwarding check also inspects the evaluated
child-resource request rather than only the root local:

```powershell
.\tests\unit\Test-Office365RootForwarding.ps1 -LogPath "$env:TEMP\office365-root.jsonl"
.\tests\unit\Test-ExampleProviderDependencies.ps1 -OutputDirectory "$env:TEMP\vwan-example-checks"
```

The example check initializes and validates every example, rejects unexpected
AzureRM dependencies in the resolved provider graph, and runs plans with mocked
Azure data and telemetry disabled. It allows the documented Accelerator
client-config dependency only in full-multi-region. These checks perform no
Azure writes and do not verify live state
moves, ARM category persistence, or preservation of an existing WAN's children.

## What the evidence behind this guide is

Three kinds of evidence exist and they are not interchangeable:

- **Live upgrades.** Upgrades from v0.16.1, v0.17.2 and v0.18.0 on live Azure. Each run had a plan,
  an apply, a clean re-plan and a leaf-by-leaf comparison of the objects read back from ARM. The
  v0.17.2 run with every optional feature also checked traffic after the upgrade: ping between spokes
  through the hub firewall, DNS through both resolver inbound endpoints, and a Bastion connection. It
  then ran a tag change on all objects and a full destroy. The five child modules were consumed from
  pinned builds in those runs, not from published registry versions.
- **Mocked unit tests (`terraform test`).** They check input validation, the firewall customer-IP mode, output shapes
  and stable resource identity. They do **not** prove the AzureRM to AzAPI state move: mock providers cannot simulate
  a move across providers, so `tests/unit/firewall_upgrade.tftest.hcl` exercises only the AzAPI code.
- **Registry-pinned children.** The release pins the five child modules to their registry versions.
  Those versions contain the same code as the tested builds. A plan against the registry versions
  must show no difference from the tested builds.

## Known limitations

- **Do not use `-refresh=false` for the upgrade plan.** This is a hard rule, not a caution. Without
  refresh, the moved state carries a null `location` and an unknown `parent_id`. The plan then
  reports replacements that are not real. The measured result was
  `5 to add, 0 to change, 2 to destroy`, with
  `+ location = "eastus" # forces replacement` on an object that a normal refresh plans as an
  in-place update. The module's ForceNew preconditions do **not** catch it, because `ignore_changes`
  does not apply to a create. There is no flag, input or version that makes it safe on this upgrade.
- **The move records the newest API version embedded in the provider**, not one your configuration
  names. An ARM resource ID carries no API version, so the provider picks the newest from its own
  index. In sovereign clouds that version may not exist, and the post-move read can fail. **This
  path has never been measured in a sovereign cloud.** Read the recorded version with
  `terraform state show <address>`; nothing in a plan will remind you. This is the limitation
  tracked in [azapi#1227](https://github.com/Azure/terraform-provider-azapi/issues/1227).
- **The create-only writer keeps its create-time API version. Changing it is not supported in this
  release.**
- **Live coverage of the `moved` blocks.** Exercised on live ARM during validation: the Virtual
  WAN, hub, firewall, firewall policy, VPN gateway, VPN site and connection, ExpressRoute gateway, hub virtual
  network connection, routing intent, BGP connection, Point-to-Site gateway and server configuration, the
  module's own resource group, the hub route table, the firewall diagnostic setting, the Bastion host and its
  public IP, and the DNS resolver with its endpoints, ruleset, rules and virtual network link. The DDoS plan
  child module was exercised on its own. **Not exercised live:** the ExpressRoute gateway connection and the
  generated private DNS zone virtual network link moves. If your estate has any of those, read the plan before
  you apply and treat a `must be replaced` as a defect in the release.
- **ExpressRoute connections have never been exercised against live ARM.** No provisioned circuit was
  available. The ExpressRoute gateway itself was exercised.
- **`properties.natRules` on VPN gateways is unmeasured** beyond plan level.
- **Other parallel writes can still fail a firewall policy update.** The module orders its hub tag
  writes after the firewall policies. It does not order other hub writes, such as a hub property change,
  against a policy write in the same apply. A change to a base policy that you own outside this module
  also updates the child policies and their firewalls, and the module cannot order that. If an apply fails
  with `FirewallPolicyUpdateFailed` and "faulted referenced firewalls", wait until the hub is `Succeeded`
  and apply again. A policy left `Failed` recovers with one more apply.
- **v0.17.2 cannot associate a module-created connection with a custom route table from the same
  module.** This is a dependency cycle in v0.17.2. If you worked around it with propagation labels, the
  upgrade keeps your labels unchanged.
- **Destroy ordering with literal IDs.** If a BGP connection refers to its hub virtual network connection by a
  literal ID string rather than a Terraform reference, Terraform has no dependency edge and may delete both in
  parallel; Azure then rejects the connection delete with `HubVnetConnectionInUseByHubBgpConnection`. Re-running
  the destroy after the BGP connection is gone succeeds. Reference the connection through a resource attribute
  or destroy the BGP connection first.
- **Rollback from an interrupted apply is not an established procedure.** A partial apply leaves
  state split and needing manual repair.

A migrated estate can still be destroyed through the module: measured, all-`delete` plan, no
dependency or ordering errors, nothing left behind. Deviations from the AVM specification are
recorded in [`MIGRATION-DEVIATIONS.md`](MIGRATION-DEVIATIONS.md).
