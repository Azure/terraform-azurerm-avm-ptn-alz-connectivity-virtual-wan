# Create the ExpressRoute Gateway in the Virtual Hub.
#
# ============================================================================================
# PROVIDER MIGRATION: azurerm_express_route_gateway -> Azure/azapi.
#
# This module uses the create-only-plus-merge shape (see `docs/MIGRATION-DEVIATIONS.md`): a CREATE-ONLY `azapi_resource` full writer, plus an
# `azapi_update_resource` merge writer for day 2.
#
# 🔴 WHY, SPECIFICALLY FOR THIS TYPE. `Microsoft.Network/expressRouteGateways` carries
# `properties.expressRouteConnections`, and those connections are created by a SEPARATE module
# (`modules/expressroute-gateway-connection`, one `azapi_resource` per connection). A full PUT
# issued from here that omits that array is a deletion of every ExpressRoute connection on the
# gateway. That is not theoretical: the same shape was measured deleting
# `properties.connections` and `properties.natRules` off a vpnGateway.
#
# AzureRM avoided it by LISTing the children and re-attaching them to the payload on both the
# create path (express_route_gateway_resource.go L107-L115, re-attached L129) and the update
# path (L173-L185). This module cannot do that -- Terraform has no read-modify-write primitive
# for a child collection it does not own, and `ExpressRouteConnectionProperties.
# expressRouteCircuitPeering` is REQUIRED by the ARM schema, so the gateway would have to know
# the peering ID of every connection, including ones created out of band by another team. So
# the collection is NOT declared here at all, and the safety comes from the writer never
# PUTting after create instead (see the lifecycle block).
# ============================================================================================

# --------------------------------------------------------------------------------- full writer
# GENESIS. CREATE-ONLY: after create this address must never PUT again, so there is exactly one
# writer against a live gateway and the partial-PUT hazard cannot occur through it.
resource "azapi_resource" "this" {
  for_each = local.expressroute_gateways

  # 🔴 NOT normalised. AzureRM ran `location.Normalize()` (L118) before sending, which
  # lowercases and strips spaces; AzAPI sends the string as configured. Both "uksouth" and
  # "UK South" are accepted by ARM and resolve to the same region, and `location` is ForceNew
  # on `azapi_resource` (ModifyPlan L734), so the only visible consequence is cosmetic drift in
  # state on a gateway adopted from AzureRM whose config spells the region with a space.
  # UNMEASURED against a live adoption.
  location  = each.value.location
  name      = each.value.name
  parent_id = local.expressroute_gateway_parent_ids[each.key]
  type      = var.resource_types.network_express_route_gateways
  body      = local.expressroute_gateway_bodies[each.key]
  # Reproduces AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left
  # unset is absent from the request rather than sent as an explicit JSON null. Null VALUES
  # only -- nothing in `expressroute_gateway_bodies` can currently be null, because AzureRM
  # sent every property unconditionally, but the flag is kept for consistency with the sibling
  # modules and so that a future optional property behaves the same way.
  ignore_body_changes  = length(var.ignore_body_changes.network_express_route_gateways) > 0 ? var.ignore_body_changes.network_express_route_gateways : null
  ignore_null_property = true
  # AzureRM's ForceNew set is `name` (L50), `location` (commonschema.Location(), ForceNew at
  # go-azure-helpers `resourcemanager/commonschema/location.go` L15), `resource_group_name`
  # (commonschema.ResourceGroupName(), ForceNew at `commonschema/resource_group_name.go` L15)
  # and `virtual_hub_id` (L61). The first three map onto AzAPI's own replacement triggers --
  # `name`, `location` and `parent_id` -- and must not be restated. That leaves the hub, which
  # lives in `body` and is handled by a PRECONDITION on the merge writer, not here.
  #
  # 🔴 `replace_triggers_external_values` WAS SET HERE AND HAS BEEN REMOVED. It was not merely
  # redundant, it was ACTIVELY HARMFUL AT ADOPTION. Audited against azapi v2.12.0:
  #   - `internal/services/azapi_resource.go` L286-L288 attaches
  #     `RequiresReplaceIfNotNull()` to the attribute.
  #   - `internal/services/myplanmodifier/planmodifierdynamic/dynamic_requires_replace.go`
  #     computes `resp.RequiresReplace = !planNull && !stateNull`. After an import the prior
  #     state is NULL, so the modifier does NOT request a replacement -- it plans a plain
  #     UPDATE instead.
  #   - The struct field at `azapi_resource.go` L75 carries NO `skip_on:"update"` tag, so that
  #     null-vs-configured difference alone makes `skip.CanSkipExternalRequest` return false
  #     and drives the resource into `["update"]`, which PUTs the stale `state.body`.
  # On THIS type that PUT is the connection deletion described at the top of the file. The
  # attribute therefore bought nothing at adoption (no replacement) and cost everything (a full
  # PUT) -- and it is NOT in the silence contract below, because listing replacement machinery
  # in `ignore_changes` would HIDE a replacement. `response_export_values` below has the same
  # non-skippable shape but IS listed, which is what makes it safe to declare.
  #
  # ============================================================================================
  # ✅ `response_export_values` IS SET, and it is SET DELIBERATELY. AVM spec TFFR4 is
  # Severity-MUST and tagged Class-Pattern, so it binds this module: an AzAPI resource MUST
  # declare the attribute, "even if empty". An earlier change that removed it repo-wide
  # breached that MUST and has been RETRACTED; see `docs/upgrade-guide.md`.
  #
  # WHY `[]` AND NOT A LIST. Nothing downstream reads a response-only property: `outputs.tf`
  # exposes the resource, its ID and a projection built from `.id` plus configuration, and
  # the computed-output rule rules a computed `.output` out of a module output because it goes unknown at
  # plan time and cascades into `(known after apply)` on every consumer.
  #
  # 🔴 IT IS ONLY SAFE BECAUSE `ignore_changes` SILENCES IT. The attribute carries NO `skip_on`
  # tag (`azapi_resource.go` L77), so `skip.CanSkipExternalRequest` (`internal/skip/skip.go`
  # L14-L56, called at `azapi_resource.go` L826) returns false the moment plan and state differ
  # on it. At ADOPTION the imported state holds `null` while the config holds `[]` -- `[]` is
  # not `null`, so that is a difference -- and on its own it would drag the resource into
  # `actions: ["update"]` and PUT the stale `state.body`. On THIS type that PUT is
  # the connection deletion described at the top of the file. The `response_export_values`
  # entry in the `lifecycle.ignore_changes` list below keeps the prior value, so there is no
  # adoption diff and no stale-body PUT. NEVER declare this attribute on an `azapi_resource`
  # without the matching `ignore_changes` entry.
  #
  # 🔴 A FUTURE CHANGE TO THIS EXPORT LIST NEEDS ITS OWN MIGRATION. `ignore_changes` pins the
  # prior value, so editing the list alone is a NO-OP on an already-managed resource: the new
  # value does not take effect without a state operation (`terraform state rm` + re-import, or
  # `-replace`). Treat a change here as a breaking change with an upgrade-guide entry.
  #
  # `avm_azapi_response_export_values_required` fires on ABSENCE and is now satisfied. Note it
  # is configured at `severity = "notice"` in the pinned AVM base tflint config, as are all
  # eight enabled `avm_*` rules -- so a green `avm pr-check` is NOT evidence of MUST compliance
  # and never was. The spec text is the authority, not the linter's exit code.
  # ============================================================================================
  response_export_values = []
  retry                  = var.retry
  # tflint-ignore: avm_azapi_resource_tags_required // the rule wants exactly `tags = var.tags`. These are PER-INSTANCE tags carried on a collection variable, which is the v0.17.2 public API; forcing a single module-wide `var.tags` is a BREAKING interface change. Tracked for the next major.
  tags = try(each.value.tags, {})

  # AzureRM's OWN per-resource defaults, not a shared repository value:
  # `express_route_gateway_resource.go` L39-L44 -- Create 90m (L40), Read 5m (L41),
  # Update 90m (L42), Delete 90m (L43). Defaulted in `variables.tf`; a consumer may still
  # override. `timeouts` is `skip_on:"update"` (azapi_resource.go L81), so a diff on it is
  # state-only and cannot reopen the PUT path -- which is why the block is safe to keep on a
  # create-only writer.
  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  # ⭐ THE ENTIRE PATTERN IS THIS BLOCK. See `local.full_writer_ignored_attributes` above for
  # the audit; `lifecycle` cannot take a variable or a local, so the list is repeated here
  # verbatim and `tests/null_optionals.tftest.hcl` asserts the two are in step.
  #
  # 🔴 THE PRICE, stated where it is paid:
  #   (a) body drift on this resource becomes permanently invisible. Candidate 1 sees drift
  #       only on the paths the MERGE writer declares (`tags`, `properties.
  #       autoScaleConfiguration`, `properties.allowNonVirtualWanTraffic`) and is blind
  #       everywhere else.
  #   (b) the merge writer is ADDITIVE and cannot UN-SET a property. It also could not remove a
  #       TAG, which was REG-1: AzureRM's update assigned the whole tag map (`tags.Expand`,
  #       L200), so removal worked there. ✅ FIXED IN 0.19.0 -- tags left the merge writer's
  #       body and moved to `azapi_resource_action.tags`, which PUTs at
  #       `Microsoft.Resources/tags/default` and REPLACES the whole set. The rest of cost (b),
  #       un-setting a non-tag property, still stands.
  #   (c) `azapi_update_resource.Delete` is an EMPTY FUNCTION, so destroying the merge writer
  #       makes no ARM call and leaves the live value in place.
  #   (d) azapi has no per-property ForceNew, so an ARM-immutable property buried in `body`
  #       is silently ignored rather than replaced. The failure mode moves from "a surprise
  #       destroy" to "a change that does nothing". `virtual_hub_id` is the only such property
  #       on this type and it is caught by the precondition on the merge writer below, which
  #       turns "does nothing" into a hard plan-time error.
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

# -------------------------------------------------------------------------------- merge writer
# DAY 2. GETs the live object and merges, so it never drops an undeclared property
# (`azapi_update_resource.go` :459,480,503,520 + `mergeObjectAtPath` MAP branch,
# `utils/json.go` L58-L59). `properties.expressRouteConnections` is therefore preserved on
# every day-2 write WITHOUT this module ever naming it, which is exactly the property AzureRM
# had to make two extra ARM calls to preserve.
#
# The declared subset is precisely what AzureRM's Update could change. Everything else on the
# gateway is ForceNew, so it could never reach the update path at all:
#   scale_units                    L187-L193  (guarded by d.HasChange)
#   allow_non_virtual_wan_traffic  L195-L197  (guarded by d.HasChange)
#   tags                           L199-L201  (guarded by d.HasChange)
# The `d.HasChange` guards are not reproduced because they are not observable: AzureRM's
# payload started from the live readback (L178), so a guard that did not fire re-sent the live
# value. Declaring the configured value unconditionally sends the same bytes unless the
# consumer actually changed something.
#
# 🔴 `Delete` on this resource type is an EMPTY FUNCTION (:676-678). Removing an entry from
# `expressroute_gateways` destroys the full writer, which DOES delete the gateway, so the
# empty delete is harmless in that direction -- but removing only this resource, or targeting
# it, makes no ARM call at all.
#
# 🔴 There is no `ignore_null_property` on `azapi_update_resource` (its model has no such
# field, `azapi_update_resource.go` L41-L62). Every value below is therefore non-null by
# construction.
resource "azapi_update_resource" "this" {
  for_each = local.expressroute_gateways

  resource_id = azapi_resource.this[each.key].id
  type        = var.resource_types.network_express_route_gateways
  body = {
    # 🔴 `tags` IS DELIBERATELY ABSENT AS OF 0.19.0. It used to sit here, and that is what made
    # REG-1: the merge preserves every undeclared key of the live object unconditionally
    # (`utils/json.go` L52-L53), so a merge writer can never REMOVE a tag. Tags now travel on
    # `azapi_resource_action.tags` below, which REPLACES the whole tag set.
    properties = {
      allowNonVirtualWanTraffic = try(each.value.allow_non_virtual_wan_traffic, null) != null ? each.value.allow_non_virtual_wan_traffic : false
      autoScaleConfiguration = {
        bounds = {
          min = try(each.value.scale_units, null) != null ? each.value.scale_units : 1
        }
      }
    }
  }
  # ✅ TFFR4 (Severity-MUST, Class-Pattern) requires the attribute on every AzAPI resource,
  # "even if empty". `[]` is correct: nothing reads this writer's `.output`, and the computed-output rule
  # keeps a computed `.output` out of a module output. A future change to this list needs its
  # own migration entry, the same as on the full writer above. No `ignore_changes` is needed
  # here: this address is never imported, so it is always created fresh and the null-vs-`[]`
  # adoption difference that the full writer guards against cannot arise.
  response_export_values = []
  retry                  = var.retry

  # Same AzureRM defaults as the full writer. `azapi_update_resource` declares all four
  # timeouts (`azapi_update_resource.go` L290-L294), so all four are forwarded.
  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  # ==========================================================================================
  # THE ForceNew GUARD. This replaces `replace_triggers_external_values` on the full writer;
  # see the note there for why that attribute had to go.
  #
  # WHY IT LIVES ON THE MERGE WRITER. The check has to compare the CONFIGURED value against
  # the value the live gateway was created (or imported) with. `azapi_resource.this[...].body`
  # is exactly that: `lifecycle.ignore_changes = [body]` makes Terraform core substitute the
  # prior state body for the configured one before the provider is ever asked to plan
  # (`node_resource_abstract_instance.go` L976 + L991 at v1.16.2), so on every ordinary plan of
  # an existing gateway that traversal yields the create-/import-time hub, not the new one.
  # Putting the precondition on the full writer would be self-referential; putting it here
  # reads the full writer's planned value, which is what we want.
  #
  # 🔴 `-replace` IS A REAL ESCAPE HATCH, not a slogan. Verified in the same file: when
  # `action.IsReplace()` Terraform re-plans from `origConfigVal` -- the config WITHOUT
  # ignore_changes applied (L1207-L1220; the comment at L1214-L1215 says so in as many words)
  # -- and `forceReplace`, which is what `-replace` sets, reaches `getAction` at L1182. So
  # under `terraform apply -replace=...azapi_resource.this["<key>"]` the planned body carries
  # the NEW hub, this precondition passes, and the gateway is genuinely recreated on it.
  #
  # 🔴 NULL HANDLING: SYMMETRIC AND FAIL-CLOSED, and the choice is deliberate. The obvious
  # shape, `state == null || state == config`, is VACUOUS in the one direction that matters:
  # a state body that does not carry the property would let the configuration ADD a ForceNew
  # value unchecked, which is exactly the silent no-op this block exists to stop. So both sides
  # are collapsed with `try(..., "")` instead and compared unconditionally -- an absent or null
  # hub on EITHER side is a mismatch and fails.
  #
  # That is only safe because neither side can legitimately be absent on this type:
  #   - config side: `virtual_hub_id` is a REQUIRED, non-optional attribute of the
  #     `expressroute_gateways` object, and `variables.tf` additionally regex-validates it as a
  #     full Virtual Hub resource ID, so a null never reaches here.
  #   - state side, create: `properties.virtualHub` is in the create body above, and it is a
  #     non-pointer `VirtualHubId` VALUE in the AzureRM SDK model, so ARM always has it.
  #   - state side, adoption: azapi's `ImportState` sets `state.Body` from
  #     `flattenBody(responseBody, ...)` -- the whole live body, not a filtered one
  #     (`azapi_resource.go` L1408-L1413) -- and every live expressRouteGateway carries
  #     `properties.virtualHub.id`. Subsequent reads then keep it, because `Read` rebuilds the
  #     body as `utils.UpdateObject(requestBody, responseBody, ...)` (L1252), which walks the
  #     prior body's own keys.
  # The residual cost, stated plainly: if some future state body really did lack the property,
  # every plan errors until a human intervenes. That is the correct direction to fail for a
  # guard whose whole job is to stop a silent connection-destroying change.
  #
  # `lower()` on both sides because ARM resource IDs are case-insensitive: a hub ID that
  # differs only in casing is the SAME hub and must not be reported as a change. It is applied
  # to the `try()` RESULT, never to a bare traversal -- `lower(null)` raises rather than
  # returning null, so the naive form dies on any absent value.
  # ==========================================================================================
  lifecycle {
    precondition {
      condition     = lower(try(azapi_resource.this[each.key].body.properties.virtualHub.id, "")) == lower(try(each.value.virtual_hub_id, ""))
      error_message = "expressroute_gateways[\"${each.key}\"].virtual_hub_id cannot be changed in place: this gateway holds \"${try(azapi_resource.this[each.key].body.properties.virtualHub.id, "<absent>")}\" in its create-/import-time body and the configuration now asks for \"${try(each.value.virtual_hub_id, "<absent>")}\". azurerm_express_route_gateway marked virtual_hub_id ForceNew (express_route_gateway_resource.go L61), so AzureRM would have REPLACED this resource -- destroying every ExpressRoute connection attached to it, which this module does not own. Terraform will not do that implicitly here. If you really mean it, use -replace deliberately on the gateway's azapi_resource.this[\"${each.key}\"] address, after confirming the connections owned by modules/expressroute-gateway-connection can be rebuilt."
    }
  }
}

# ----------------------------------------------------------------------------------- tag writer
# DAY 2 -- THE TAG WRITER. REG-1'S REMEDY. New in 0.19.0.
#
# 🔴 WHY A SEPARATE RESOURCE AT ALL. `azapi_update_resource` is a MERGE writer, and the merge
# preserves every undeclared key of the LIVE object unconditionally -- `mergeObjectAtPath`'s map
# branch, `utils/json.go` L52-L53, `} else { res[key] = value }`. So a merge writer can add a tag
# and change a tag but can NEVER REMOVE one: dropping a key from `var.tags` produced a PUT that
# silently re-sent the live tag. That was REG-1, a regression against azurerm 4.x, where the next
# apply removed it. A PUT at `Microsoft.Resources/tags/default` REPLACES the whole tag set
# instead, which is exactly what AzureRM's `tags.Expand` assignment did
# (`express_route_gateway_resource.go` L199-L201).
#
# ✅ OBSERVED IN TESTING: this PUT DELETED the `stage` tag from a live VPN gateway, left
# `costCentre` and `purpose` intact, and issued exactly ONE ARM write.
#
# 🔴 WHY `azapi_resource_action` AND NOT `azapi_resource`. `Microsoft.Resources/tags/default` is
# an ARM SINGLETON THAT ALWAYS EXISTS, so `azapi_resource` can never CREATE it --
# there is nothing to create, only something to PUT. Do not "improve" this back into an
# `azapi_resource`.
#
# 🔴 WHY `depends_on`. Measured twice: the tags PUT drives the resource provider but
# issues NO gateway write -- the activity log for the window shows only
# `Microsoft.Resources/tags/write` -- and the RP then sits internally in `Updating` for ~4m30s
# AFTER Terraform has returned. Two writes racing on one parent produce a 409, so this PUT is
# ordered strictly after the merge writer. `depends_on` has no per-instance granularity, so it
# serialises the whole address rather than key-by-key; that is stricter than required and is the
# only granularity Terraform offers.
#
# ⚠️ OUT-OF-BAND TAGS ARE NOT DETECTED: this resource's Read issues NO GET
# (`azapi_resource_action_resource.go` L424-L435), so a tag set outside Terraform never appears as
# drift -- it is simply overwritten on the next apply. Weaker than AzureRM's drift detection,
# DELIBERATE, and recorded as a named difference in `docs/upgrade-guide.md`.
#
# ⚠️ Its `Delete` is a NO-OP unless `when == "destroy"` (L413-L421), so removing a gateway from
# `var.expressroute_gateways` issues no tags DELETE. Harmless here: the full writer deletes the
# gateway and its tags go with it.
#
# The tag expression is the one the merge writer used before this resource existed, verbatim --
# including the `{}` fallback, which is AzureRM parity: `tags.Expand(nil)` returns a pointer to an
# EMPTY map and never nil.
resource "azapi_resource_action" "tags" {
  for_each = local.expressroute_gateways

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
  from = azurerm_express_route_gateway.express_route_gateway
  to   = azapi_resource.this
}
