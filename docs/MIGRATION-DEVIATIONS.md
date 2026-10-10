# Migration deviations

Deviations from the migration guidance in
[`.github/skills/avm-tf-migration/SKILL.md`](../.github/skills/avm-tf-migration/SKILL.md).

## `removed` + `import` is not supported in the AzAPI migration release

The module ships in-module `moved` blocks, which Terraform resolves before `removed` and `import`
blocks, so a consumer-written removed+import artifact has no effect.

## Root `retry`/`timeouts` defaults moved into locals

TFFR7 requires `retry` and `timeouts` to cascade unchanged. The published root variables carried
non-null defaults (four retry regexes, 60m/5m/60m/60m), which would have overwritten the Virtual
WAN submodule's per-resource defaults (for example 90m for a firewall) on every plan. The defaults
now live in `locals.retry.tf` and `locals.timeouts.tf`; the variables keep their name, shape and
`default = {}` but their attributes are `optional(...)` without a default. The only visible change
is that a value you set now also reaches the Virtual WAN resources.

## `ignore_body_changes` keys from `v0.18.0` kept as deprecated aliases

The published baseline `0.17.2` has no root `ignore_body_changes` input, so baseline callers are unaffected.
Release `v0.18.0` introduced it with three
top-level keys. Release `v0.19.0` reshapes it to mirror the submodule and keeps those three keys, which are
accepted and merged into the new ones (see `locals.ignore_body_changes.tf`).

## Virtual WAN Office365 schema validation exception

`office365_local_breakout_category` remains supported with the AzureRM default
`None` and allowed values `None`, `Optimize`, `OptimizeAndAllow` and `All`.
`modules/virtual-wan/main.tf` sends it as
`properties.office365LocalBreakoutCategory` on the existing Virtual WAN writer.
Callers supplying `virtual_wan_id` reference an externally managed WAN; this
module does not write that WAN or change its category.

AzureRM v4.81.0 sets the field on create, reads it into state, and updates it by
merging the changed value into the existing ARM response. Its implementation is
[virtual_wan_resource.go](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.81.0/internal/services/network/virtual_wan_resource.go).
AzAPI's embedded schema instead marks the property read-only for API 2025-07-01.
Omitting it while accepting the input silently loses supported behavior.

The historical `o365-readonly/RESULT.md` lab record, amended on 2026-09-26,
reports a hubless WAN PUT with `OptimizeAndAllow` followed by two GETs returning
`Succeeded` and the same value. It also records the AzAPI 2.12.0 schema rejection
and a successful local plan with `schema_validation_enabled = false`.
That measurement supports the exception; it is not a live test of this repair
revision, nor proof of every category or an upgrade with hubs attached.

An isolated lab run at vWAN commit
`7be2e258283ee454669ef43b5e9f5a983b480eb7` created a Standard WAN with
`Optimize` and one attached hub in `centralindia`. ARM readback confirmed the
category and the attached hub's `Succeeded` state; the refreshed replan showed
`No changes`, and all seven managed objects were destroyed afterwards. This
does not establish category updates on an existing WAN, every category, or
preservation of gateways, connections and other child collections during an
upgrade. It is not a full vWAN or Accelerator end-to-end test.

Only `azapi_resource.virtual_wan` sets `schema_validation_enabled = false`.
The flag is resource-wide, so the entire Virtual WAN request body loses embedded
schema validation. Input enum validation remains, and other resources are not
changed. The body is still mutable so category changes can reach ARM; no new
`ignore_changes`, replacement trigger or state address is introduced.
Existing-state upgrades still require a normal-refresh plan, review of every ARM
write and child-collection readback under the upgrade guide. Local mocked tests
cannot establish that an existing estate's full PUT preserves all child objects.

## Existing connection routing: read-only BGP back-reference

Commit `c889b17007fe314a9b17311017c262d79235998a` restored AzureRM's
Optional/Computed routing preservation when callers omit `routing`. It copied
the matching connection's entire ARM `routingConfiguration` into the PUT body,
including `vnetRoutes.bgpConnections` when a hub BGP connection references it.
That introduced a regression: the 2025-05-01 connection schema marks that
back-reference read-only, so AzAPI rejects the request before an applicable
upgrade plan can be produced.

Accelerator attempt 4 reproduced the rejection with Terraform 1.16.5, AzAPI
2.13.0 and vWAN `872abe5a21594dd0750dab8de26b89da366b194c`, upgrading
Starter v17.6.0 / vWAN 0.17.2. Its baseline connection used `defaultRouteTable`,
propagated `["none"]` to `noneRouteTable`, and retained static-route settings
`Contains` / `true`, with no static routes. A sidecar BGP connection was present.
The partial plan's 23 add / 26 change / 0 destroy is not an applicable or
successful migration plan.

The repair strips only `routingConfiguration.vnetRoutes.bgpConnections`.
The current [ARM REST schema](https://github.com/Azure/azure-rest-api-specs/blob/88e2199d770d74f3061a162824185fd6894cb7d7/specification/network/resource-manager/Microsoft.Network/Network/stable/2025-05-01/virtualWan.json)
and its referenced types identify no other read-only field inside
`routingConfiguration`. Static routes and their configuration, associated and
propagated tables, route maps, and returned legacy transit flags remain
preserved. Explicit `routing` still wins. Request schema validation remains
enabled; this is not an Office365-style exception or a blanket routing ignore.
Consumer-supplied `ignore_body_changes` remains unchanged.

The regression fixture reproduced the same embedded-schema rejection before
the repair. Mocked plans now cover the Accelerator baseline shape, custom
routing with and without BGP references, absent/null/BGP-only `vnetRoutes`,
explicit routing, fresh connections and unrelated remote VNets. These tests
do not prove a refreshed upgrade or an apply on the held Accelerator estate.
That live re-plan and routing readback remain release gates.

Historical evidence explains the detection gap: the earlier combined
Accelerator leg A at `7041481` exercised both BGP and hub connections and
re-planned clean, but preceded `c889b17`. No recorded post-`c889b17` live lane
included a BGP connection, and the previous mock contained only writable
routing. The successful earlier lane therefore did not validate this later
carry-over change.

The related body-builder audit found no equivalent raw ARM routing copy in
ER connections or hub route tables: those requests are constructed from
configured inputs. The hub has a constructed genesis body and an AzAPI
merge-update writer, not a copied list response in its declared body. That
provider-managed merge path is distinct and is not live-validated by this
regression. This audit does not resolve the separately documented hazards
around undeclared out-of-band fields on other full PUT writers.

## P2S omitted routing on a full gateway PUT

The held Accelerator attempt 5 candidate plan at Starter `62e3836` /
vWAN `fed7fc7` had 23 additions, 27 changes, no destroys and no replacements.
Its frozen plan JSON SHA256 is
`591110BECEFEF661869227443532D44D876F800640F0CA0CC08508EF230524F3`.
The plan was not applied. The baseline ARM GET showed the P2S connection
configuration associated with `defaultRouteTable` and propagated to
`noneRouteTable` with label `none`, while the candidate's full P2S gateway
body omitted `routingConfiguration`. Since `p2SConnectionConfigurations`
is an inline property in the gateway's full PUT, and there is no equivalent
isolated ARM readback proving omission is merge-exempt, plan counts do not
establish that the routing survives.

The module now reads only the existing P2S gateway's connection
configurations. If the matching named configuration has ARM routing and the
caller has no routing input (the module does not expose one), that routing
is carried into the PUT; a missing gateway or configuration leaves it absent
and uses Azure defaults. The P2S 2025-07-01 schema also marks
`routingConfiguration.vnetRoutes.bgpConnections` read-only, so that one
response-only field is filtered while associated/propagated tables, route
maps, static routes, and static-route settings are retained. A mocked
regression test covers the attempt-5 table association and propagation shape,
the static-route configuration, and removal of the BGP back-reference. It
does not prove the live attempt-5 upgrade; the retained estate must be
re-planned and reviewed before apply.

The VPN connection body also omits caller-unconfigured routing, but historical
R4-clean evidence at `C:\Bugs\AzApi Config\.scratch\validation\tier3\step-e\RESULT.md`
records a write by the VPN connection resource itself with routing omitted,
followed by ARM readback showing its associated route table, propagated IDs
and labels unchanged. That distinct resource-specific measurement supports
omission for that historical default-route fixture; it is not an after-write
result for attempt 5's `noneRouteTable` configuration and does not establish
preservation for the current full request body. The decision to leave this
writer unchanged has therefore been superseded by explicit preservation.

The VPN connection now reads only `properties.routingConfiguration` when the
caller omits `routing`, using the same resource type/API version as its writer.
If present, that routing is carried into the PUT with only the 2025-07-01
schema's read-only `vnetRoutes.bgpConnections` removed. A 404 or absent routing
leaves the field omitted. Explicit caller routing keeps its existing request
shape and precedence, including the documented route-map input behavior.
Regression tests cover the attempt-5 default association and `none` propagation,
additional writable route maps/static routes with a BGP back-reference, a fresh
connection, and explicit routing. Before the fix, the new writable-routing
assertion failed because the body had no routing; afterwards it passed.

Earlier null-optionals coverage asserted routing was absent for a fresh
connection and did not supply existing non-default ARM routing. Historical
step-E readback covered default propagation, not attempt 5's `none` propagation.
Those missing scenarios explain why the preservation gap was not caught before
the held full-body review. Neither mocked tests nor the held candidate's
zero-destroy plan prove a completed live migration. The P2S-only repair at
`0c28b816b5b3b1530506744b477b13472700416a` has a separate plan-only routing match
in `evidence-routing-fix-0c28`; both routing fixes still require a same-state
candidate replan and review before any apply.

## Full-multi-region example's Accelerator client-config dependency

The resource-group calls in all six affected examples use the AzAPI
implementation in resourcegroup `0.4.0`. The full-multi-region example still
needs AzureRM for its remote Accelerator config-templating utility, not for
resource-group or vWAN provisioning. Removing that provider would break the
utility's `azurerm_client_config` read.

The inspected Accelerator revision is
[`8efcb61c4dc856c7a7c0f227d0aaf5fe39d28661`](https://github.com/Azure/alz-terraform-accelerator/tree/8efcb61c4dc856c7a7c0f227d0aaf5fe39d28661/templates/platform_landing_zone/modules/config-templating).
Its `data.tf` reads the client configuration, and `locals.config.tf` uses the
tenant ID when the root management-group input is empty. AzAPI can provide that
value, so this is a residual upstream dependency, not an AzAPI capability
exception. The example retains its existing remote source rather than copying
or modifying the upstream utility.

The example provider-graph regression permits AzureRM declarations only at the
full-multi-region root and that utility. No global AzureRM-disallowed lint
suppression remains. Remove this example-only provider configuration after the
upstream utility has a compatible AzAPI implementation and its rendered outputs
and resolved graph have been checked. The remote source still tracks `main`;
the inspected revision is evidence, not a pin or a promise about future heads.
