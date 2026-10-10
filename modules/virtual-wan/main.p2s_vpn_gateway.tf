# Point to site VPN Gateway.
#
data "azapi_resource" "existing_p2s_gateway" {
  for_each = local.p2s_gateways != null ? local.p2s_gateways : {}

  resource_id      = "${local.p2s_gateway_parent_ids[each.key]}/providers/Microsoft.Network/p2sVpnGateways/${each.value.name}"
  type             = var.resource_types.network_p2s_vpn_gateways
  ignore_not_found = true
  response_export_values = [
    "properties.p2SConnectionConfigurations",
  ]
}

# ---------------------------------------------------------------------------
# TWO RESOURCES, TWO DIFFERENT SHAPES, AND THE DIFFERENCE IS MEASURED.
#
# The choice between "a plain `azapi_resource`" and "candidate 1" is not a style
# call. It is driven by whether the ARM type owns a CHILD COLLECTION inside its
# own body -- a body path holding a collection of resources ARM ALSO exposes as
# a separate child type. A full PUT that does not declare such a path DELETES
# its contents; that is measured, not inferred (measured).
#
# Source: the OpenAPI classifier run at api-version 2025-07-01,
# a captured and classified 2025-07-01 response.
#
#   `p2sVpnGateways`          L126-L134   ZERO child-collection paths.
#                                         virtualHub REFERENCE,
#                                         p2SConnectionConfigurations INLINE,
#                                         vpnGatewayScaleUnit PRIMITIVE,
#                                         vpnServerConfiguration REFERENCE,
#                                         customDnsServers PRIMITIVE,
#                                         isRoutingPreferenceInternet PRIMITIVE,
#                                         provisioningState READONLY,
#                                         vpnClientConnectionHealth READONLY.
#                             -> PLAIN `azapi_resource`. No merge writer, no
#                                `ignore_changes`. A full PUT can never drop a
#                                child because there is no child to drop.
#
#   `vpnServerConfigurations` L108-L124   ONE child-collection path:
#                                         `properties.configurationPolicyGroups`
#                                         -> `Microsoft.Network/vpnServerConfigurations/configurationPolicyGroups`,
#                                         marked `<-- RISK, unresolved` and
#                                         registered `measured: "unmeasured"` in
#                                         `preflight/child_collections.json`.
#                             -> CANDIDATE 1: a create-only `azapi_resource`
#                                plus an `azapi_update_resource` merge writer.
#
# `unmeasured` is deliberately treated as hazardous: shape does not predict
# ARM's behaviour (the isolated measurements falsified that), so the safe shape is taken until
# a post-apply child-count readback says otherwise.
#
# AzureRM parity is cited throughout against terraform-provider-azurerm at
# 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0), files
# `internal/services/network/vpn_server_configuration_resource.go` and
# `internal/services/network/point_to_site_vpn_gateway_resource.go`.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# GENESIS -- THE FULL WRITER FOR THE VPN SERVER CONFIGURATION. CREATE-ONLY.
#
# After create this address must never PUT again, so there is exactly ONE
# writer against a live object and the partial-PUT hazard cannot occur through
# it. Everything that could drag it into an update is silenced by the
# `lifecycle` block below.
# ---------------------------------------------------------------------------
resource "azapi_resource" "p2s_gateway_vpn_server_configuration" {
  for_each = local.p2s_gateway_vpn_server_configurations != null ? local.p2s_gateway_vpn_server_configurations : {}

  # AzureRM sent `location.Normalize(...)` on the wire (L369); this sends the consumer's
  # string verbatim. Not a behaviour difference: azapi declares a SEMANTIC EQUALITY function
  # on this attribute (`azapi_resource.go` L219) and normalises both sides again before
  # deciding to replace, so "UK South" and "uksouth" are the same location to both providers,
  # and ARM accepts either form.
  location            = module.virtual_hubs.location[each.value.virtual_hub_key]
  name                = each.value.name
  parent_id           = local.p2s_gateway_vpn_server_configuration_parent_ids[each.key]
  type                = var.resource_types.network_vpn_server_configurations
  body                = local.p2s_gateway_vpn_server_configuration_bodies[each.key]
  ignore_body_changes = length(var.ignore_body_changes.network_vpn_server_configurations) > 0 ? var.ignore_body_changes.network_vpn_server_configurations : null
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left unset
  # is absent from the request rather than sent as an explicit JSON null. Null VALUES only --
  # `aadAuthenticationParameters` is built as a whole-object null above precisely so that the
  # expander returning nil is reproduced as an ABSENT key, and the three empty arrays are
  # still emitted as `[]`.
  ignore_null_property = true
  #
  # 🔴 NEITHER `replace_triggers_refs` NOR `replace_triggers_external_values` IS SET, AND
  # THAT IS CORRECT HERE RATHER THAN A COMPROMISE.
  #
  # `azurerm_vpn_server_configuration` has exactly THREE ForceNew properties and NONE of them
  # lives in `body`: `name` (L47), `resource_group_name` (L51) and `location` (L53). AzAPI
  # replaces natively on all three -- they map to `name`, `parent_id` and `location`, none of
  # which is in `lifecycle.ignore_changes` below. There is nothing left for a replacement
  # trigger to do. Verified by `grep -n ForceNew vpn_server_configuration_resource.go`, which
  # returns a single hit at L47, and cross-checked against the Update function, which handles
  # every other schema field behind `d.HasChange`.
  #
  # ==========================================================================================
  # ✅ `response_export_values` IS SET, AND IT IS `[]`. AVM spec TFFR4 is Severity-MUST and
  # tagged Class-Pattern, so it binds this module: an AzAPI resource MUST declare the
  # attribute, "even if empty". The repo-wide removal at 3ef4bc8 breached that MUST and
  # has been RETRACTED; see `docs/upgrade-guide.md`.
  #
  # WHY `[]`. Nothing downstream reads a response-only property; `outputs.tf` exposes only
  # `.id`, which AzAPI provides natively, and the computed-output rule keeps a computed `.output` out of a
  # module output.
  #
  # 🔴 IT IS ONLY SAFE BECAUSE `ignore_changes` SILENCES IT. The attribute carries NO
  # `skip_on` tag (`azapi_resource.go` L77), so at ADOPTION the imported state holds `null`
  # while the config holds `[]` -- `[]` is not `null`, so that is a difference -- and it alone
  # would drag the resource into `["update"]` and PUT the stale `state.body`. On
  # THIS resource that PUT drops `properties.configurationPolicyGroups`.
  # `response_export_values` is in `local.vpn_server_configuration_full_writer_ignored_
  # attributes` and in the `lifecycle` block below, which keeps the prior value and removes
  # the diff. NEVER declare this attribute on an `azapi_resource` without that matching
  # `ignore_changes` entry.
  #
  # 🔴 A FUTURE CHANGE TO THIS EXPORT LIST NEEDS ITS OWN MIGRATION. `ignore_changes` pins
  # the prior value, so editing the list is a NO-OP on an already-managed configuration until
  # a state operation (`terraform state rm` + re-import, or `-replace`) is performed.
  #
  # `avm_azapi_response_export_values_required` fires on ABSENCE and is now satisfied. It runs
  # at `severity = "notice"` under the pinned AVM base tflint config, as do all eight enabled
  # `avm_*` rules, so a green `avm pr-check` is NOT evidence of MUST compliance.
  # ==========================================================================================
  response_export_values = []
  retry                  = local.retry
  # Write-only. See `p2s_gateway_vpn_server_configuration_client_root_certificates` above,
  # including the Terraform 1.11 floor this introduces for consumers who set a certificate.
  # `sensitive_body_version` is deliberately NOT set; a null is the detecting AND the safe
  # regime.
  sensitive_body = length(local.p2s_gateway_vpn_server_configuration_client_root_certificates[each.key]) > 0 ? {
    properties = { vpnClientRootCertificates = local.p2s_gateway_vpn_server_configuration_client_root_certificates[each.key] }
  } : null
  # Preserved from the AzureRM resource. `locals.tf` already falls back to `var.tags` when the
  # per-configuration `tags` is null, so this is the effective map either way. AzureRM turned
  # a null into `tags: {}` via `tags.Expand`; AzAPI omits the key. Same resulting tag set, one
  # fewer key on the wire.
  # tflint-ignore: avm_azapi_resource_tags_required // the rule wants exactly `tags = var.tags`. These are PER-INSTANCE tags carried on a collection variable, which is the v0.17.2 public API; forcing a single module-wide `var.tags` is a BREAKING interface change. Tracked for the next major.
  tags = each.value.tags

  timeouts {
    create = local.timeouts.network_vpn_server_configurations.create
    delete = local.timeouts.network_vpn_server_configurations.delete
    read   = local.timeouts.network_vpn_server_configurations.read
    update = local.timeouts.network_vpn_server_configurations.update
  }

  # ⭐ THE ENTIRE PATTERN IS THIS BLOCK. Without it, any later change to `body`, `tags` or
  # `sensitive_body` makes THIS resource issue a full PUT of the configured body -- which has
  # no `properties.configurationPolicyGroups` in it. With it, this address goes inert after
  # create and the merge writer below is the only writer.
  #
  # 🔴 THE PRICE, stated where it is paid, and narrower than "drift is invisible forever":
  # this resource sees drift on exactly the paths the MERGE writer declares
  # (`properties.vpnAuthenticationTypes`, `properties.aadAuthenticationParameters`,
  # `properties.vpnClientRootCertificates` and `tags`) and is blind on every other path --
  # including `vpnProtocols`, `vpnClientIpsecPolicies` and `vpnClientRevokedCertificates`,
  # which it sets at create and then stops watching.
  #
  # 🔴🔴 THE LIST IS `local.vpn_server_configuration_full_writer_ignored_attributes`,
  # ENUMERATED THERE. `lifecycle` cannot take a variable or a local, so it is repeated here
  # verbatim. `tests/p2s_vpn_gateway.tftest.hcl` asserts the local's contents; the two must be
  # kept in step BY HAND, and the audit comment on the local is where the reasoning lives.
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
# DAY 2 -- THE MERGE WRITER FOR THE VPN SERVER CONFIGURATION.
#
# GETs the live object and merges into it, so a property it does not declare is
# PRESERVED rather than dropped (`utils.MergeObject` -> `mergeObjectAtPath`,
# `utils/json.go` L39-L105; the map branch at L45-L58 is the one that keeps
# `properties.configurationPolicyGroups`).
#
# 🔴 NO PRECONDITIONS, AND THE EMPTY LIST IS A MEASURED RESULT, NOT AN OVERSIGHT.
#
# The candidate-1 hazard a precondition guards against is a BODY field that
# AzureRM marked ForceNew: with `ignore_changes = [body]` on the full writer,
# such a field would be changed IN PLACE by this merge writer where AzureRM
# would have destroyed and recreated the resource, silently.
# `azurerm_vpn_server_configuration` HAS NO SUCH FIELD.
# `grep -n ForceNew internal/services/network/vpn_server_configuration_resource.go`
# at 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa returns ONE line:
#
#   L47   `name`
#
# plus two more that are ForceNew by construction rather than by a literal in
# this file:
#
#   L51   `resource_group_name`   `commonschema.ResourceGroupName()`
#   L53   `location`              `commonschema.Location()`
#
# All three are RESOURCE-LEVEL, not body-level: they map to `name`, `parent_id`
# and `location` on `azapi_resource`, all three of which AzAPI replaces on
# natively and NONE of which is in the full writer's `ignore_changes` list. A
# consumer who renames the configuration, moves it to another resource group or
# changes its region gets a REPLACEMENT out of AzAPI, exactly as they got one
# out of AzureRM. Cross-checked against `resourceVPNServerConfigurationUpdate`
# (L462-L580): every other schema field on the resource is handled there behind
# a `d.HasChange` guard, which is only possible for a field that is NOT
# ForceNew.
#
# So there is no in-place change this writer can make that AzureRM would have
# refused, and a precondition here would be dead code advertising a guarantee
# it does not provide. If a future api-version or provider version adds a
# ForceNew body field, this is the block it belongs on.
#
# 🔴 Its `Delete` is an EMPTY FUNCTION (`azapi_update_resource.go` L676-L678):
# destroying this resource makes NO ARM call and silently leaves the live change
# in place. That is a teardown hazard, not a day-2 one, and it belongs in the
# upgrade guide.
# ---------------------------------------------------------------------------
resource "azapi_update_resource" "p2s_gateway_vpn_server_configuration" {
  for_each = local.p2s_gateway_vpn_server_configurations != null ? local.p2s_gateway_vpn_server_configurations : {}

  # Never a constructed ID: taking it off the full writer is what ORDERS the two writers and
  # what guarantees the configuration exists before the merge PUT is attempted.
  resource_id = azapi_resource.p2s_gateway_vpn_server_configuration[each.key].id
  type        = var.resource_types.network_vpn_server_configurations
  body        = local.p2s_gateway_vpn_server_configuration_update_bodies[each.key]
  # ✅ TFFR4 (Severity-MUST, Class-Pattern) requires the attribute on every AzAPI resource,
  # "even if empty". `[]` is correct: nothing reads this writer's `.output`, and the computed-output rule
  # keeps a computed `.output` out of a module output. A future change to this list needs its
  # own migration, the same as on the full writer. No `ignore_changes` here -- this address is
  # never imported, so it is always created fresh and the null-vs-`[]` adoption difference
  # cannot arise.
  response_export_values = []
  retry                  = local.retry
  # The certificate data has to be supplied to BOTH writers. The full writer sends it at
  # create; the merge writer is the only address that can send it afterwards, because
  # `sensitive_body` is in the full writer's `ignore_changes` list. Rotating the certificate
  # in place -- same `name`, new `public_cert_data` -- therefore flows through here.
  sensitive_body = length(local.p2s_gateway_vpn_server_configuration_client_root_certificates[each.key]) > 0 ? {
    properties = { vpnClientRootCertificates = local.p2s_gateway_vpn_server_configuration_client_root_certificates[each.key] }
  } : null

  # `azapi_update_resource` has no create/delete of its own against ARM: its "create" is the
  # first merge PUT and its `Delete` is a no-op, so both ARM-facing operations take AzureRM's
  # UPDATE timeout and the read takes its read timeout
  # (`vpn_server_configuration_resource.go` L39 and L38). `delete` is not set because no
  # request is ever issued -- and `AzapiUpdateResourceModel` carries no delete timeout either.
  timeouts {
    create = local.timeouts.network_vpn_server_configurations.update
    read   = local.timeouts.network_vpn_server_configurations.read
    update = local.timeouts.network_vpn_server_configurations.update
  }
}

# ---------------------------------------------------------------------------
# DAY 2 -- THE TAG WRITER FOR THE VPN SERVER CONFIGURATION. REG-1'S REMEDY.
# New in 0.19.0.
#
# 🔴 WHY A SEPARATE RESOURCE AT ALL. `azapi_update_resource` is a MERGE writer,
# and the merge preserves every undeclared key of the LIVE object
# unconditionally -- `mergeObjectAtPath`'s map branch, `utils/json.go`
# L52-L53, `} else { res[key] = value }`. So a merge writer can add a tag and
# change a tag but can NEVER REMOVE one: dropping a key from
# `p2s_gateway_vpn_server_configurations[*].tags` produced a PUT that silently
# re-sent the live tag. That was REG-1, observed in testing, a regression against
# azurerm 4.x, whose Update assigned the WHOLE tag map (`tags.Expand`,
# L571-L573). A PUT at `Microsoft.Resources/tags/default` REPLACES the whole
# tag set instead, which is what that assignment did.
#
# ✅ OBSERVED IN TESTING: this PUT DELETED the `stage` tag from a live
# VPN gateway, left `costCentre` and `purpose` intact, and issued exactly ONE
# ARM write.
#
# 🔴 THIS ADDRESS TAGS THE VPN SERVER CONFIGURATION, NOT THE P2S GATEWAY.
# `azapi_resource.p2s_gateway` below is a PLAIN `azapi_resource` whose `tags`
# argument drives a whole-object PUT on every change -- neither `body` nor
# `tags` is in its `ignore_changes` list -- so tag REMOVAL already worked
# there and it needs no action of its own. `tests/p2s_vpn_gateway.tftest.hcl`
# asserts that premise so it cannot regress silently. Do NOT add a second
# action for the gateway.
#
# 🔴 WHY `azapi_resource_action` AND NOT `azapi_resource`.
# `Microsoft.Resources/tags/default` is an ARM SINGLETON THAT ALWAYS EXISTS
#, so `azapi_resource` can never CREATE it -- there is nothing to
# create, only something to PUT. Do not "improve" this back into an
# `azapi_resource`.
#
# 🔴 WHY `depends_on`. Measured twice: the tags PUT drives the
# resource provider but issues NO write against the parent -- the activity log
# for the window shows only `Microsoft.Resources/tags/write` -- and the RP then
# sits internally in `Updating` for ~4m30s AFTER Terraform has returned. Two
# writes racing on one parent produce a 409. `depends_on` has no per-instance
# granularity, so it serialises the whole address rather than key-by-key; that
# is stricter than required and is the only granularity Terraform offers.
#
# ⚠️ OUT-OF-BAND TAGS ARE NOT DETECTED: this resource's Read issues NO GET
# (`azapi_resource_action_resource.go` L424-L435), so a tag set outside
# Terraform never appears as drift -- it is simply overwritten on the next
# apply. Weaker than AzureRM's drift detection, DELIBERATE, and recorded as a
# named difference in `docs/upgrade-guide.md`.
#
# ⚠️ Its `Delete` is a NO-OP unless `when == "destroy"` (L413-L421), so
# removing an entry issues no tags DELETE. Harmless here: the full writer
# deletes the configuration and its tags go with it.
#
# The tag expression is the one the merge writer used before this resource
# existed, with one deliberate change: a NULL now yields `{}` rather than
# omitting the key, because this body is not a merge and an omitted key would
# mean "PUT no tags at all". `{}` is also AzureRM parity -- `tags.Expand(nil)`
# returns a pointer to an EMPTY map and never nil.
# ---------------------------------------------------------------------------
resource "azapi_resource_action" "p2s_gateway_vpn_server_configuration_tags" {
  for_each = local.p2s_gateway_vpn_server_configurations != null ? local.p2s_gateway_vpn_server_configurations : {}

  method = "PUT"
  # 🔴 The FULL writer's id, not the merge writer's. `azapi_update_resource`
  # has an `id` of its own that is not the ARM resource ID of the
  # configuration.
  resource_id = "${azapi_resource.p2s_gateway_vpn_server_configuration[each.key].id}/providers/Microsoft.Resources/tags/default"
  type        = "Microsoft.Resources/tags@2021-04-01"
  body = {
    properties = {
      tags = try(each.value.tags, null) != null ? each.value.tags : {}
    }
  }
  # ✅ TFFR4 (Severity-MUST, Class-Pattern): declared on every AzAPI resource,
  # "even if empty". Nothing reads this writer's `.output`, and the computed-output rule
  # keeps a computed `.output` out of a module output.
  response_export_values = []
  # `local.retry`, not `var.retry`: every resource this module owns takes the
  # module-local retry (`locals.retry.tf`), and only submodule cascades are
  # handed `var.retry` verbatim for TFFR7 neutrality.
  retry = local.retry

  depends_on = [azapi_update_resource.p2s_gateway_vpn_server_configuration]
}

# ---------------------------------------------------------------------------
# THE POINT-TO-SITE VPN GATEWAY. A PLAIN `azapi_resource`, ONE WRITER, FULL PUT
# ON EVERY CHANGE -- and that is SAFE here, which is not true of the four
# gateway-shaped resources in this repo that use candidate 1.
#
# `p2sVpnGateways` has ZERO CHILD-COLLECTION paths at api-version 2025-07-01
# (classifier L126-L134). Its only two INLINE/REFERENCE hazards,
# `p2SConnectionConfigurations` and `virtualHub`/`vpnServerConfiguration`, are
# all DECLARED by the body above, so a full PUT rewrites exactly what this
# module owns and drops nothing it does not.
#
# The consequence is worth stating positively, because candidate 1 gives it up:
# THIS RESOURCE SEES DRIFT ON EVERY PATH IT DECLARES, on every plan, and an
# out-of-band change to the scale unit, the address pool or the DNS servers
# shows up as a diff instead of being silently tolerated.
# ---------------------------------------------------------------------------
resource "azapi_resource" "p2s_gateway" {
  for_each = local.p2s_gateways != null ? local.p2s_gateways : {}

  location            = module.virtual_hubs.location[each.value.virtual_hub_key]
  name                = each.value.name
  parent_id           = local.p2s_gateway_parent_ids[each.key]
  type                = var.resource_types.network_p2s_vpn_gateways
  body                = local.p2s_gateway_bodies[each.key]
  ignore_body_changes = length(var.ignore_body_changes.network_p2s_vpn_gateways) > 0 ? var.ignore_body_changes.network_p2s_vpn_gateways : null
  # Matches AzureRM's nil-pointer/omitempty serialisation: an optional the consumer left unset
  # is absent from the request rather than sent as an explicit JSON null.
  ignore_null_property = true
  # ⭐ FULL ForceNew PARITY, and it WORKS on this resource where it could not on a candidate-1
  # one. `replace_triggers_refs` compares `state.Body` against `plan.Body`
  # (`azapi_resource.go` L737-L775); under candidate 1 `ignore_changes = [body]` makes
  # `plan.body` equal `state.body` by construction, so the comparison can never differ. There
  # is no `ignore_changes` here, so the comparison is real.
  #
  # `grep -n ForceNew internal/services/network/point_to_site_vpn_gateway_resource.go` at
  # 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa returns FOUR lines:
  #
  #   L51    `name`                                  -> AzAPI `name`, native replacement
  #   L62    `virtual_hub_id`                        -> properties.virtualHub.id, below
  #   L69    `vpn_server_configuration_id`           -> properties.vpnServerConfiguration.id, below
  #   L174   `routing_preference_internet_enabled`   -> properties.isRoutingPreferenceInternet, below
  #
  # plus `resource_group_name` (L55, `commonschema.ResourceGroupName()`) and `location`
  # (L57, `commonschema.Location()`), which map to `parent_id` and `location` and are native
  # replacement triggers on `azapi_resource`. So all six are covered.
  #
  # ⚠️ `properties.isRoutingPreferenceInternet` is currently INERT, because the body hardcodes
  # it to `false` -- this module exposes no input for `routing_preference_internet_enabled`,
  # so the value can never change and the trigger can never fire. It is listed anyway: the
  # trigger is correct the day that input is added, and leaving it out would make adding the
  # input a silent loss of ForceNew parity rather than a no-op.
  #
  # ⚠️ NOT REPRODUCED, and reported rather than hidden: nothing marks
  # `properties.p2SConnectionConfigurations[*].name` as a replacement trigger. It is not
  # ForceNew on AzureRM either (the whole `connection_configuration` block is handled behind
  # `d.HasChange` at L265-L267), so this is parity, not a gap -- noted only because a
  # connection configuration looks like a child resource and is not one.
  replace_triggers_refs = [
    "properties.isRoutingPreferenceInternet",
    "properties.virtualHub.id",
    "properties.vpnServerConfiguration.id",
  ]
  # ✅ `response_export_values` IS SET, AND IT IS `[]`, per TFFR4 (Severity-MUST,
  # Class-Pattern). See the fuller note on the VPN server configuration above. `outputs.tf`
  # exposes only `.id`, which AzAPI provides natively, and a computed `.output` in a module
  # output is a day-2 blast-radius bug, so the empty list is the right value.
  #
  # ⛔ NO `lifecycle { ignore_changes = [response_export_values] }` -- WITHDRAWN, AND IT MUST
  # NOT COME BACK. This site is "armed": `ignore_body_changes`/`ignore_null_property` leave
  # `body` free, so `skip.CanSkipExternalRequest` is false and a PUT does occur. Pinning
  # `response_export_values` here reproduces BUG 3: the pin freezes `plan.Output` to the stale
  # null-derived default projection while the writer still PUTs at adoption, so the applied
  # output disagrees with the planned one -> "Error: Provider produced inconsistent result
  # after apply" on first apply after upgrade. Do not copy this withdrawal onto a Class A
  # (fully silent) writer -- there, pinning costs nothing extra since no PUT happens, and BUG 3
  # cannot fire either way.
  #
  # 🔴 This also means `tags` and `body` were never in scope for a lifecycle ignore list on
  # this resource -- there is none. A changed tag map drives a whole-object PUT and REMOVING a
  # tag works, which is precisely what the four candidate-1 merge writers could not do (REG-1).
  # `tests/tags_writer.tftest.hcl` applies twice -- two tags, then one -- to prove the removal
  # still reaches the resource, so this cannot regress silently.
  response_export_values = []
  retry                  = local.retry
  # `locals.tf` already falls back to `var.tags` when the per-gateway `tags` is null.
  # tflint-ignore: avm_azapi_resource_tags_required // the rule wants exactly `tags = var.tags`. These are PER-INSTANCE tags carried on a collection variable, which is the v0.17.2 public API; forcing a single module-wide `var.tags` is a BREAKING interface change. Tracked for the next major.
  tags = each.value.tags

  timeouts {
    create = local.timeouts.network_p2s_vpn_gateways.create
    delete = local.timeouts.network_p2s_vpn_gateways.delete
    read   = local.timeouts.network_p2s_vpn_gateways.read
    update = local.timeouts.network_p2s_vpn_gateways.update
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
  from = azurerm_vpn_server_configuration.p2s_gateway_vpn_server_configuration
  to   = azapi_resource.p2s_gateway_vpn_server_configuration
}

moved {
  from = azurerm_point_to_site_vpn_gateway.p2s_gateway
  to   = azapi_resource.p2s_gateway
}
