# ---------------------------------------------------------------------------
# Azure Firewall in a Virtual WAN hub, migrated from `hashicorp/azurerm` to
# `Azure/azapi` in place. The public variable shape is unchanged; only the
# provider and the request bodies moved.
#
# THE SHAPE, in one sentence: `azapi_resource` creates the firewall once and
# then never PUTs again, and every subsequent write goes through
# `azapi_update_resource`, which GETs the live object and merges.
#
# This is the create-only-plus-merge shape. Every clause below is here
# because something was measured; see `docs/MIGRATION-DEVIATIONS.md` and `locals.tf` for the
# attribute-by-attribute audit that the `lifecycle` block encodes.
# ---------------------------------------------------------------------------

# ===========================================================================
# CHILD-COLLECTION EXPOSURE -- Microsoft.Network/azureFirewalls
#
# REGISTRY STATUS: **NOT REGISTERED**.
# The child-collection preflight registry carries rows for six types. `microsoft.network/azurefirewalls` is not
# one of them. Per the registry's own coverage doctrine an unregistered type is
# INVISIBLE to preflight CHECK 3 -- the gate prints PASS having checked
# nothing. So the status of every path below is `unmeasured`, and that word is
# meant literally. It is not shorthand for "probably fine".
#
# 🔴 DO NOT REASON BY ANALOGY FROM THE ONE NEARBY ROW.
# `microsoft.network/virtualhubs` -> `properties.azureFirewall` is
# `measured: preserved` (hub PUT minus that path,
# firewall still GET 200/Succeeded, back-reference intact). That row is about
# the HUB's PUT dropping its back-reference TO a firewall. Different resource,
# different path, opposite direction. It licenses nothing here. Measured:
# shape does not predict ARM's behaviour.
#
# WHAT THIS MODULE DOES NOT DECLARE. Enumerated from the 2025-07-01 body type
# (bicep-types-az, network/microsoft.network/2025-07-01, node #1469 ->
# AzureFirewallPropertiesFormat); members flagged 2 are ReadOnly
# (`provisioningState`, `ipGroups`, `afcConfiguration`) and are excluded.
#
#   path                                            registry status
#   ------------------------------------------      ---------------
#   properties.applicationRuleCollections           unmeasured
#   properties.networkRuleCollections               unmeasured
#   properties.natRuleCollections                   unmeasured
#   properties.hubIPAddresses.publicIPs.addresses   unmeasured
#   properties.hubIPAddresses.privateIPAddress      unmeasured
#   properties.managementIpConfiguration            unmeasured
#   properties.autoscaleConfiguration               unmeasured
#   extendedLocation                                unmeasured
#
# There are NO child RESOURCE types under `azureFirewalls` at 2025-07-01. The
# only sub-paths in the ARM spec are `learnedIPPrefixes`, `packetCapture` and
# `packetCaptureOperation`, all POST actions. Everything in the table is an
# INLINE member of the firewall's own body, so it can only be lost to a PUT of
# that body -- which is exactly what this shape exists to stop.
#
# WHAT AZURERM ITSELF SAYS ABOUT THE FIRST THREE. FW L368-386: on every
# non-create apply AzureRM issued its own GET and copied
# `ApplicationRuleCollections`, `NetworkRuleCollections` and
# `NatRuleCollections` out of the live object into the outgoing PUT. A
# provider does not hand-roll a carry-forward for fun; that code IS the
# provider's statement that a full PUT omitting them deletes them. It is a
# strong signal. It is still not a measurement of ARM, and it does not move
# any row above out of `unmeasured`.
#
# THE LAST TWO ROWS GO THE OTHER WAY. AzureRM v4.81.0 has no schema field for
# autoscale configuration or extended location, and no carry-forward for them
# either, so AzureRM's own PUT omitted them on every apply. Under this module
# nobody writes them at all. Still `unmeasured`, but the exposure here is
# strictly smaller than the AzureRM-era module's, not larger.
#
# HOW THE SHAPE CLOSES THE EXPOSURE, and where that stops being a claim:
#   - FULL WRITER: create-only, so its single PUT happens when the object does
#     not yet exist. There is nothing live to drop. Structural, not measured.
#   - MERGE WRITER: GET-then-merge (`mergeObjectAtPath` MAP branch,
#     azapi `utils/json.go`), so an undeclared path is preserved rather than
#     omitted. The mechanism is type-independent by construction and was
#     confirmed live on `microsoft.network/vpngateways` (an earlier test,
#      -- `connections` and `natRules` survived byte-identical bar
#     `etag`).
#     🔴 It has NOT been confirmed on `azureFirewalls`. The registry has no
#     `merge_writer_measured` field for this type because it has no row for
#     this type: unmeasured.
# ===========================================================================

# ---------------------------------------------------------------------------
# GENESIS. Writes once, at create, when there is nothing live to drop.
# ---------------------------------------------------------------------------
resource "azapi_resource" "fw" {
  for_each = local.firewalls

  location  = each.value.location
  name      = each.value.name
  parent_id = local.firewall_parent_ids[each.key]
  type      = var.resource_types.network_azure_firewalls
  body      = local.firewall_bodies[each.key]
  # ✅ TFFR8 (Severity-MUST, Class-Pattern) -- "the `ignore_body_changes` argument of every
  # supported AzAPI resource MUST be configurable by the consumer", and authors "MUST NOT omit
  # the argument". The spec's own collapse-to-null form is used so the write-only argument stays
  # ABSENT at the `[]` default, which is what keeps a consumer on Terraform < 1.11 unaffected.
  #
  # 🔴 ITS REACH ON THIS ADDRESS IS ALMOST NIL, and that is a property of the writer split, not
  # of the variable. v2.12.0 calls `overrideBodyWithPaths` from exactly two places, and both are
  # gated on there already being prior state: `ModifyPlan` (`azapi_resource.go` L542) at L630,
  # under the `if state != nil && len(ignoreBodyChanges) != 0` test at L619; and the CreateUpdate
  # path at L942, under the `if !isNewResource {` guard at L930. Neither fires on a create -- and
  # this address never takes the update path for body drift either, because `body` is in the
  # `ignore_changes` list below. The day-2
  # merge writer, which does take that path, cannot accept the argument at all: v2.12.0's
  # `AzapiUpdateResourceModel` (`azapi_update_resource.go` L40-L63) has no such field. Both facts
  # were read from the provider source at tag v2.12.0; neither was measured against Azure.
  #
  # ⚠️ `ignore_body_changes` also appears in the `ignore_changes` list below. That entry does NOT
  # neuter this assignment: the attribute is `WriteOnly: true` (`azapi_resource.go` L255) so its
  # state value is permanently null, and the provider reads the CONFIG value, not the planned
  # one (`azapi_resource.go` L575, L931, L1104). The `ignore_changes` entry is therefore inert
  # either way and is left in place only because it is audited against the full v2.12.0
  # attribute set in `local.full_writer_ignored_attributes`.
  ignore_body_changes = length(var.ignore_body_changes.network_azure_firewalls) > 0 ? (
    var.ignore_body_changes.network_azure_firewalls
  ) : null
  # Matches AzureRM's nil-pointer/`omitempty` serialisation: an optional the
  # consumer left unset is absent from the request rather than sent as an
  # explicit JSON null. Null VALUES only -- the empty-but-present members
  # AzureRM sent unconditionally (`ipConfigurations: []`, `threatIntelMode:
  # ""`, `additionalProperties: {}`) are not null and survive the prune.
  ignore_null_property = true
  # =======================================================================
  # ✅ `response_export_values` IS SET. AVM spec TFFR4 is Severity-MUST and
  # tagged Class-Pattern, so it binds this module: an AzAPI resource MUST
  # declare the attribute, "even if empty". An earlier change that removed it
  # repo-wide breached that MUST and has been RETRACTED.
  #
  # WHY `[]` AND NOT `["properties.hubIPAddresses"]`. The hub IP addresses are
  # read by the SEPARATE read-only `data "azapi_resource" "fw_hub_ip_addresses"`
  # below, precisely so that no writer has to carry them. the computed-output rule also keeps
  # a computed `.output` out of a module output, so nothing here would consume
  # a non-empty list anyway.
  #
  # 🔴 IT IS ONLY SAFE BECAUSE `ignore_changes` SILENCES IT. The attribute
  # carries NO `skip_on` tag (`azapi_resource.go` L77), so
  # `skip.CanSkipExternalRequest` (`internal/skip/skip.go` L14-L56, called at
  # `azapi_resource.go` L826) returns false the moment plan and state differ on
  # it. At ADOPTION the imported state holds `null` while the config holds `[]`
  # -- a difference -- and that alone would drag the firewall into
  # `["update"]` and PUT the stale `state.body`, which is the observed test
  # (ii) failure. `response_export_values` is in
  # `local.full_writer_ignored_attributes` and in the `lifecycle` block below,
  # which keeps the prior value and removes the diff. NEVER declare this
  # attribute on an `azapi_resource` without that matching entry.
  #
  # 🔴 A FUTURE CHANGE TO THIS EXPORT LIST NEEDS ITS OWN MIGRATION.
  # `ignore_changes` pins the prior value, so editing the list is a NO-OP on an
  # already-managed firewall until a state operation (`terraform state rm` +
  # re-import, or `-replace`) is performed.
  #
  # `avm_azapi_response_export_values_required` fires on ABSENCE and is now
  # satisfied. It runs at `severity = "notice"` under the pinned AVM base
  # tflint config, as do all eight enabled `avm_*` rules, so a green
  # `avm pr-check` is NOT evidence of MUST compliance.
  # =======================================================================
  response_export_values = []
  retry                  = var.retry
  # FW L262 + L276. AzureRM sent `"tags": {}` for an untagged firewall, so the
  # null is normalised in `locals.tf` rather than passed through.
  # tflint-ignore: avm_azapi_resource_tags_required // the rule wants exactly `tags = var.tags`. These are PER-INSTANCE tags carried on a collection variable, which is the v0.17.2 public API; forcing a single module-wide `var.tags` is a BREAKING interface change. Tracked for the next major.
  tags = local.firewall_tags[each.key]

  # FW L46-51 -- AzureRM's own per-resource defaults for `azurerm_firewall`,
  # not a shared house number:
  #   Create 90m (FW L47), Read 5m (FW L48), Update 90m (FW L49),
  #   Delete 90m (FW L50).
  # The `dynamic "timeouts"` wrapper that used to sit here was a no-op: `var.timeouts`
  # is `nullable = false` and `network_azure_firewalls` was `optional(object(...), {})`, so the
  # `for_each` list always had exactly one element and the block was always emitted.
  # A static block is therefore identical, and the per-resource fallbacks now live in
  # `local.timeouts` (`locals.tf`) rather than on the variable.
  timeouts {
    create = local.timeouts.network_azure_firewalls.create
    delete = local.timeouts.network_azure_firewalls.delete
    read   = local.timeouts.network_azure_firewalls.read
    update = local.timeouts.network_azure_firewalls.update
  }

  # ⭐ THE ENTIRE PATTERN IS THIS BLOCK.
  #
  # Without it, any later change to `body` or `tags` makes THIS resource issue
  # a full PUT of the configured body -- which omits every row in the
  # child-collection table above. With it, this address goes inert after create
  # and the merge writer below becomes the only writer.
  #
  # 🔴🔴 THE LIST IS `local.full_writer_ignored_attributes`, AUDITED THERE
  # against azapi v2.12.0 `AzapiResourceModel`. `lifecycle` cannot take a
  # variable or a local, so it is repeated here verbatim;
  # `tests/null_optionals.tftest.hcl` asserts the two agree, but only by
  # comparing the local against a literal -- keeping the block below in step is
  # still a manual job.
  #
  # 🔴 COSTS ACCEPTED HERE, unchanged and on the record:
  #   (a) body drift on every path this file stops watching is PERMANENTLY
  #       invisible. The merge writer still sees drift on the paths IT
  #       declares (sku.tier, firewallPolicy.id, virtualHub.id,
  #       hubIPAddresses.publicIPs.count) and nowhere else. `tags` LEFT that
  #       list in 0.19.0 -- see (b) -- and `azapi_resource_action.tags` does
  #       not detect tag drift at all, by design.
  #   (b) merge is additive -- it CANNOT un-set. It also could not remove a
  #       TAG: dropping a key from `firewalls[*].tags` was a no-op against
  #       Azure while the plan looked like it worked. That was REG-1.
  #       ✅ FIXED IN 0.19.0 -- tags left the merge writer's body and moved to
  #       `azapi_resource_action.tags` below, which PUTs at
  #       `Microsoft.Resources/tags/default` and REPLACES the whole set. The
  #       rest of cost (b) still stands: setting `firewall_policy_id` back to
  #       null is the same no-op: AzureRM's guarded assign at FW L315-317
  #       meant an unset policy was simply omitted from its full PUT and ARM
  #       detached it. Here it is preserved.
  #   (c) `azapi_update_resource.Delete` is an EMPTY FUNCTION
  #       (`azapi_update_resource.go` L676-678): destroying the merge writer
  #       makes no ARM call and leaves the live change in place.
  #   (d) plan-level evidence is nil; gate CHECK 4 annotates, it never proves.
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
  depends_on = [terraform_data.public_ip_mode]
}

# ---------------------------------------------------------------------------
# DAY 2. GET-then-merge, so an omitted path is PRESERVED rather than dropped.
#
# 🔴 This resource also runs at CREATE time -- `azapi_update_resource.Create`
# is a GET + merge + PUT -- so standing a firewall up costs two PUTs, and the
# second one is a 90m-class operation. That is inherent to the shape, not a
# bug in this module.
#
# 🔴 Its `Delete` is an EMPTY FUNCTION (`azapi_update_resource.go` L676-678).
# Removing an entry from `var.firewalls` destroys the full writer, which does
# delete the firewall, so the empty Delete is harmless HERE -- but it is a real
# teardown hazard for anyone who targets this address on its own, and it
# belongs in the upgrade guide.
# ---------------------------------------------------------------------------
resource "azapi_update_resource" "fw" {
  for_each = local.firewalls

  resource_id = azapi_resource.fw[each.key].id
  type        = var.resource_types.network_azure_firewalls
  body        = local.firewall_update_bodies[each.key]
  # 🔴 NO `ignore_body_changes` HERE, AND IT IS NOT AN OVERSIGHT.
  #
  # TFFR8 lists `azapi_update_resource` among the resource types that trigger the requirement,
  # and then says authors "MUST NOT omit the argument". On this resource type that MUST is
  # UNSATISFIABLE in `Azure/azapi` v2.12.0, which is this module's provider floor: the argument
  # does not exist.
  #
  # Read at tag v2.12.0, not recalled:
  #   - `internal/services/azapi_update_resource.go` L40-L63 -- the whole
  #     `AzapiUpdateResourceModel` struct. It has `IgnoreCasing`, `IgnoreMissingProperty`,
  #     `IgnoreOtherItemsInList` and `ListUniqueIdProperty`, and NO `IgnoreBodyChanges` field.
  #     Compare `AzapiResourceModel` at `internal/services/azapi_resource.go` L64, which does.
  #   - `internal/services/azapi_update_resource.go` L93 is that resource's `Schema` method;
  #     the string `"ignore_body_changes"` does not occur anywhere in the file (0 matches).
  #   - Repo-wide, the only service declaring it is `azapi_resource.go` (schema at L252-L260,
  #     `WriteOnly: true` at L255), plus the private-state helper
  #     `internal/services/ignore_body_changes_private.go`.
  #
  # Writing the argument here would be a "Unsupported argument" error at validate time, so the
  # conflict is reported upward rather than worked around. If a later azapi release adds it,
  # wire it to a new `network_azure_firewalls` sibling key -- the variable already carries that
  # key for the full writer above.
  #
  # ⚠️ CONSEQUENCE FOR CONSUMERS: because this is the only writer that performs day-2 body
  # writes, there is at present NO way to suppress drift on an individual firewall body path.
  # `var.ignore_body_changes.network_azure_firewalls` reaches only the create-only writer.
  # ✅ TFFR4 (Severity-MUST, Class-Pattern) requires the attribute on every
  # AzAPI resource, "even if empty". `[]` is correct: nothing reads this
  # writer's `.output` -- the hub IP addresses come from the read-only data
  # source below -- and the computed-output rule keeps a computed `.output` out of a module
  # output. A future change to this list needs its own migration entry. No
  # `ignore_changes` here: this address is never imported, so it is always
  # created fresh and the null-vs-`[]` adoption difference cannot arise.
  response_export_values = []

  # Same AzureRM defaults as the full writer; `azapi_update_resource` supports
  # create/read/update/delete on this block (`azapi_update_resource.go`
  # L290-294).
  # The `dynamic "timeouts"` wrapper that used to sit here was a no-op: `var.timeouts`
  # is `nullable = false` and `network_azure_firewalls` was `optional(object(...), {})`, so the
  # `for_each` list always had exactly one element and the block was always emitted.
  # A static block is therefore identical, and the per-resource fallbacks now live in
  # `local.timeouts` (`locals.tf`) rather than on the variable.
  timeouts {
    create = local.timeouts.network_azure_firewalls.create
    delete = local.timeouts.network_azure_firewalls.delete
    read   = local.timeouts.network_azure_firewalls.read
    update = local.timeouts.network_azure_firewalls.update
  }

  # =========================================================================
  # ⭐ FORCENEW GUARD. The replacement AzAPI cannot perform, turned into an
  # error instead of a silence.
  #
  # WHY HERE AND NOT ON THE FULL WRITER. The full writer's `ignore_changes =
  # [body]` makes a changed `sku_name` or `zones` produce NO diff at all on
  # that address, so a precondition there would be evaluated against a plan
  # that already agrees with itself. This address re-plans on every apply, so
  # it is the one that always runs.
  #
  # WHY IT IS RELIABLE. `azapi_resource.fw[each.key].body` is the STATE body,
  # pinned by `ignore_changes = [body]` on the full writer: it holds whatever
  # CREATE or IMPORT wrote and is never refreshed. For a property
  # AzureRM marked ForceNew that is exactly the right reference point --
  # such a property cannot legally change without a replacement, so the
  # create/import-time value IS the live value, and stale state is not a
  # source of false positives the way it would be for a mutable property.
  #
  # THE AUDIT, from azurerm v4.81.0 `firewall_resource.go` at commit
  # 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa. Every `ForceNew: true` in that
  # schema, and what this module does about it:
  #
  #   FW L61   name                                  -> azapi `name`
  #            ForceNew on `azapi_resource` itself (L72, RequiresReplace
  #            L188-190). NO precondition needed.
  #   FW L73   sku_name                              -> body.properties.sku.name
  #            PRECONDITION 1 below.
  #   FW L110  ip_configuration.subnet_id            -> not exposed
  #            This module has no `ip_configuration` variable and sends a
  #            literal `ipConfigurations: []` (locals.tf). Unreachable.
  #   FW L129  management_ip_configuration (block)   -> not exposed
  #   FW L141  management_ip_configuration.subnet_id -> not exposed
  #            Neither is in `var.firewalls` and neither is ever written.
  #            Unreachable.
  #   FW L227  zones (ZonesMultipleOptionalForceNew) -> body.zones
  #            PRECONDITION 2 below. 🔴 PATH DIFFERENCE: `zones` is a
  #            TOP-LEVEL ARM member, NOT under `properties`.
  #   FW L65   location  (commonschema.Location)     -> azapi `location`
  #   FW L67   resource_group_name                   -> azapi `parent_id`
  #            Both are ForceNew on `azapi_resource` (location via ModifyPlan
  #            L732-735, parent_id via RequiresReplace L197-199). NO
  #            precondition needed -- a diff on either already replaces.
  #
  # NOT GUARDED, and deliberately: `virtual_hub_id`, `sku_tier`,
  # `firewall_policy_id` and `vhub_public_ip_count`. AzureRM does NOT mark any
  # of them ForceNew (FW L203-207, L81-89, L91-95, L208-213), the merge body
  # above carries all four precisely so they CAN change in place, and a
  # precondition on `properties.virtualHub.id` would make that declaration
  # dead and break a supported operation.
  # =========================================================================
  lifecycle {
    # PRECONDITION 1 -- sku_name (FW L73), at `properties.sku.name`.
    #
    # NULL HANDLING: both halves are built by the IDENTICAL expression in
    # `locals.tf`, one reading the state body and one reading the genesis
    # body, so an absent `properties.sku` yields `null` on both sides and
    # `null == null` passes. This is NOT the vacuous `state == null || ...`
    # form: adding a `sku` where the state has none, or removing one, is
    # `null != "azfw_hub"` and FAILS, which is what AzureRM's ForceNew would
    # have done. `lower()` is inside a `try` because `lower(null)` raises.
    #
    # TRADE-OFF, stated: the check trusts `state.body`. If an import wrote a
    # body with no `properties.sku` while the live firewall has one, the plan
    # fails and the consumer must repair the import. That direction is
    # deliberate -- a false stop is recoverable, a missed ForceNew is an
    # undetected divergence between Terraform and Azure.
    precondition {
      condition     = local.firewall_state_sku_names[each.key] == local.firewall_config_sku_names[each.key]
      error_message = "firewalls[\"${each.key}\"].sku_name cannot change in place: the live firewall was created with sku_name \"${coalesce(local.firewall_state_sku_names[each.key], "<absent>")}\" and the configuration now asks for \"${coalesce(local.firewall_config_sku_names[each.key], "<absent>")}\". AzureRM marked sku_name ForceNew (firewall_resource.go L73), so it would have REPLACED this resource -- destroying the firewall and every connection routed through it. AzAPI cannot replace on a body property, so this plan is failed instead. If you really intend the replacement, run terraform apply -replace='module.<path>.azapi_resource.fw[\"${each.key}\"]' deliberately, after confirming the outage is acceptable."
    }

    # PRECONDITION 2 -- zones (FW L227), at TOP-LEVEL `body.zones`, not under
    # `properties`.
    #
    # Same symmetric construction, and see `locals.tf` for why both halves are
    # `toset()` of strings rather than lists. Absence normalises to the empty
    # set on BOTH sides, so a non-zonal firewall passes and
    # `absent -> [1,2,3]` -- a real ForceNew change -- fails.
    precondition {
      condition     = local.firewall_state_zones[each.key] == local.firewall_config_zones[each.key]
      error_message = "firewalls[\"${each.key}\"].zones cannot change in place: the live firewall was created in availability zones [${join(", ", sort(tolist(local.firewall_state_zones[each.key])))}] and the configuration now asks for [${join(", ", sort(tolist(local.firewall_config_zones[each.key])))}]. AzureRM marked zones ForceNew (firewall_resource.go L227, commonschema.ZonesMultipleOptionalForceNew), so it would have REPLACED this resource -- destroying the firewall and every connection routed through it. AzAPI cannot replace on a body property, so this plan is failed instead. If you really intend the replacement, run terraform apply -replace='module.<path>.azapi_resource.fw[\"${each.key}\"]' deliberately, after confirming the outage is acceptable."
    }
  }
}

# ---------------------------------------------------------------------------
# DAY 2 -- THE TAG WRITER. REG-1'S REMEDY. New in 0.19.0.
#
# 🔴 WHY A SEPARATE RESOURCE AT ALL. `azapi_update_resource` is a MERGE writer,
# and the merge preserves every undeclared key of the LIVE object
# unconditionally -- `mergeObjectAtPath`'s map branch, `utils/json.go`
# L52-L53, `} else { res[key] = value }`. So a merge writer can add a tag and
# change a tag but can NEVER REMOVE one: dropping a key from
# `firewalls[*].tags` produced a PUT that silently re-sent the live tag. That
# was REG-1, a regression against azurerm 4.x, where the next apply removed
# it (FW L262 + L276 assigned the WHOLE expanded map). A PUT at
# `Microsoft.Resources/tags/default` REPLACES the whole tag set instead, which
# is what that assignment did.
#
# ✅ OBSERVED IN TESTING: this PUT DELETED the `stage` tag from a live
# VPN gateway, left `costCentre` and `purpose` intact, and issued exactly ONE
# ARM write.
#
# 🔴 WHY `azapi_resource_action` AND NOT `azapi_resource`.
# `Microsoft.Resources/tags/default` is an ARM SINGLETON THAT ALWAYS EXISTS
#, so `azapi_resource` can never CREATE it -- there is nothing to
# create, only something to PUT. Do not "improve" this back into an
# `azapi_resource`.
#
# 🔴 WHY `depends_on`. Measured twice: the tags PUT drives the
# resource provider but issues NO firewall write -- the activity log for the
# window shows only `Microsoft.Resources/tags/write` -- and the RP then sits
# internally in `Updating` for ~4m30s AFTER Terraform has returned. Two writes
# racing on one parent produce a 409, and on THIS type the merge writer is a
# 90m-class operation, so the ordering matters more here than anywhere else.
# `depends_on` has no per-instance granularity, so it serialises the whole
# address rather than key-by-key; that is stricter than required and is the
# only granularity Terraform offers.
#
# ⚠️ OUT-OF-BAND TAGS ARE NOT DETECTED: this resource's Read issues NO GET
# (`azapi_resource_action_resource.go` L424-L435), so a tag set outside
# Terraform never appears as drift -- it is simply overwritten on the next
# apply. Weaker than AzureRM's drift detection, DELIBERATE, and recorded as a
# named difference in `docs/upgrade-guide.md`.
#
# ⚠️ Its `Delete` is a NO-OP unless `when == "destroy"` (L413-L421), so
# removing an entry from `var.firewalls` issues no tags DELETE. Harmless here:
# the full writer deletes the firewall and its tags go with it.
#
# The tag expression is `local.firewall_tags`, unchanged and still the single
# source -- including its `{}` normalisation, which is AzureRM parity:
# `tags.Expand(nil)` returns a pointer to an EMPTY map and never nil.
#
# 🟡 `retry = var.retry`, matching `azapi_resource.fw` and
# `azapi_resource.diagnostic_setting`. Note `azapi_update_resource.fw` above
# carries NO retry at all; the module's convention for every other azapi
# address is `var.retry`, so that is what a new address follows.
# ---------------------------------------------------------------------------
resource "azapi_resource_action" "tags" {
  for_each = local.firewalls

  method = "PUT"
  # 🔴 The FULL writer's id, not the merge writer's. `azapi_update_resource`
  # has an `id` of its own that is not the ARM resource ID of the firewall.
  resource_id = "${azapi_resource.fw[each.key].id}/providers/Microsoft.Resources/tags/default"
  type        = "Microsoft.Resources/tags@2021-04-01"
  body = {
    properties = {
      tags = local.firewall_tags[each.key]
    }
  }
  # ✅ TFFR4 (Severity-MUST, Class-Pattern): declared on every AzAPI resource,
  # "even if empty". Nothing reads this writer's `.output`, and the computed-output rule
  # keeps a computed `.output` out of a module output.
  response_export_values = []
  retry                  = var.retry

  depends_on = [azapi_update_resource.fw]
}

# ---------------------------------------------------------------------------
# HUB IP ADDRESSES, read-only.
#
# 🔴 WHY A `.output` IS ALLOWED HERE AND NOWHERE ELSE IN THIS MODULE.
# 16 rules a computed `.output` out of a module output, and `outputs.tf` used
# to carry a long note explaining why `private_ip_address` and
# `public_ip_addresses` therefore had to be `null`. It was decided that
# note's conclusion wrong for a DATA SOURCE, on:
#
#   a data source HAS NO WRITER. It never PUTs, it has no `state.body`, and
#   `response_export_values` on it cannot drag anything into an update -- so
#   the adoption hazard that governs the attribute on `azapi_resource.fw`
#   (non-skippable, `azapi_resource.go` L77, measured in testing) simply
#   does not exist on this address. Different schema, different lifecycle.
#
# ⛔ DO NOT "FIX" THIS by deleting it, and DO NOT generalise the NON-EMPTY
# list: `azapi_resource.fw` above now declares `response_export_values` too
# (TFFR4 is a MUST), but it declares `[]` and pairs it with an
# `ignore_changes` entry. Giving the writer a NON-EMPTY export list, or
# declaring it without `ignore_changes`, is what caused the testing stale
# PUT.
#
# `response_export_values` is a single narrow path, NOT `["*"]`.
# `buildOutputFromBody` (azapi `internal/services/common.go` L24) takes the
# LIST branch and calls `flattenOutput`, which reproduces the requested path
# inside `output` -- so the value lands at
# `output.properties.hubIPAddresses`, nested, not flattened.
#
# ARM SHAPE, verified against the 2025-07-01 type set that ships INSIDE azapi
# v2.12.0 (`internal/azure/generated/network/microsoft.network/2025-07-01/
# types.json`), not taken on trust:
#   #1569 HubIPAddresses            -> privateIPAddress (string),
#                                      publicIPs (#1570)
#   #1570 HubPublicIPAddresses      -> addresses (array of #1571), count (int)
#   #1571 AzureFirewallPublicIPAddress -> address (string)
# That is exactly the shape AzureRM's own flattener walked at FW L804-819.
#
# 🟡 NO `depends_on` ON THE MERGE WRITER, deliberately. Adding one would defer
# this read to apply time on every change and push an unknown through both
# outputs at plan -- the computed-output cascade, reintroduced by the back door.
# Without it the read depends only on `azapi_resource.fw[*].id`, which is
# stable after create, so the outputs stay KNOWN at plan. THE COST: after a
# `vhub_public_ip_count` change, `public_ip_addresses` is read before the merge
# writer applies and is therefore one apply behind until the next plan.
# `private_ip_address` is unaffected -- a hub firewall's private IP is assigned
# at create and does not move.
# ---------------------------------------------------------------------------
data "azapi_resource" "fw_hub_ip_addresses" {
  for_each = local.firewalls

  resource_id            = azapi_resource.fw[each.key].id
  type                   = var.resource_types.network_azure_firewalls
  response_export_values = ["properties.hubIPAddresses"]
}

# ---------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS. A plain single writer, NOT candidate 1, and that is a
# deliberate difference from the firewall above.
#
# `Microsoft.Insights/diagnosticSettings` has no child collections and no
# undeclared writable members that this module omits: `logs`, `metrics`, the
# four destinations and `logAnalyticsDestinationType` are the whole writable
# surface, and the module feeds all of them. AzureRM's own update path
# (DIAG L351+) is likewise an unconditional `CreateOrUpdate` of a body built
# from scratch. A full PUT here is parity, not a hazard, so the candidate-1
# machinery would buy nothing and would cost cost (b) -- the inability to
# un-set a destination.
# ---------------------------------------------------------------------------
resource "azapi_resource" "diagnostic_setting" {
  for_each = {
    for key, setting in local.flattened_diagnostic_settings : key => setting
    if !local.customer_mode[setting.virtual_hub_key]
  }

  name      = each.value.data.name != null ? each.value.data.name : "diag-${azapi_resource.fw[each.value.virtual_hub_key].name}"
  parent_id = azapi_resource.fw[each.value.virtual_hub_key].id
  type      = var.resource_types.insights_diagnostic_settings
  body      = local.diagnostic_setting_bodies[each.key]
  ignore_body_changes = length(var.ignore_body_changes.insights_diagnostic_settings) > 0 ? (
    var.ignore_body_changes.insights_diagnostic_settings
  ) : null
  ignore_null_property = true
  # ✅ `response_export_values` IS SET, per TFFR4 (Severity-MUST,
  # Class-Pattern). `[]` is correct: `outputs.tf` builds the diagnostic
  # setting IDs by string from the firewall's `.id`, so nothing reads
  # `.output`, and the computed-output rule keeps a computed `.output` out of a module
  # output.
  #
  # ⛔ NO `lifecycle { ignore_changes = [response_export_values] }` -- WITHDRAWN, AND IT MUST
  # NOT COME BACK. This site is "armed": `ignore_body_changes`/`ignore_null_property` leave
  # `body` free, so `skip.CanSkipExternalRequest` is false and a PUT does occur -- it is
  # deliberately NOT a candidate-1 writer, so `body` and `tags` stay visible. Pinning
  # `response_export_values` here reproduces BUG 3: the pin freezes `plan.Output` to the stale
  # null-derived default projection while the writer still PUTs at adoption, so the applied
  # output disagrees with the planned one -> "Error: Provider produced inconsistent result
  # after apply" on first apply after upgrade. Do not copy this withdrawal onto a Class A
  # (fully silent) writer -- there, pinning costs nothing extra since no PUT happens, and BUG 3
  # cannot fire either way.
  response_export_values = []
  retry                  = var.retry

  # DIAG L43-48 -- AzureRM's own per-resource defaults for
  # `azurerm_monitor_diagnostic_setting`, which are NOT the firewall's:
  #   Create 30m (DIAG L44), Read 5m (DIAG L45), Update 30m (DIAG L46),
  #   Delete 60m (DIAG L47).
  # The `dynamic "timeouts"` wrapper that used to sit here was a no-op: `var.timeouts`
  # is `nullable = false` and `insights_diagnostic_settings` was `optional(object(...), {})`, so the
  # `for_each` list always had exactly one element and the block was always emitted.
  # A static block is therefore identical, and the per-resource fallbacks now live in
  # `local.timeouts` (`locals.tf`) rather than on the variable.
  timeouts {
    create = local.timeouts.insights_diagnostic_settings.create
    delete = local.timeouts.insights_diagnostic_settings.delete
    read   = local.timeouts.insights_diagnostic_settings.read
    update = local.timeouts.insights_diagnostic_settings.update
  }
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
  from = azurerm_firewall.fw
  to   = azapi_resource.fw
}

moved {
  from = azurerm_monitor_diagnostic_setting.this
  to   = azapi_resource.diagnostic_setting
}

# ===========================================================================
# CUSTOMER-PROVIDED PUBLIC IPs (customer-IP mode)
#
# A firewall whose `ip_configurations` map is non-empty is created and maintained by
# `module.customer_firewalls`; the managed-IP writers above iterate only `local.firewalls`.
# The inventory read needs subscription-scoped firewall read permission and is requested only when at
# least one firewall is in customer-IP mode.
# ===========================================================================
data "azapi_client_config" "current" {
  count = length(local.requested_customer_firewalls) == 0 ? 0 : 1
}

data "azapi_resource_list" "firewalls" {
  count = length(local.requested_customer_firewalls) == 0 ? 0 : 1

  parent_id = "/subscriptions/${one(data.azapi_client_config.current).subscription_id}"
  type      = var.resource_types.network_azure_firewalls
  response_export_values = {
    firewalls = "value[].{id:id,name:name,properties:properties}"
  }
}

resource "terraform_data" "public_ip_mode" {
  for_each = local.all_firewalls

  input = local.customer_mode[each.key]

  lifecycle {
    # Keep only this state-only record immutable; the postcondition rejects rather than hides a mode edit.
    ignore_changes = [input]

    precondition {
      condition = !local.customer_mode[each.key] ? true : (
        local.existing_firewalls[each.key] == null ? true : local.existing_customer_mode[each.key]
      )
      error_message = "Firewall ${each.key}: changing between managed and customer public IP modes is not supported by normal apply. Keep the existing mode; cross-mode conversion requires a separately planned migration."
    }
    postcondition {
      condition     = self.output == local.customer_mode[each.key]
      error_message = "Firewall ${each.key}: the recorded public IP mode cannot change. Keep the existing managed/customer mode; removing the final customer IP or adding customer IPs to a managed firewall is not supported."
    }
  }
}

module "customer_firewalls" {
  source   = "../firewall-customer-ip"
  for_each = local.customer_firewalls

  ip_configurations = each.value.ip_configurations
  location          = each.value.location
  name              = each.value.name
  parent_id         = local.parent_ids[each.key]
  virtual_hub_id    = each.value.virtual_hub_id
  diagnostic_settings = {
    for key, setting in local.diagnostic_settings_v2 : key => setting
    if local.flattened_diagnostic_settings[key].virtual_hub_key == each.key
  }
  enable_telemetry    = var.enable_telemetry
  firewall_policy_id  = each.value.firewall_policy_id
  ignore_body_changes = var.ignore_body_changes
  resource_types      = var.resource_types
  retry               = var.retry
  sku_tier            = each.value.sku_tier
  tags                = each.value.tags
  timeouts            = var.timeouts
  zones               = each.value.zones

  depends_on = [terraform_data.public_ip_mode]
}
