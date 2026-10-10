# Create a site to site vpn gateway in a virtual hub.
#
# ---------------------------------------------------------------------------
# CANDIDATE 1 (FINAL). `azapi_resource` creates the gateway ONCE and then never
# PUTs again; every day-2 write goes through `azapi_update_resource`, which GETs
# the live object and merges into it.
#
# WHY THIS SHAPE AND NOT A SINGLE `azapi_resource` LIKE THE OTHER FOUR MODULES.
# `Microsoft.Network/vpnGateways` owns two CHILD COLLECTIONS inside its own
# body -- `properties.connections` (the VPN connections this repo creates from
# `modules/site-to-site-gateway-connection`) and `properties.natRules`. A full
# PUT that does not declare them DELETES them. That is measured, not inferred:
# `properties.connections` is `measured: deleted` in the child-collection
# registry. A writer that declares the whole body therefore cannot be
# allowed to PUT a second time, because the body this module builds has neither
# collection in it.
#
# The pattern, its 17-entry silence contract and the costs it accepts are
# specified in `docs/MIGRATION-DEVIATIONS.md`.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# GENESIS -- THE FULL WRITER. CREATE-ONLY.
#
# After create this address must never PUT again, so there is exactly ONE
# writer against a live object and the partial-PUT hazard cannot occur through
# it. Everything that could drag it into an update is silenced by the
# `lifecycle` block below.
# ---------------------------------------------------------------------------
resource "azapi_resource" "this" {
  for_each = local.vpn_gateways

  # AzureRM sent `location.Normalize(...)` on the wire (L250); this sends the consumer's
  # string verbatim. Not a behaviour difference: azapi declares a SEMANTIC EQUALITY
  # function on this attribute (`azapi_resource.go` L219) and normalises both sides again
  # before deciding to replace (L732), so "UK South" and "uksouth" are the same location to
  # both providers, and ARM accepts either form.
  location  = each.value.location
  name      = each.value.name
  parent_id = local.vpn_gateway_parent_ids[each.key]
  type      = var.resource_types.network_vpn_gateways
  body      = local.vpn_gateway_bodies[each.key]
  # ⚠️ Effectively inert under this shape and kept only so the module's input surface
  # matches its four sibling submodules. `lifecycle.ignore_changes` already pins the WHOLE
  # body on this resource, so a finer-grained per-path ignore has nothing left to do, and
  # `azapi_update_resource` -- the only writer that runs after create -- has no equivalent
  # attribute. A non-empty value still reaches the create PUT.
  ignore_body_changes = length(var.ignore_body_changes.network_vpn_gateways) > 0 ? var.ignore_body_changes.network_vpn_gateways : null
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left
  # unset is absent from the request rather than sent as an explicit JSON null. Null VALUES
  # only -- `bgpSettings` is built as a whole-object null in `vpn_gateway_bodies` above so
  # that `expandVPNGatewayBGPSettings` returning nil is reproduced as an absent key.
  ignore_null_property = true
  #
  # 🔴 NEITHER `replace_triggers_refs` NOR `replace_triggers_external_values` IS SET, AND
  # THAT IS A DELIBERATE, REPORTED NON-PARITY -- not an oversight.
  #
  # Hardened further: `replace_triggers_external_values` is now a
  # POSITIVE PROHIBITION on this resource rather than merely an attribute nobody reached
  # for, and the ForceNew guarantee it was once a candidate for is carried instead by
  # LIFECYCLE PRECONDITIONS on the merge writer below.
  #
  # AzureRM marked four configurable properties ForceNew that live inside `body`:
  # `virtual_hub_id` (L63), `routing_preference` (L71), `bgp_settings.asn` (L94) and
  # `bgp_settings.peer_weight` (L100). Neither azapi mechanism can reproduce them here:
  #
  #  1. `replace_triggers_refs` compares `state.Body` against `plan.Body`
  #     (`azapi_resource.go` L737-L775, `flattenOutputJMES` over both). `ignore_changes =
  #     [body]` makes Terraform plan the PRIOR STATE value for `body`, so plan.body is
  #     state.body by construction and the comparison can never differ. It would be dead
  #     code advertising a guarantee it does not provide.
  #  2. `replace_triggers_external_values` IS RULED OUT, on two independent grounds, both
  #     read out of azapi v2.12.0:
  #     (a) IT DOES NOT REPLACE WHEN IT WOULD MATTER MOST. Its plan modifier is
  #         `RequiresReplaceIfNotNull`, in
  #         `internal/services/myplanmodifier/planmodifierdynamic/dynamic_requires_replace.go`:
  #         `resp.RequiresReplace = !planNull && !stateNull`. After an IMPORT the state
  #         value is null -- the attribute is config-only, so there was nothing for the read
  #         to populate -- and an adoption plan that first introduces it therefore gets an
  #         UPDATE, not a replacement.
  #     (b) AND THAT UPDATE IS A FULL PUT. The attribute carries NO `skip_on:"update"` tag
  #         (`AzapiResourceModel` L75; compare `retry` L78 and `timeouts` L81, which do), so
  #         `skip.CanSkipExternalRequest` returns false on the null-to-value difference
  #         alone and the full writer PUTs its stale `state.body` at a live gateway that
  #         owns `properties.connections`. That is the stale-body behaviour, landing on the one resource
  #         in this repo where a partial PUT is MEASURED to delete child collections.
  #     Buying ForceNew parity with a partial PUT of a gateway's child collections is not a
  #     trade this module will make.
  #
  # ✅ WHAT IS DONE INSTEAD: one `lifecycle.precondition` per category-(a) ForceNew body
  # property, on `azapi_update_resource.this` below. A precondition cannot replace the
  # gateway -- only a human passing `-replace` can -- but it converts the old silent no-op
  # into a HARD PLAN FAILURE that names the offending property. The null-handling and its
  # one known gap are documented on that block.
  #
  # CONSEQUENCE, stated as a consumer sees it: changing `virtual_hub_id`,
  # `routing_preference`, `bgp_settings.asn` or `bgp_settings.peer_weight` on an EXISTING
  # gateway still produces NO plan diff and NO replacement on THIS address -- but the plan
  # now FAILS on the merge writer's precondition rather than succeeding and doing nothing.
  # Under azurerm the same edit destroyed and recreated the gateway; the consumer must now
  # ask for that destruction explicitly, having accounted for the connections it takes with
  # it. `location`, `name` and `parent_id` are unaffected -- azapi replaces on all three
  # natively (L189, L198, ModifyPlan L732-L735), none of them is in the ignore list, and so
  # none of them needs a precondition.
  #
  # ==========================================================================================
  # ✅ `response_export_values` IS SET, AND IT IS SET DELIBERATELY. AVM spec TFFR4 is
  # Severity-MUST and tagged Class-Pattern, so it binds this module: an AzAPI resource MUST
  # declare the attribute, "even if empty". An earlier change that removed it repo-wide
  # breached that MUST and has been RETRACTED; see `docs/upgrade-guide.md`.
  #
  # WHY `[]`. Nothing downstream reads a response-only property. Consumers take `.id` and
  # `.name`, both of which AzAPI exposes natively; the BGP peering-address IDs that
  # `outputs.tf` used to read back are now CONSTRUCTED (see the `ip_configuration_ids` note
  # there), and the computed-output rule already rules a computed `.output` out of a module output because
  # it goes unknown on every update and takes the whole downstream chain unknown with it.
  #
  # 🔴 IT IS ONLY SAFE BECAUSE `ignore_changes` SILENCES IT. The attribute carries NO
  # `skip_on` tag (`azapi_resource.go` L77), so at ADOPTION the imported state holds `null`
  # while the config holds `[]` -- `[]` is not `null`, so that is a difference -- and it alone
  # would drag the resource into `["update"]` and PUT the stale `state.body`. On
  # THIS resource that PUT drops `properties.connections`, and it is the defect
  # found on the candidate-1 gateway fixture. `response_export_values` is entry 10 of
  # `local.full_writer_ignored_attributes` and appears in the `lifecycle` block below, which
  # keeps the prior value and removes the diff. NEVER declare this attribute on an
  # `azapi_resource` without that matching `ignore_changes` entry.
  #
  # 🔴 A FUTURE CHANGE TO THIS EXPORT LIST NEEDS ITS OWN MIGRATION. `ignore_changes` pins
  # the prior value, so editing the list is a NO-OP on an already-managed gateway until a
  # state operation (`terraform state rm` + re-import, or `-replace`) is performed.
  #
  # `avm_azapi_response_export_values_required` fires on ABSENCE and is now satisfied. It runs
  # at `severity = "notice"` under the pinned AVM base tflint config, as do all eight enabled
  # `avm_*` rules, so a green `avm pr-check` is NOT evidence of MUST compliance -- the spec
  # text is the authority, not the linter's exit code.
  # ==========================================================================================
  response_export_values = []
  retry                  = var.retry
  # `try(each.value.tags, {})` is preserved verbatim from the AzureRM resource, including
  # the `try`: `tags` is `optional(map(string))` with no default, so `try` returns the null
  # unchanged rather than the `{}` fallback. AzureRM turned that null into `tags: {}` via
  # `tags.Expand`; AzAPI omits the key. Same resulting tag set, one fewer key on the wire.
  # tflint-ignore: avm_azapi_resource_tags_required // the rule wants exactly `tags = var.tags`. These are PER-INSTANCE tags carried on a collection variable, which is the v0.17.2 public API; forcing a single module-wide `var.tags` is a BREAKING interface change. Tracked for the next major.
  tags = try(each.value.tags, {})

  # AzureRM's OWN per-resource defaults, not a shared 30m and not another module's number.
  # `vpn_gateway_resource.go` L41-L46:
  #   Create 90m (L42)   Read 5m (L43)   Update 90m (L44)   Delete 90m (L45)
  # `var.timeouts` carries those four values as its attribute defaults so a consumer can
  # still override them; see `variables.tf`.
  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  # ⭐ THE ENTIRE PATTERN IS THIS BLOCK. Without it, any later change to `body` or `tags`
  # makes THIS resource issue a full PUT of the configured body -- which has no
  # `properties.connections` and no `properties.natRules` in it, and that is the MEASURED
  # deletion. With it, this address goes inert after create and the
  # merge writer below is the only writer.
  #
  # 🔴 THE PRICE, stated where it is paid, and narrower than "drift is invisible forever":
  # candidate 1 sees drift on exactly the paths the MERGE writer declares (`tags`,
  # `properties.vpnGatewayScaleUnit`, `properties.enableBgpRouteTranslationForNat` and the
  # two `customBgpIpAddresses` lists) and is blind on every other path -- including
  # everything this resource sets at create and then stops watching. Observed in testing.
  #
  # 🔴🔴 THE LIST IS `local.full_writer_ignored_attributes`, ENUMERATED THERE.
  # `lifecycle` cannot take a variable or a local, so it is repeated here verbatim.
  # `tests/null_optionals.tftest.hcl` asserts the local's contents; the two must be kept in
  # step BY HAND, and the audit comment on the local is where the reasoning for each entry
  # lives.
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

# ---------------------------------------------------------------------------
# DAY 2 -- THE MERGE WRITER.
#
# GETs the live object and merges into it, so a property it does not declare is
# PRESERVED rather than dropped (`azapi_update_resource.go` :459,:480,:503,:520
# feeding `utils.MergeObject` -> `mergeObjectAtPath`, `utils/json.go` L39-L105;
# the map branch at L45-L58 is the one that keeps `properties.connections`).
#
# This is also where AzureRM's SECOND create PUT lands -- see the custom-BGP-IP
# note in `locals` above -- so the request sequence a consumer sees is the same
# one AzureRM produced.
#
# ✅ REG-1 IS FIXED, AND THE FIX IS THAT `tags` IS NO LONGER ON THIS BLOCK.
# The merge is additive PER KEY: `mergeObjectAtPath`'s map branch copies every key of the LIVE
# object that the request does not declare straight back into the request
# (`utils/json.go` L52-L53, `} else { res[key] = value }`, unconditional). A merge writer can
# therefore add a tag and change a tag but can NEVER REMOVE ONE. AzureRM's Update assigned the
# WHOLE tag map (`tags.Expand`, L332-L333), so deleting a key from `var.tags` removed it from
# Azure; under the merge writer the plan showed the key leaving the body, the apply succeeded,
# and Azure kept the tag indefinitely with no warning (observed in testing: `driftProbe = oob-probe`
# survived the merge PUT and was never mentioned in any plan).
#
# Tags now travel on `azapi_resource_action.tags` below, which PUTs at
# `Microsoft.Resources/tags/default` and REPLACES the whole tag set. Observed in testing,
# : that PUT DELETED the `stage` tag from a live VPN gateway, left `costCentre` and
# `purpose` intact, and issued exactly one ARM write.
#
# 🔴 Its `Delete` is an EMPTY FUNCTION (`azapi_update_resource.go` L676-L678):
# destroying this resource makes NO ARM call and silently leaves the live change
# in place. That is a teardown hazard, not a day-2 one, and it belongs in the
# upgrade guide.
# ---------------------------------------------------------------------------
resource "azapi_update_resource" "this" {
  for_each = local.vpn_gateways

  # Never the constructed ID: taking it off the full writer is what orders the two writers
  # and what guarantees the gateway exists before the merge PUT is attempted.
  resource_id = azapi_resource.this[each.key].id
  type        = var.resource_types.network_vpn_gateways
  body        = local.vpn_gateway_update_bodies[each.key]
  # ✅ TFFR4 (Severity-MUST, Class-Pattern) requires the attribute on every AzAPI resource,
  # "even if empty". `[]` is correct: nothing reads this writer's `.output` and `outputs.tf`
  # must not expose a computed `.output`. A future change to this list needs its
  # own migration, the same as on the full writer. No `ignore_changes` is needed here -- this
  # address is never imported, so it is always created fresh and the null-vs-`[]` adoption
  # difference the full writer guards against cannot arise.
  response_export_values = []
  retry                  = var.retry

  # `azapi_update_resource` has no create/delete of its own against ARM: its "create" is the
  # first merge PUT and its `Delete` is a no-op, so both ARM-facing operations take
  # AzureRM's UPDATE timeout (`vpn_gateway_resource.go` L44: 90m) and the read takes its
  # read timeout (L43: 5m). `delete` is not set because no request is ever issued.
  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]

    content {
      create = timeouts.value.update
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  # =========================================================================
  # ⚖️ FORCE-NEW PARITY, ENFORCED AS A PLAN-TIME REFUSAL.
  #
  # Every property AzureRM marked `ForceNew: true` that lives in `body` gets one
  # precondition here. Enumerated against `vpn_gateway_resource.go` at
  # 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0) -- the file has exactly
  # five `ForceNew: true` lines:
  #
  #   L52  name                     -> azapi `name`      ALREADY ForceNew on the
  #                                    azapi resource (RequiresReplace, L189).
  #                                    NO precondition needed.
  #   L63  virtual_hub_id           -> body.properties.virtualHub.id        ✔ below
  #   L71  routing_preference       -> body.properties.isRoutingPreferenceInternet ✔ below
  #   L94  bgp_settings.asn         -> body.properties.bgpSettings.asn      ✔ below
  #   L100 bgp_settings.peer_weight -> body.properties.bgpSettings.peerWeight ✔ below
  #
  # Plus the two ForceNew commonschema helpers, which are also NOT preconditioned
  # because azapi already replaces on them natively:
  #   L56  resource_group_name (`commonschema.ResourceGroupName()`) -> half of
  #        `parent_id`, ForceNew on azapi at `azapi_resource.go` L198.
  #   L58  location (`commonschema.Location()`) -> azapi `location`, ForceNew via
  #        ModifyPlan L732-L735.
  #
  # WHY THIS READS THE OTHER RESOURCE'S BODY AND WHY THAT IS RELIABLE.
  # `azapi_resource.this` has `ignore_changes = [body]`, so Terraform plans the
  # PRIOR STATE value for `body` forever. `azapi_resource.this[...].body` is
  # therefore the CREATE-TIME (or IMPORT-TIME) value, not the configured one, and
  # these properties cannot change on the live object without a replacement. On
  # the very first plan the resource is being created, state and config are the
  # same value, and every precondition below passes by construction -- which is
  # also why `tests/forcenew_preconditions.tftest.hcl` has to APPLY before it can
  # test anything. A plan-only suite here is a guaranteed false negative.
  #
  # 🔴 BOTH SIDES COME FROM THE SAME EXPRESSION. The right-hand side of every
  # comparison is `local.vpn_gateway_bodies[each.key]` -- the genesis body -- not
  # `each.value.*`. The state side IS that local, frozen at create. Sourcing the
  # config side from it too means the schema defaults, the "Microsoft Network" ->
  # boolean conversion and the whole-object null for `bgpSettings` are applied
  # identically on both sides, instead of being re-implemented here where they
  # could drift. Absent-vs-absent is `null == null`, not `null` vs `""`.
  #
  # 🔴 NULL-HANDLING, STATED RATHER THAN HIDDEN.
  #  * `virtualHub.id` -- `try(..., "")` on BOTH sides, because `lower(null)` RAISES
  #    rather than returning null and a raised condition is a confusing plan error
  #    rather than this module's message. Neither side can actually be null: the key
  #    is unconditional in `vpn_gateway_bodies`, `virtual_hub_id` is required, and
  #    ARM's GET is MEASURED to return `virtualHub.id` on a provisioned gateway
  #    (a captured live 2025-07-01 response), which is the body an
  #    adoption import lands in state. The fallback is a guard, not an escape hatch:
  #    `""` on one side and an ID on the other still FAILS.
  #  * `isRoutingPreferenceInternet` -- STRICT, no fallback. A BOOLEAN, always present
  #    on both sides (schema Default "Microsoft Network" collapses to `false`), and
  #    also measured present on ARM's GET even when false.
  #  * `bgpSettings.asn` / `.peerWeight` -- the only asymmetric pair, because
  #    `bgpSettings` is a whole-object null when `bgp_settings` is unset. The rule is
  #    SKIP ON CONFIG-NULL ONLY, and it is deliberately NOT the symmetric
  #    `state == null || state == config`:
  #      - CONFIG side null (consumer REMOVES `bgp_settings`): skipped, and that is
  #        correct parity. AzureRM's `bgp_settings` is `Optional: true, Computed: true`
  #        (L84-L88, `Optional` L86 / `Computed` L87), so dropping the block produced no diff and no replacement there
  #        either. `tests/.../bgp_settings_removed_passes` pins this.
  #      - STATE side null (gateway created WITHOUT `bgp_settings`, consumer now ADDS
  #        it): `try(state, null)` is null, the config side is a number, and the
  #        comparison FAILS. Adding a ForceNew property is not waved through. This
  #        FAILS CLOSED and is a knowing over-rejection: AzureRM would have compared
  #        the new value against the Computed live one and NOT replaced if they
  #        happened to match, but this module has no live value to compare against
  #        (`response_export_values` is `[]` -- the empty list TFFR4 requires, which
  #        exports nothing -- and the computed-output rule rules out a computed `.output`). The cost is a plan failure the consumer clears by
  #        removing the block again; the alternative cost was an unchecked ForceNew
  #        add. `tests/.../bgp_settings_added_fails` pins this.
  #  * `lower()` is used on the ARM ID only. `isRoutingPreferenceInternet` is a
  #    BOOLEAN and `asn` / `peerWeight` are NUMBERS -- `lower()` on any of them is a
  #    type error, not a safety measure.
  # =========================================================================
  lifecycle {
    # `virtual_hub_id`, ForceNew at L63. ARM IDs are case-insensitive, hence `lower()`
    # on both sides.
    precondition {
      condition     = lower(try(azapi_resource.this[each.key].body.properties.virtualHub.id, "")) == lower(try(local.vpn_gateway_bodies[each.key].properties.virtualHub.id, ""))
      error_message = "`vpn_gateways[\"${each.key}\"].virtual_hub_id` cannot change in place. AzureRM marked `virtual_hub_id` ForceNew (vpn_gateway_resource.go L63) and would have REPLACED this resource -- destroying its `properties.connections` with it. If that is what you want, ask for it deliberately with `terraform apply -replace='<module address>.azapi_resource.this[\"${each.key}\"]'` after accounting for every VPN connection on this gateway; otherwise restore the original `virtual_hub_id`."
    }

    # `routing_preference`, ForceNew at L71. The comparison is on the derived BOOLEAN,
    # so a consumer moving between `null` and an explicit "Microsoft Network" is not a
    # change -- exactly as it was not one under AzureRM's schema default.
    precondition {
      condition     = azapi_resource.this[each.key].body.properties.isRoutingPreferenceInternet == local.vpn_gateway_bodies[each.key].properties.isRoutingPreferenceInternet
      error_message = "`vpn_gateways[\"${each.key}\"].routing_preference` cannot change in place. AzureRM marked `routing_preference` ForceNew (vpn_gateway_resource.go L71) and would have REPLACED this resource -- destroying its `properties.connections` with it. If that is what you want, ask for it deliberately with `terraform apply -replace='<module address>.azapi_resource.this[\"${each.key}\"]'` after accounting for every VPN connection on this gateway; otherwise restore the original `routing_preference`."
    }

    # `bgp_settings.asn`, ForceNew at L94. NUMBER, nested under an object that is a
    # whole-object null when unset -- see the null-handling note above. The `try` is on
    # the STATE side only, so ADDING an asn to a gateway created without one fails.
    precondition {
      condition = (
        try(local.vpn_gateway_bodies[each.key].properties.bgpSettings.asn, null) == null
        || try(azapi_resource.this[each.key].body.properties.bgpSettings.asn, null) == local.vpn_gateway_bodies[each.key].properties.bgpSettings.asn
      )
      error_message = "`vpn_gateways[\"${each.key}\"].bgp_settings.asn` cannot be changed or introduced in place. AzureRM marked `asn` ForceNew (vpn_gateway_resource.go L94) and would have REPLACED this resource -- destroying its `properties.connections` with it. If that is what you want, ask for it deliberately with `terraform apply -replace='<module address>.azapi_resource.this[\"${each.key}\"]'` after accounting for every VPN connection on this gateway; otherwise restore the original `bgp_settings.asn`, or drop the `bgp_settings` block if this gateway was created without one."
    }

    # `bgp_settings.peer_weight`, ForceNew at L100. Same shape, same asymmetry.
    precondition {
      condition = (
        try(local.vpn_gateway_bodies[each.key].properties.bgpSettings.peerWeight, null) == null
        || try(azapi_resource.this[each.key].body.properties.bgpSettings.peerWeight, null) == local.vpn_gateway_bodies[each.key].properties.bgpSettings.peerWeight
      )
      error_message = "`vpn_gateways[\"${each.key}\"].bgp_settings.peer_weight` cannot be changed or introduced in place. AzureRM marked `peer_weight` ForceNew (vpn_gateway_resource.go L100) and would have REPLACED this resource -- destroying its `properties.connections` with it. If that is what you want, ask for it deliberately with `terraform apply -replace='<module address>.azapi_resource.this[\"${each.key}\"]'` after accounting for every VPN connection on this gateway; otherwise restore the original `bgp_settings.peer_weight`, or drop the `bgp_settings` block if this gateway was created without one."
    }
  }
}

# ---------------------------------------------------------------------------
# DAY 2 -- THE TAG WRITER. REG-1'S REMEDY. New in 0.19.0.
#
# 🔴 WHY A SEPARATE RESOURCE AT ALL. `azapi_update_resource` is a MERGE writer, and the merge
# preserves every undeclared key of the LIVE object unconditionally -- `mergeObjectAtPath`'s
# map branch, `utils/json.go` L52-L53, `} else { res[key] = value }`. So a merge writer can add
# a tag and change a tag but can NEVER REMOVE one: dropping a key from `var.tags` produced a
# PUT that silently re-sent the live tag. That was REG-1, a regression against azurerm 4.x,
# where the next apply removed it. A PUT at `Microsoft.Resources/tags/default` REPLACES the
# whole tag set instead, which is exactly what AzureRM's `tags.Expand` assignment did
# (`vpn_gateway_resource.go` L332-L333).
#
# ✅ OBSERVED IN TESTING: this PUT DELETED the `stage` tag from a live VPN gateway, left
# `costCentre` and `purpose` intact, and issued exactly ONE ARM write.
#
# 🔴 WHY `azapi_resource_action` AND NOT `azapi_resource`. `Microsoft.Resources/tags/default`
# is an ARM SINGLETON THAT ALWAYS EXISTS, so `azapi_resource` can never CREATE it
# -- there is nothing to create, only something to PUT. Do not "improve" this back into an
# `azapi_resource`.
#
# 🔴 WHY `depends_on`. Measured twice: the tags PUT drives the resource provider
# but issues NO gateway write -- the activity log for the window shows only
# `Microsoft.Resources/tags/write` and no `Microsoft.Network/vpnGateways/write` -- and the RP
# then sits internally in `Updating` for ~4m30s AFTER Terraform has returned. Two writes racing
# on one parent produce a 409, so this PUT is ordered strictly after the merge writer.
# `depends_on` has no per-instance granularity, so it serialises the whole address rather than
# key-by-key; that is stricter than required and is the only granularity Terraform offers.
#
# ⚠️ OUT-OF-BAND TAGS ARE NOT DETECTED: this resource's Read issues NO GET
# (`azapi_resource_action_resource.go` L424-L435), so a tag set outside Terraform never appears
# as drift -- it is simply overwritten on the next apply. Weaker than AzureRM's drift
# detection, DELIBERATE, and recorded as a named difference in `docs/upgrade-guide.md`.
#
# ⚠️ Its `Delete` is a NO-OP unless `when == "destroy"` (L413-L421), so removing a gateway from
# `var.vpn_gateways` issues no tags DELETE. Harmless here: the full writer deletes the gateway
# and its tags go with it.
#
# The tag expression is the one the merge writer used before this resource existed, unchanged
# except that a null tag map now yields `{}` rather than an absent key -- AzureRM parity,
# `tags.Expand(nil)` returns a pointer to an EMPTY map and never nil.
# ---------------------------------------------------------------------------
resource "azapi_resource_action" "tags" {
  for_each = local.vpn_gateways

  method = "PUT"
  # 🔴 The FULL writer's id, not the merge writer's. `azapi_update_resource` has an `id` of its
  # own that is not the ARM resource ID of the gateway.
  resource_id = "${azapi_resource.this[each.key].id}/providers/Microsoft.Resources/tags/default"
  type        = "Microsoft.Resources/tags@2021-04-01"
  body = {
    properties = {
      tags = try(each.value.tags, null) != null ? each.value.tags : {}
    }
  }
  # ✅ TFFR4 (Severity-MUST, Class-Pattern): declared on every AzAPI resource, "even if empty".
  # Nothing reads this writer's `.output`, and the computed-output rule keeps a computed `.output` out of a
  # module output.
  response_export_values = []
  retry                  = var.retry

  depends_on = [azapi_update_resource.this]
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
  from = azurerm_vpn_gateway.vpn_gateway
  to   = azapi_resource.this
}
