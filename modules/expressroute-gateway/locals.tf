locals {
  expressroute_gateways = var.expressroute_gateways != null ? var.expressroute_gateways : {}

  # AzAPI addresses the parent by resource ID; AzureRM took a name plus an implicit
  # subscription from the provider block (`d.Get("resource_group_name")` +
  # `meta.Account.SubscriptionId`, L85 and L91). This is a provider migration in place, so the
  # module's public variable shape is preserved and the ID is reconstructed here instead: the
  # subscription comes from `virtual_hub_id`, because an ExpressRoute Gateway must live in the
  # same subscription as the Virtual Hub it is parented on. `variables.tf` validates the shape
  # of that ID, so the index below is checked rather than assumed.
  expressroute_gateway_parent_ids = {
    for key, value in local.expressroute_gateways :
    key => format("/subscriptions/%s/resourceGroups/%s", split("/", value.virtual_hub_id)[2], value.resource_group_name)
  }

  # AzureRM's Create builds `parameters.Properties` as a struct literal with NO conditionals at
  # all -- every field below was sent on EVERY create, via `pointer.To(d.Get(...))`, so each
  # schema default reached ARM whether or not the consumer set it. A migrated gateway has to
  # send the same literals or the first apply after the upgrade would reset live values.
  # Verified against express_route_gateway_resource.go at
  # 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0):
  #   allow_non_virtual_wan_traffic  L71-L75    Optional, Default false, sent at L120
  #   scale_units                    L65-L69    Required, IntBetween(1,10), sent at L123
  #   virtual_hub_id                 L58-L63    Required, ForceNew,        sent at L126-L128
  #   tags                           L77        commonschema.Tags(),       sent at L131
  #
  # 🔴 `autoScaleConfiguration` sets `bounds.min` ONLY (L121-L125). There is no `max` in the
  # payload and there never was, so ARM picks the upper bound. Adding `max` here would be a
  # behaviour change on every existing gateway, not a completion of the object.
  #
  # 🔴 `tags.Expand` of an empty map returns a non-nil pointer to an empty map, so AzureRM sent
  # `"tags": {}` rather than omitting the key. `try(each.value.tags, {})` reproduces that.
  expressroute_gateway_bodies = {
    for key, value in local.expressroute_gateways : key => {
      properties = {
        # `pointer.To(d.Get("allow_non_virtual_wan_traffic").(bool))`, L120. Unconditional, and
        # `variables.tf` carries the same `false` default, so the literal matches AzureRM's.
        allowNonVirtualWanTraffic = try(value.allow_non_virtual_wan_traffic, null) != null ? value.allow_non_virtual_wan_traffic : false

        # L121-L125. The struct literal is unconditional, so `bounds.min` is always present.
        autoScaleConfiguration = {
          bounds = {
            min = try(value.scale_units, null) != null ? value.scale_units : 1
          }
        }

        # L126-L128. `VirtualHub` is a VALUE, not a pointer, in the SDK model, so it could
        # never be omitted.
        virtualHub = { id = value.virtual_hub_id }

        # 🔴🔴 `expressRouteConnections` IS DELIBERATELY ABSENT. THIS IS A PARITY DEVIATION
        # AND IT IS THE POINT OF THE WHOLE SHAPE.
        #
        # AzureRM DID send it: L107 LISTs the gateway's connections, L112-L115 converts them,
        # L129 attaches them to the payload. On a genuine create the list is empty, and
        # `convertConnectionsToGatewayConnections` returns a pointer to an EMPTY SLICE rather
        # than nil (L273-L277), so AzureRM's create request literally carried
        # `"expressRouteConnections": []`.
        #
        # At a genuine create, `[]` and absent are indistinguishable -- there are no
        # connections yet either way -- so nothing is lost on the create path. What IS gained
        # is that the declared body never contains an instruction to empty that array. The
        # create-only lifecycle below is the primary guarantee; omitting the key is the
        # belt-and-braces second one, so that if the guarantee were ever broken the stale body
        # is at least not an explicit "delete all connections".
        #
        # Day 2 is handled by `azapi_update_resource` below, which GETs the live object and
        # merges, and therefore preserves this array without ever naming it.
      }
    }
  }

  # ==========================================================================================
  # THE FULL WRITER'S SILENCE CONTRACT. Audited against azapi v2.12.0
  # `internal/services/azapi_resource.go` (`AzapiResourceModel`, L58-L91). THIS LIST IS THE
  # MODULE'S SAFETY PROPERTY, not a style choice, and it was ENUMERATED rather than guessed.
  #
  # WHY IT EXISTS. `azapi_resource`'s update path (L826) is guarded by
  # `skip.CanSkipExternalRequest(plan, state, "update")` (`internal/skip/skip.go` L14-L55),
  # which reflects over EVERY field of `AzapiResourceModel` and returns false -- meaning "do
  # the full PUT of `state.body`" -- the moment any field WITHOUT a `skip_on:"update"` tag
  # differs between plan and state. So the create-only guarantee holds only if every such
  # field is pinned. `ignore_changes = [body, tags]` is NOT sufficient: testing measured a
  # gateway driven into `["update"]` by `response_export_values` (L77) and `timeouts` (L81),
  # not by the body at all.
  #
  # NON-SKIPPABLE and CONFIGURABLE and NOT ForceNew -> all 16 listed below.
  #   body                        L59      sensitive_body              L60
  #   sensitive_body_version      L61      identity                    L63
  #   ignore_body_changes         L64      ignore_casing               L65
  #   ignore_missing_property     L66      ignore_null_property        L67
  #   list_unique_id_property     L68      ignore_other_items_in_list  L69
  #   locks                       L71      response_export_values      L77
  #   schema_validation_enabled   L79      tags                        L80
  #   update_headers              L85      update_query_parameters     L86
  #
  # NON-SKIPPABLE but DELIBERATELY NOT LISTED, with the reason:
  #   id L62, output L73                 -- Computed-only. Not configurable, so
  #                                         `ignore_changes` cannot name them.
  #   name L72 (RequiresReplace L189), parent_id L74 (L198), type L82,
  #   location L70 (ModifyPlan L734)     -- ForceNew. A change REPLACES rather than updates,
  #                                         so the create-only guarantee is not what protects
  #                                         them, and listing them would HIDE a replacement.
  #   replace_triggers_external_values L75, replace_triggers_refs L76
  #                                      -- replacement machinery. Same reasoning. NEITHER is
  #                                         set on this module; the ForceNew body property is
  #                                         guarded by a precondition on the MERGE writer
  #                                         instead. See the note above that writer.
  #
  # SKIPPABLE (`skip_on:"update"`), so a diff on them is STATE-ONLY with no ARM call. Not
  # listed, and they must not be -- silencing them would cost real behaviour for no safety
  # gain: retry L78, timeouts L81, create_headers L83, create_query_parameters L84,
  # delete_headers L87, delete_query_parameters L88, read_headers L89, read_query_parameters
  # L90. Measured in testing: the full writer's only diff was `timeouts` and `arm_call` was
  # false.
  #
  # 🔴 A future azapi bump can add a 17th entry. Re-run the audit against
  # `AzapiResourceModel` when the version pin in `terraform.tf` moves.
  # ==========================================================================================
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
