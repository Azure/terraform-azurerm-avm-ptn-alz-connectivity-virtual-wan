####################################################################################################
# Microsoft.Network/virtualHubs — candidate-1 TWO-WRITER shape
#
#   azapi_resource        "this"  -> CREATE-ONLY full writer (genesis body, then silenced)
#   azapi_update_resource "this"  -> DAY-2 merge writer (GET, merge, PUT)
#
# Read `docs/MIGRATION-DEVIATIONS.md` before changing anything here.
# Every clause below is present because something was measured, not as a style preference.
#
# ══════════════════════════════════════════════════════════════════════════════════════════════
# 🔴 WHY THE FULL WRITER IS CREATE-ONLY — the child collections this module does NOT declare
# ══════════════════════════════════════════════════════════════════════════════════════════════
#
# `Microsoft.Network/virtualHubs` owns child collections and back-references that OTHER modules,
# and often the CUSTOMER directly, create. A full PUT that omits them is NOT uniformly safe:
# ARM decides per property, inside the RP's own handler, and the outcome is NOT predictable from
# the property's shape (isolated per-property measurements on falsified the earlier shape-based predictions). `virtualHubs` alone shows BOTH outcomes.
#
# `VirtualHubProperties` at api-version 2025-07-01 has 22 keys, 5 read-only, so 17 writable.
# This module declares 6 of them (`addressPrefix`, `allowBranchToBranchTraffic`,
# `hubRoutingPreference`, `sku`, `virtualRouterAutoScaleConfiguration`, `virtualWan`).
# The remaining 11 are UNDECLARED and would be dropped by any full PUT built from this body:
#
#  | # | undeclared writable path                | status on an OMITTING full PUT                |
#  |---|-----------------------------------------|-----------------------------------------------|
#  | 1 | `properties.virtualHubRouteTableV2s`    | 🔴 **measured: deleted**                       |
#  | 2 | `properties.azureFirewall`              | measured: preserved                            |
#  | 3 | `properties.vpnGateway`                 | measured: preserved                            |
#  | 4 | `properties.expressRouteGateway`        | measured: preserved                            |
#  | 5 | `properties.p2SVpnGateway`              | ⚠️ UNMEASURED — hazardous under fail-closed    |
#  | 6 | `properties.securityPartnerProvider`    | ⚠️ UNMEASURED                                  |
#  | 7 | `properties.securityProviderName`       | ⚠️ UNMEASURED                                  |
#  | 8 | `properties.preferredRoutingGateway`    | ⚠️ UNMEASURED                                  |
#  | 9 | `properties.virtualRouterAsn`           | ⚠️ UNMEASURED                                  |
#  |10 | `properties.virtualRouterIps`           | ⚠️ UNMEASURED                                  |
#  |11 | `properties.routeTable`                 | ⚠️ UNMEASURED                                  |
#
# Provenance of each status — the registry is authoritative, this comment is a convenience copy:
#
#   Rows 1 and 2 are REGISTRY ROWS. the child-collection preflight registry, `types["microsoft.network/virtualhubs"]`, api-version 2025-07-01,
#   generated. Row 1 `measured: "deleted"` — item C row 1: an `az rest` PUT of the hub
#   readback minus exactly `properties.virtualHubRouteTableV2s` took the child GET from 200 to
#   HTTP 404 and the hub back-reference from `[...]` to `[]`. Row 2 `measured:
#   "preserved"` — item C row 3, same hub, same procedure: the firewall survived AND kept its
#   `properties.virtualHub` back-reference; ARM treated the omission as "no change".
#
#   Rows 3 and 4 are NOT registry rows. They are the isolated measurements
#   (measured): case (a)
#   `virtualHubs.vpnGateway` and case (c) `virtualHubs.expressRouteGateway`, both preserved, both
#   re-run with `-target` so no gateway PUT existed in the apply. A survival measured in an apply
#   that also touches the writer of that property is NOT a measurement.
#
#   Rows 5-11 have never been measured. Under the fail-closed rule UNMEASURED is treated as
#   hazardous, and ticket 02 records them so nobody later mistakes silence for safety.
#
#   STRUCTURALLY SAFE, and deliberately absent from the table above: `hubRouteTables` (the type
#   `modules/virtual-wan` actually manages, via `azurerm_virtual_hub_route_table`) and
#   `hubVirtualNetworkConnections`. Neither has ANY member on `VirtualHubProperties`, so neither
#   can be dropped by omission from a hub PUT. See `_NOTE_hubRouteTables` in the registry — the
#   distinction between `routeTables` and `hubRouteTables` (current, safe)
#   is easy to get backwards.
#
# 🔴 THIS IS A REGRESSION RISK THE MODULE DID NOT PREVIOUSLY CARRY. `azurerm_virtual_hub`'s
# Update is GET-then-modify-then-PUT (`virtual_hub_resource.go` L262 `VirtualHubsGet`, L267
# `payload := existing.Model`, L300 `VirtualHubsCreateOrUpdateThenPoll`), and it mutates only
# five fields, each behind `if d.HasChange` (L276/L281/L285/L289/L292). Every other hub property
# rode along verbatim from the readback. That preservation was a property of the PROVIDER's
# update path, not of this module, and a plain `azapi_resource` full PUT removes it.
#
# 🔴 THEREFORE: do NOT remove `lifecycle.ignore_changes` below, and do NOT add a second full PUT
# against a live hub. The create-only full writer plus the merge writer is what replaces AzureRM's
# read-modify-write. `azapi_update_resource` GETs the live object and merges into it
# (`mergeObjectAtPath` MAP branch, `utils/json.go` L45-58 at azapi v2.12.0; the preservation is
# L52-53, `res[key] = value` for a key present in the LIVE object and absent from the new body),
# so an undeclared path is preserved whether or not the provider has ever heard of it. If the
# ignore list is incomplete the protection is not there, because `skip.CanSkipExternalRequest`
# (`internal/skip/skip.go` L14-55,
# called at `azapi_resource.go:826`) will do the full PUT of `state.body` for ANY non-`skip_on`
# field whose plan value differs from its state value.
#
# ══════════════════════════════════════════════════════════════════════════════════════════════
# Accepted costs of this shape, on the record and unchanged
# ══════════════════════════════════════════════════════════════════════════════════════════════
# (a) 🔴 the ignore list makes body drift PERMANENTLY INVISIBLE. See the ForceNew note on the
#     full writer below for the concrete consequence on this type.
# (b) 🔴 merge is additive — the day-2 writer CANNOT UN-SET a property. It also could not remove
#     a tag key, which was REG-1: under AzureRM, `tags.Expand` assigned the whole map, so deleting
#     a key from config deleted it in Azure. ✅ FIXED IN 0.19.0 — tags left the merge writer's
#     body and moved to `azapi_resource_action.tags` below, which PUTs at
#     `Microsoft.Resources/tags/default` and REPLACES the whole tag set. The rest of cost (b),
#     un-setting a non-tag property, still stands.
# (c) 🔴 `azapi_update_resource.Delete` is an EMPTY function — destroying the merge writer makes
#     no ARM call at all.
# (d) 🔴 plan-level evidence is nil; the steady-state gate's CHECK 4 annotates, it never proves.
####################################################################################################

# AzAPI addresses every resource by ARM resource ID, where AzureRM took a resource group NAME plus
# an implicit subscription from the provider block. This is a provider migration in place, so the
# module's public variable shape is preserved and the missing subscription segment is read from the
# provider once, here. Matches `modules/virtual-wan/main.tf` L1-5.
data "azapi_client_config" "current" {}

# ───────────────────────────────────────────────────────────────────────────── full writer ──────
# CREATE-ONLY. After genesis this address must never PUT again, so there is exactly ONE writer
# against a live hub and the partial-PUT hazard documented at the top of this file cannot occur
# through it. Everything that could drag it into an update is silenced below.
resource "azapi_resource" "this" {
  for_each = local.virtual_hubs

  location = each.value.location
  name     = each.value.name
  # `resource_group_name` was Required on `azurerm_virtual_hub` (`commonschema.ResourceGroupName()`,
  # L62), so a null was already a hard error before this migration; it still is, as a failed
  # interpolation. The public variable shape is unchanged.
  parent_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}/resourceGroups/${each.value.resource_group_name}"
  type      = var.resource_types.network_virtual_hubs
  body      = local.virtual_hub_bodies[each.key]
  # `ignore_body_changes` is offered for shape-consistency with the sibling modules. On THIS
  # module it is close to inert: `body` is already in `ignore_changes` below, so the full writer
  # does not act on body drift either way.
  ignore_body_changes = length(var.ignore_body_changes.network_virtual_hubs) > 0 ? var.ignore_body_changes.network_virtual_hubs : null
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left unset is
  # absent from the request rather than sent as an explicit JSON null.
  ignore_null_property = true
  # ✅ `response_export_values` IS SET, AND IT IS `[]`. AVM spec TFFR4 is Severity-MUST and tagged
  # Class-Pattern, so it binds this module: an AzAPI resource MUST declare the attribute, "even if
  # empty". An earlier change that removed it repo-wide breached that MUST and has been
  # RETRACTED; see `docs/upgrade-guide.md`.
  #
  # WHY `[]`. Nothing downstream needs a response-only property: `outputs.tf` constructs child IDs
  # from `.id`, which stays known at plan time (the computed-output rule — a computed `.output` in a module
  # output is a day-2 blast-radius bug, confirmed three ways).
  #
  # 🔴 IT IS ONLY SAFE BECAUSE `ignore_changes` SILENCES IT. It carries NO `skip_on:"update"` tag
  # (`azapi_resource.go` L77), so at ADOPTION the imported state holds `null` while the config
  # holds `[]` — `[]` is not `null`, so that is a difference — and it ALONE would take the resource
  # to `actions: ["update"]` and PUT the stale `state.body` (the stale-body behaviour, measured on
  # `gateway-c1` in testing). On this type that PUT is the hub partial-PUT hazard itself.
  # `response_export_values` is entry 12 of the silence contract below, so `ignore_changes` keeps
  # the prior value and there is no adoption diff. NEVER declare this attribute on an
  # `azapi_resource` without that matching `ignore_changes` entry.
  #
  # 🔴 A FUTURE CHANGE TO THIS EXPORT LIST NEEDS ITS OWN MIGRATION. `ignore_changes` pins the
  # prior value, so editing the list is a NO-OP on an already-managed hub until a state operation
  # (`terraform state rm` + re-import, or `-replace`) is performed.
  #
  # `avm_azapi_response_export_values_required` fires on ABSENCE and is now satisfied. It runs at
  # `severity = "notice"` under the pinned AVM base tflint config, as do all eight enabled `avm_*`
  # rules, so a green `avm pr-check` is NOT evidence of MUST compliance.
  response_export_values = []
  retry                  = var.retry
  # L193 `Tags: tags.Expand(d.Get("tags").(map[string]interface{}))`. `tags.Expand` returns a
  # pointer to a map and never nil, so `"tags": {}` was in every create request AzureRM sent.
  # tflint-ignore: avm_azapi_resource_tags_required // the rule wants exactly `tags = var.tags`. These are PER-INSTANCE tags carried on a collection variable, which is the v0.17.2 public API; forcing a single module-wide `var.tags` is a BREAKING interface change. Tracked for the next major.
  tags = each.value.tags != null ? each.value.tags : {}

  # AzureRM's per-resource defaults, `virtual_hub_resource.go` L47-52:
  #   Create 60m, Read 5m, Update 60m, Delete 60m.
  # 🔴 NOT the shared 30m used by the sibling modules. A hub create polls `routingState` to
  # `Provisioned` with `ContinuousTargetOccurence: 3` on top of the ARM LRO (L230-240), which is
  # why the create budget is twice the repo default. Do not copy this number to another type, and
  # do not replace it with one.
  timeouts {
    create = var.timeouts.create
    delete = var.timeouts.delete
    read   = var.timeouts.read
    update = var.timeouts.update
  }

  # ── THE SILENCE CONTRACT ────────────────────────────────────────────────────────────────────
  # `ignore_changes = [body, tags]` is NOT sufficient, and Testing measured why: the resource
  # went to `actions: ["update"]` driven by `response_export_values` and `timeouts`, not by the
  # body at all. `skip.CanSkipExternalRequest` (`internal/skip/skip.go` L14-55, called at
  # `azapi_resource.go:826`) returns false — do the full PUT of `state.body` — for ANY field that
  # (a) has no `skip_on:"update"` struct tag and (b) whose plan value differs from its state
  # value. The create-only guarantee holds only if every such field is pinned.
  #
  # These are the 16 non-skippable, configurable, non-ForceNew attributes on `azapi_resource` in
  # azapi v2.12.0. Line numbers verified against `internal/services/azapi_resource.go` at tag
  # `v2.12.0`. A future azapi bump can add a 17th: the list was ENUMERATED, not guessed, and must
  # be re-enumerated on every provider bump.
  #
  #   |  # | attribute                    | line |    |  # | attribute                 | line |
  #   |----|------------------------------|------|    |----|---------------------------|------|
  #   |  1 | body                         | L59  |    |  9 | list_unique_id_property   | L68  |
  #   |  2 | sensitive_body               | L60  |    | 10 | ignore_other_items_in_list| L69  |
  #   |  3 | sensitive_body_version       | L61  |    | 11 | locks                     | L71  |
  #   |  4 | identity                     | L63  |    | 12 | response_export_values    | L77  |
  #   |  5 | ignore_body_changes          | L64  |    | 13 | schema_validation_enabled | L79  |
  #   |  6 | ignore_casing                | L65  |    | 14 | tags                      | L80  |
  #   |  7 | ignore_missing_property      | L66  |    | 15 | update_headers            | L85  |
  #   |  8 | ignore_null_property         | L67  |    | 16 | update_query_parameters   | L86  |
  #
  # DELIBERATELY EXCLUDED, with the reason:
  #   `id` L62, `output` L73                        Computed-only; cannot diff from config.
  #   `name` L72, `parent_id` L74, `type` L82,
  #   `location` L70                                ForceNew. A change REPLACES rather than
  #                                                 updates, so the create-only guarantee is not
  #                                                 what protects them and listing them would
  #                                                 HIDE a replacement.
  #   `replace_triggers_external_values` L75,
  #   `replace_triggers_refs` L76                   Replacement machinery. See the ForceNew note
  #                                                 below for why neither is used here.
  #   `retry` L78, `timeouts` L81, `create_headers`
  #   L83, `create_query_parameters` L84,
  #   `delete_headers` L87,
  #   `delete_query_parameters` L88, `read_headers`
  #   L89, `read_query_parameters` L90              Carry `skip_on:"update"`. A diff on these is
  #                                                 STATE-ONLY with no ARM call. Measured in test
  #                                                 (ii): the full writer's only diff was
  #                                                 `timeouts` and `arm_call` was `false`.
  #
  # 🔴 A ForceNew PARITY LOSS is accepted here, and it is a real behaviour difference.
  # `address_prefix` (L69), `sku` (L82) and `virtual_wan_id` (L92) are ForceNew on
  # `azurerm_virtual_hub`: changing one REPLACED the hub. In this shape they live inside `body`,
  # which is ignored, so changing one is now silently a no-op — accepted cost (a) applied to this
  # type. NEITHER piece of azapi replacement machinery is used to restore it, and the reason
  # differs for each:
  #
  #   `replace_triggers_refs` L76               Cannot work. `ignore_changes` rewrites the
  #                                             proposed body to the prior state BEFORE the
  #                                             provider's ModifyPlan runs, so the trigger never
  #                                             sees a difference.
  #
  #   `replace_triggers_external_values` L75    🔴 POSITIVELY RULED OUT — not merely unused. It
  #                                             COULD read the variables directly, and an earlier
  #                                             revision of this comment claimed that made it
  #                                             workable. That claim is SUPERSEDED. The attribute
  #                                             carries NO `skip_on` tag, and its plan modifier is
  #                                             `RequiresReplaceIfNotNull`
  #                                             (`planmodifierdynamic/dynamic_requires_replace.go`
  #                                             at azapi v2.12.0), which does NOT replace when the
  #                                             STATE value is null. At ADOPTION the imported
  #                                             state holds exactly that null, so the modifier
  #                                             stays silent and the plain diff (null state vs
  #                                             non-null config) takes the resource to
  #                                             `actions: ["update"]` instead. With no `skip_on`
  #                                             tag, `skip.CanSkipExternalRequest` then returns
  #                                             false and the provider PUTs the STALE `state.body`
  #                                             in full — the hub partial-PUT hazard documented at
  #                                             the top of this file, fired by the very attribute
  #                                             added to prevent a different hazard. It buys no
  #                                             replacement at adoption and costs a full PUT.
  #
  # THE CHOSEN MECHANISM IS A LIFECYCLE PRECONDITION ON THE MERGE WRITER instead. It is inert at
  # plan-time cost, makes no ARM call, and cannot alter the plan graph — it can only FAIL the plan.
  # See the FORCENEW GUARD block on `azapi_update_resource.this` below. A precondition cannot plan
  # the replacement AzureRM would have planned, so this is still a parity loss; what it converts is
  # a SILENT no-op into a LOUD, actionable plan error.
  lifecycle {
    ignore_changes = [
      body,
      identity,
      ignore_body_changes,
      ignore_casing,
      ignore_missing_property,
      ignore_null_property,
      ignore_other_items_in_list,
      list_unique_id_property,
      locks,
      response_export_values,
      schema_validation_enabled,
      sensitive_body,
      sensitive_body_version,
      tags,
      type,
      update_headers,
      update_query_parameters,
    ]
  }
}

# ──────────────────────────────────────────────────────────────────────────── merge writer ──────
# DAY 2. GETs the live hub and merges this body into it (`mergeObjectAtPath` MAP branch,
# `utils/json.go` L45-58, preservation at L52-53), so it NEVER drops an undeclared property. This
# is the replacement for `resourceVirtualHubUpdate`'s GET-then-modify-then-PUT, and it is what
# makes the 11 undeclared writable paths listed at the top of this file safe on day 2.
#
# 🔴 `azapi_update_resource` has no `tags` argument and no `ignore_null_property`. Tags used to
# travel as a BODY KEY here for that reason, and that is what made REG-1; as of 0.19.0 they are
# gone from this body entirely and live on `azapi_resource_action.tags` below. The body is still
# built with no null-valued keys so that nothing is merged as an explicit JSON null.
resource "azapi_update_resource" "this" {
  for_each = local.virtual_hubs

  resource_id = azapi_resource.this[each.key].id
  type        = var.resource_types.network_virtual_hubs
  body        = local.virtual_hub_update_bodies[each.key]
  # ✅ TFFR4 (Severity-MUST, Class-Pattern) requires the attribute on every AzAPI resource, "even
  # if empty". `[]` is correct: nothing reads this writer's `.output` and the computed-output rule keeps a
  # computed `.output` out of a module output. A future change to this list needs its own
  # migration, the same as on the full writer. No `ignore_changes` here — this address is never
  # imported, so it is always created fresh and the null-vs-`[]` adoption difference cannot arise.
  response_export_values = []
  retry                  = var.retry

  # Same AzureRM per-resource defaults, `virtual_hub_resource.go` L47-52.
  timeouts {
    create = var.timeouts.create
    delete = var.timeouts.delete
    read   = var.timeouts.read
    update = var.timeouts.update
  }

  # ── FORCENEW GUARD ──────────────────────────────────────────────────────────────────────────
  # `azurerm_virtual_hub` has exactly SIX ForceNew inputs at v4.81.0. Three of them map to
  # attributes that are ALREADY ForceNew on `azapi_resource`, so they need nothing here:
  #
  #   `name` L58                                  -> azapi `name`      (ForceNew, L72)
  #   `resource_group_name` L62,
  #     `commonschema.ResourceGroupName()`,
  #     ForceNew at go-azure-helpers
  #     `resourcemanager/commonschema/
  #      resource_group_name.go` L15               -> azapi `parent_id` (ForceNew, L74)
  #   `location` L64, `commonschema.Location()`,
  #     ForceNew at go-azure-helpers
  #     `resourcemanager/commonschema/
  #      location.go` L15                          -> azapi `location`  (ForceNew, L70)
  #
  # The other three live in `body`, which the full writer ignores, so azapi sees no diff at all:
  #
  #   `address_prefix` L69   -> `body.properties.addressPrefix`  (create L196-198)
  #   `sku` L82              -> `body.properties.sku`            (create L200-202,
  #                                                               `parameters.Properties.Sku`;
  #                                                               a PROPERTIES key on this type,
  #                                                               not the top-level ARM `sku`)
  #   `virtual_wan_id` L92   -> `body.properties.virtualWan.id`  (create L204-208)
  #
  # There is no `CustomizeDiff` on this resource, so those four literal `ForceNew: true` schema
  # entries plus the two commonschema helpers are the COMPLETE set.
  #
  # 🔴 WHY READING `azapi_resource.this[...].body` IS RELIABLE. `ignore_changes = [body]` pins the
  # full writer's planned body to the PRIOR STATE body, so this reference is the create-time (or,
  # after adoption, the import-time readback) value — not the config value, which would make the
  # comparison a tautology. Because all three properties are ForceNew, the live object cannot have
  # moved away from that value without a replacement, so state is a faithful stand-in for Azure.
  #
  # 🔴 NULL HANDLING. All three keys can be legitimately ABSENT from the genesis body: `sku` is
  # `optional(string, null)`, and `address_prefix` / `virtual_wan_id` are omitted when empty
  # (`d.GetOk` semantics, reproduced in `local.virtual_hub_bodies` above). A bare `==` against
  # `var.*` would therefore explode on a missing key. Both sides are instead wrapped in
  # `try(..., null)` AND the right-hand side is taken from `local.virtual_hub_bodies`, not from the
  # variable: that is the SAME expression that built the genesis body, so the `GetOk` omission
  # rules apply identically to both sides. absent-vs-absent compares `null == null` (passes) and
  # absent-vs-present compares `null == "Standard"` (fails), so ADDING a previously-absent ForceNew
  # property is caught too. The check is not made vacuous by the null handling.
  #
  # 🔴 EXACT `==`, NOT `lower()`, FOR `addressPrefix` AND `sku`. `lower()` is applied only to
  # `virtualWan.id`, which is an ARM resource ID and genuinely case-insensitive. `sku` is compared
  # exactly because AzureRM's own `StringInSlice([...], false)` (L83-86) is CASE-SENSITIVE, so a
  # case-only change was a ForceNew there too. `addressPrefix` is compared exactly because
  # AzureRM's diff was a plain string compare: `validate.CIDR` (L70) only checks parseability and
  # never rewrites the value. If ARM ever normalises a prefix (host bits set, e.g. `10.0.0.1/23`
  # read back as `10.0.0.0/23`, or IPv6 hex casing), this precondition fires — but so would
  # AzureRM's plan, as a REPLACEMENT. Matching AzureRM's strictness is the point; a `cidrsubnet`
  # round-trip would be LESS faithful, not more.
  lifecycle {
    precondition {
      condition     = try(azapi_resource.this[each.key].body.properties.addressPrefix, null) == try(local.virtual_hub_bodies[each.key].properties.addressPrefix, null)
      error_message = "virtual_hubs[\"${each.key}\"].address_prefix cannot change in place: it is ForceNew on azurerm_virtual_hub (virtual_hub_resource.go L69) and AzureRM would have REPLACED this resource, destroying its connections, gateways and route tables. The azapi full writer ignores `body`, so this change would otherwise be a silent no-op. Restore the original address prefix, or, if replacement is genuinely intended, request it deliberately with `terraform apply -replace='...azapi_resource.this[\"${each.key}\"]'`."
    }

    precondition {
      condition     = try(azapi_resource.this[each.key].body.properties.sku, null) == try(local.virtual_hub_bodies[each.key].properties.sku, null)
      error_message = "virtual_hubs[\"${each.key}\"].sku cannot change in place: it is ForceNew on azurerm_virtual_hub (virtual_hub_resource.go L82) and AzureRM would have REPLACED this resource, destroying its connections, gateways and route tables. The azapi full writer ignores `body`, so this change would otherwise be a silent no-op. Restore the original SKU, or, if replacement is genuinely intended, request it deliberately with `terraform apply -replace='...azapi_resource.this[\"${each.key}\"]'`."
    }

    precondition {
      condition     = try(lower(azapi_resource.this[each.key].body.properties.virtualWan.id), null) == try(lower(local.virtual_hub_bodies[each.key].properties.virtualWan.id), null)
      error_message = "virtual_hubs[\"${each.key}\"].virtual_wan_id cannot change in place: it is ForceNew on azurerm_virtual_hub (virtual_hub_resource.go L92) and AzureRM would have REPLACED this resource, destroying its connections, gateways and route tables. The azapi full writer ignores `body`, so this change would otherwise be a silent no-op. Restore the original Virtual WAN ID, or, if replacement is genuinely intended, request it deliberately with `terraform apply -replace='...azapi_resource.this[\"${each.key}\"]'`."
    }
  }
}

# ──────────────────────────────────────────────────────────────────────────────── tag writer ────
# DAY 2 — THE TAG WRITER. REG-1'S REMEDY. New in 0.19.0.
#
# 🔴 WHY A SEPARATE RESOURCE AT ALL. `azapi_update_resource` is a MERGE writer, and the merge
# preserves every undeclared key of the LIVE object unconditionally — `mergeObjectAtPath`'s map
# branch, `utils/json.go` L52-L53, `} else { res[key] = value }`. So a merge writer can add a tag
# and change a tag but can NEVER REMOVE one: dropping a key from `virtual_hubs[*].tags` produced
# a PUT that silently re-sent the live tag. That was REG-1, a regression against azurerm 4.x,
# whose L289 `payload.Tags = tags.Expand(...)` ASSIGNED the whole map. A PUT at
# `Microsoft.Resources/tags/default` REPLACES the whole tag set instead, which is what that
# assignment did.
#
# ✅ OBSERVED IN TESTING: this PUT DELETED the `stage` tag from a live VPN gateway, left
# `costCentre` and `purpose` intact, and issued exactly ONE ARM write.
#
# 🔴 WHY `azapi_resource_action` AND NOT `azapi_resource`. `Microsoft.Resources/tags/default` is
# an ARM SINGLETON THAT ALWAYS EXISTS, so `azapi_resource` can never CREATE it —
# there is nothing to create, only something to PUT. Do not "improve" this back into an
# `azapi_resource`.
#
# 🔴 WHY `depends_on`. Measured twice: the tags PUT drives the resource provider but
# issues NO hub write — the activity log for the window shows only `Microsoft.Resources/tags/
# write` — and the RP then sits internally in `Updating` for ~4m30s AFTER Terraform has returned.
# Two writes racing on one parent produce a 409. `depends_on` has no per-instance granularity, so
# it serialises the whole address rather than key-by-key; that is stricter than required and is
# the only granularity Terraform offers.
#
# ⚠️ OUT-OF-BAND TAGS ARE NOT DETECTED: this resource's Read issues NO GET
# (`azapi_resource_action_resource.go` L424-L435), so a tag set outside Terraform never appears as
# drift — it is simply overwritten on the next apply. Weaker than AzureRM's drift detection,
# DELIBERATE, and recorded as a named difference in `docs/upgrade-guide.md`.
#
# ⚠️ Its `Delete` is a NO-OP unless `when == "destroy"` (L413-L421), so removing an entry from
# `var.virtual_hubs` issues no tags DELETE. Harmless here: the full writer deletes the hub and its
# tags go with it.
#
# The tag expression is the one the merge writer used before this resource existed, verbatim —
# including the `{}` fallback, which is AzureRM parity: `tags.Expand(nil)` returns a pointer to an
# EMPTY map and never nil, so AzureRM sent `"tags": {}` when tags were unset.
resource "azapi_resource_action" "tags" {
  for_each = local.virtual_hubs

  method = "PUT"
  # 🔴 The FULL writer's id, not the merge writer's. `azapi_update_resource` has an `id` of its
  # own that is not the ARM resource ID of the hub.
  resource_id = "${azapi_resource.this[each.key].id}/providers/Microsoft.Resources/tags/default"
  type        = "Microsoft.Resources/tags@2021-04-01"
  body = {
    properties = {
      tags = each.value.tags != null ? each.value.tags : {}
    }
  }
  # ✅ TFFR4 (Severity-MUST, Class-Pattern): declared on every AzAPI resource, "even if empty".
  # Nothing reads this writer's `.output`, and the computed-output rule keeps a computed `.output` out of a
  # module output.
  response_export_values = []
  retry                  = var.retry

  # `var.tags_depends_on` orders this write after the firewall policy writes. See the variable description.
  depends_on = [azapi_update_resource.this, var.tags_depends_on]
}

# =============================================================================
# AzureRM -> AzAPI state moves (`avm-tf-migration` SKILL.md L66-78)
#
# The provider migration is IN PLACE: same module, same `for_each`/`count`
# boundary, same keys, so every move is a whole-resource move and the consumer
# only bumps the module version. Plan with a normal refresh -- see
# `docs/upgrade-guide.md`; `-refresh=false` hits azapi#1227 and plans a replace.
# =============================================================================

moved {
  from = azurerm_virtual_hub.virtual_hub
  to   = azapi_resource.this
}
