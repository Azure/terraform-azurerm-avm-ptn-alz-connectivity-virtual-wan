locals {
  vpn_gateways = var.vpn_gateways != null ? var.vpn_gateways : {}

  # AzAPI addresses the parent by resource ID; AzureRM took a resource group NAME plus an
  # implicit subscription from the provider block. This is a provider migration in place,
  # so the module's public variable shape is preserved and the ID is reconstructed here:
  # the subscription comes from `virtual_hub_id`, because a vpnGateway must live in the
  # same subscription as the virtual hub it is parented on. `variables.tf` validates the
  # shape of that ID, so the index below is checked rather than assumed.
  vpn_gateway_parent_ids = {
    for key, value in local.vpn_gateways :
    key => format("/subscriptions/%s/resourceGroups/%s", split("/", value.virtual_hub_id)[2], value.resource_group_name)
  }

  # AzureRM's schema applies defaults BEFORE the Create func runs, and Create then builds
  # `VpnGatewayProperties` as a STRUCT LITERAL -- every field is sent with
  # `pointer.To(d.Get(...))`, unconditionally, whatever the consumer passed. A migrated
  # gateway therefore has to send the same literals or the first apply after the upgrade
  # would silently reset live values. Verified against
  # `internal/services/network/vpn_gateway_resource.go` at
  # 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0):
  #
  #   enableBgpRouteTranslationForNat  L252   from `bgp_route_translation_for_nat_enabled`,
  #                                           schema L78-L82, Default false
  #   bgpSettings                      L253   expandVPNGatewayBGPSettings, see below
  #   virtualHub.id                    L254   from `virtual_hub_id`, Required
  #   vpnGatewayScaleUnit              L257   from `scale_unit`, schema L191-L196, Default 1
  #   isRoutingPreferenceInternet      L258   `d.Get("routing_preference") == "Internet"`,
  #                                           schema L67-L76, Default "Microsoft Network",
  #                                           so the literal AzureRM sent when unset is FALSE
  #   tags                             L260   `tags.Expand(...)`, carried on the resource's
  #                                           own `tags` argument rather than in `body`
  #
  # 🔴 `expandVPNGatewayBGPSettings` (L450-L460) returns NIL for an empty list and otherwise
  # returns ONLY `{Asn, PeerWeight}`. It never populates `BgpPeeringAddresses`. The custom
  # BGP IPs are not part of the create payload at all -- see the merge writer below. The nil
  # is reproduced as a null rather than as `bgpSettings: {}`, because `ignore_null_property`
  # prunes null VALUES but leaves an emptied object behind, and `"bgpSettings": {}` is not
  # the same request as no `bgpSettings` at all.
  vpn_gateway_bodies = {
    for key, value in local.vpn_gateways : key => {
      properties = {
        enableBgpRouteTranslationForNat = try(value.bgp_route_translation_for_nat_enabled, null) != null ? value.bgp_route_translation_for_nat_enabled : false
        bgpSettings = try(value.bgp_settings, null) != null ? {
          asn        = value.bgp_settings.asn
          peerWeight = value.bgp_settings.peer_weight
        } : null
        virtualHub                  = { id = value.virtual_hub_id }
        vpnGatewayScaleUnit         = try(value.scale_unit, null) != null ? value.scale_unit : 1
        isRoutingPreferenceInternet = (try(value.routing_preference, null) != null ? value.routing_preference : "Microsoft Network") == "Internet"
      }
    }
  }

  # ------------------------------------------------------------------ custom BGP IPs
  # AzureRM could not send these on the create PUT and said so in a comment at L268-L269:
  # *"customer cannot provide this field during create. This will be set with default value
  # once gateway is created. it could only be updated"*. So Create issues a SECOND request
  # (L270-L302): GET the gateway back, overwrite
  # `properties.bgpSettings.bgpPeeringAddresses[0].customBgpIpAddresses` and/or `[1]`, and
  # PUT the whole readback model. Update does the same thing behind `d.HasChange`
  # (L343-L354). Both are GET-then-modify-then-PUT -- which is precisely what
  # `azapi_update_resource` is, so the second PUT moves onto the merge writer and the
  # sequence a consumer sees is the same one AzureRM produced.
  #
  # 🔴 THE TWO-ELEMENT ARRAY IS LOAD-BEARING. `mergeObjectAtPath` (azapi v2.12.0
  # `utils/json.go` L62-L77) looks for an identifier property on the array items, defaulting
  # to `"name"` (`listIdentifierKeyForPath`, L270-L279). `bgpPeeringAddresses` items have no
  # `name`, so `hasIdentifier` is false and the merge falls through to the POSITIONAL branch
  # (L70-L77) -- which merges element-by-element ONLY when `len(old) == len(new)`, and
  # otherwise returns the new array verbatim, replacing the live one.
  #
  # ✅ MEASURED: ARM returns exactly two peering addresses on a provisioned vpnGateway,
  # `ipconfigurationId` "Instance0" and "Instance1", in that order --
  # a captured live 2025-07-01 response. So a two-element array is the
  # only shape that merges positionally, which is exactly the `[0]` / `[1]` indexing
  # AzureRM did at L346 and L352.
  #
  # An instance the consumer did not configure contributes an EMPTY OBJECT, not a null.
  # The map branch of the merge (L45-L58) keeps every key of the live item that the new item
  # does not mention, so `{}` means "leave this instance exactly as ARM has it" -- AzureRM's
  # `if len(input) > 0` guard at L344/L350, reproduced. A null would NOT be equivalent:
  # `mergeObjectAtPath` returns `new` immediately when `new == nil` (L40-L42), so a null
  # would blank the live item, and `azapi_update_resource` has no `ignore_null_property`
  # to prune it.
  #
  # `merge({}, [...]...)` rather than a `cond ? {...} : {}` conditional: a conditional whose
  # branches are objects with different attribute sets is unified into a MAP, and the
  # unification is only safe while every branch has at most one attribute. Splatting a
  # zero-or-one element list into `merge` has no unification step at all.
  vpn_gateway_bgp_peering_addresses = {
    for key, value in local.vpn_gateways : key => [
      merge({}, [
        for address in(try(value.bgp_settings.instance_0_bgp_peering_address, null) != null ? [value.bgp_settings.instance_0_bgp_peering_address] : []) :
        { customBgpIpAddresses = address.custom_ips }
      ]...),
      merge({}, [
        for address in(try(value.bgp_settings.instance_1_bgp_peering_address, null) != null ? [value.bgp_settings.instance_1_bgp_peering_address] : []) :
        { customBgpIpAddresses = address.custom_ips }
      ]...),
    ]
  }

  # AzureRM only made the second create PUT when at least one instance block was present
  # (L285: `if len(input0) > 0 || len(input1) > 0`), and only touched an instance whose
  # block was present. With neither set, `bgpSettings` is omitted from the merge body
  # entirely so the live `asn`, `peerWeight`, `bgpPeeringAddress` and both peering
  # addresses are preserved untouched.
  vpn_gateway_bgp_peering_addresses_configured = {
    for key, value in local.vpn_gateways :
    key => try(value.bgp_settings.instance_0_bgp_peering_address, null) != null || try(value.bgp_settings.instance_1_bgp_peering_address, null) != null
  }

  # ------------------------------------------------------------------ the day-2 subset
  # Exactly the properties AzureRM's Update was able to change in place, and no others.
  # `resourceVPNGatewayUpdate` (L307-L362) is a GET-then-modify-then-PUT over
  # `model := *existing.Model`, with every field behind `d.HasChange`:
  #
  #   scale_unit                            L329-L331 -> properties.vpnGatewayScaleUnit
  #   tags                                  L332-L334 -> tags
  #   bgp_route_translation_for_nat_enabled L335-L337 -> properties.enableBgpRouteTranslationForNat
  #   bgp_settings.0.instance_*             L343-L354 -> properties.bgpSettings.bgpPeeringAddresses
  #
  # Everything else on this resource is ForceNew and so could never appear in an AzureRM
  # update: `name` (L52), `virtual_hub_id` (L63), `routing_preference` (L71), `location`
  # (`commonschema.Location()`), and the per-block `bgp_settings.asn` (L94) and
  # `bgp_settings.peer_weight` (L100). They are declared by the full writer at create and
  # deliberately absent here -- declaring them on a merge writer would turn an AzureRM
  # replacement into a silent in-place change.
  #
  # 🔴 `tags` IS DELIBERATELY ABSENT FROM THIS BODY AS OF 0.19.0. It used to be spliced in
  # here with `try(value.tags, null) != null ? { tags = value.tags } : {}`, and that is what
  # made REG-1: a merge writer preserves every undeclared key of the live object
  # (`utils/json.go` L52-L53, unconditional), so it can add and change a tag but can NEVER
  # remove one. Tags now travel on `azapi_resource_action.tags` in `main.tf`, which PUTs at
  # `Microsoft.Resources/tags/default` and REPLACES the whole tag set. There is exactly one
  # tag writer per address after create, and it is not this one.
  vpn_gateway_update_bodies = {
    for key, value in local.vpn_gateways : key => {
      properties = merge(
        {
          vpnGatewayScaleUnit             = try(value.scale_unit, null) != null ? value.scale_unit : 1
          enableBgpRouteTranslationForNat = try(value.bgp_route_translation_for_nat_enabled, null) != null ? value.bgp_route_translation_for_nat_enabled : false
        },
        local.vpn_gateway_bgp_peering_addresses_configured[key] ? {
          bgpSettings = { bgpPeeringAddresses = local.vpn_gateway_bgp_peering_addresses[key] }
        } : {},
      )
    }
  }

  # =========================================================================
  # THE FULL WRITER'S SILENCE CONTRACT. Enumerated against azapi v2.12.0
  # `internal/services/azapi_resource.go`, struct `AzapiResourceModel` L58-L91,
  # re-verified. THIS LIST IS THE MODULE'S SAFETY PROPERTY, not a
  # style choice, and `tests/null_optionals.tftest.hcl` asserts its contents so
  # a silent edit to the `lifecycle` block below fails the test run.
  #
  # WHY IT EXISTS. `azapi_resource`'s update path (L826) is guarded by
  # `skip.CanSkipExternalRequest(plan, state, "update")`, which reflects over
  # EVERY field of the model and returns FALSE -- meaning "do the full PUT of
  # `state.body`" -- the moment any field WITHOUT a `skip_on:"update"` tag
  # differs between plan and state (`internal/skip/skip.go` L14-L55). So the
  # create-only guarantee holds only if every such field is pinned.
  #
  # 🔴 `ignore_changes = [body, tags]` IS NOT SUFFICIENT. Testing measured a
  # gateway going to `actions: ["update"]` driven by `response_export_values`
  # and `timeouts`, not by the body at all.
  #
  # NON-SKIPPABLE and CONFIGURABLE and NOT ForceNew -> listed:
  #   body                        L59
  #   sensitive_body              L60
  #   sensitive_body_version      L61
  #   identity                    L63
  #   ignore_body_changes         L64
  #   ignore_casing               L65
  #   ignore_missing_property     L66
  #   ignore_null_property        L67
  #   list_unique_id_property     L68
  #   ignore_other_items_in_list  L69
  #   locks                       L71
  #   response_export_values      L77   <- the one that caused the failure
  #   schema_validation_enabled   L79
  #   tags                        L80
  #   update_headers              L85
  #   update_query_parameters     L86
  #
  # NON-SKIPPABLE but DELIBERATELY NOT LISTED, with the reason:
  #   id L62, output L73          Computed-only. Not configurable, so they
  #                               cannot diff from config and `ignore_changes`
  #                               cannot name them.
  #   name L72 (RequiresReplace L189), parent_id L74 (L198), type L82,
  #   location L70 (ModifyPlan L734)
  #                               ForceNew. A change REPLACES rather than
  #                               updates, so the create-only guarantee is not
  #                               what protects them, and listing them would
  #                               HIDE a replacement.
  #   replace_triggers_external_values L75, replace_triggers_refs L76
  #                               Replacement machinery. Neither is set on this
  #                               resource -- see the note on the writer.
  #
  # SKIPPABLE (`skip_on:"update"`), so a diff on them is STATE-ONLY with no ARM
  # call. Not listed, and they must not be -- silencing them would cost real
  # behaviour for no safety gain:
  #   retry L78, timeouts L81, create_headers L83, create_query_parameters L84,
  #   delete_headers L87, delete_query_parameters L88, read_headers L89,
  #   read_query_parameters L90.
  #
  # 🔴 `timeouts` being skippable is why this module keeps its timeouts block
  # and why an ADOPTION plan still reads `["update"]`: the plan diff is real,
  # the ARM call is not. Measured in testing: the full writer's only diff was
  # `timeouts` and `arm_call` was false.
  #
  # A future azapi bump can add a 17th entry. The list was enumerated, not
  # guessed, and this comment is where the next change starts.
  # =========================================================================
  # tflint-ignore: terraform_unused_declarations // referenced only from comments and from the `lifecycle.ignore_changes` literal below, which HCL will not let a local drive. It is the audited silence-contract list and is deliberately kept next to the thing it documents.
  full_writer_ignored_attributes = [
    "body",
    "identity",
    "ignore_body_changes",
    "ignore_casing",
    "ignore_missing_property",
    "ignore_null_property",
    "ignore_other_items_in_list",
    "list_unique_id_property",
    "locks",
    "response_export_values",
    "schema_validation_enabled",
    "sensitive_body",
    "sensitive_body_version",
    "tags",
    "type",
    "update_headers",
    "update_query_parameters",
  ]
}
