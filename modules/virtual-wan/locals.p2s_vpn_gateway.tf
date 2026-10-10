locals {
  # AzAPI addresses the parent by resource ID; AzureRM took a resource group NAME plus an
  # implicit subscription from the provider block. Both of these resources were parented on
  # the hub's resource group, so the ID is composed the same way `main.tf` composes
  # `local.resource_group_resource_id` -- from `data.azapi_client_config.current` and the
  # configured name. The name is read back off the hub module, which sources it from
  # CONFIGURATION rather than from ARM, so this stays known at plan time.
  p2s_gateway_parent_ids = {
    for key, value in(local.p2s_gateways != null ? local.p2s_gateways : {}) :
    key => "/subscriptions/${data.azapi_client_config.current.subscription_id}/resourceGroups/${module.virtual_hubs.resource_group_name[value.virtual_hub_key]}"
  }
  p2s_gateway_vpn_server_configuration_parent_ids = {
    for key, value in(local.p2s_gateway_vpn_server_configurations != null ? local.p2s_gateway_vpn_server_configurations : {}) :
    key => "/subscriptions/${data.azapi_client_config.current.subscription_id}/resourceGroups/${module.virtual_hubs.resource_group_name[value.virtual_hub_key]}"
  }

  # ------------------------------------------------------------------ vpnServerConfigurations
  # AzureRM's Create builds `VpnServerConfigurationProperties` as a STRUCT LITERAL
  # (`vpn_server_configuration_resource.go` L336-L343) and every one of the four list fields
  # is fed by an expander that returns a pointer to a slice that is EMPTY rather than nil:
  #
  #   VpnAuthenticationTypes       L338  always sent, Required on the schema
  #   AadAuthenticationParameters  L337  expandVpnServerConfigurationAADAuthentication L603-L606
  #                                      returns NIL for an empty list -- the one field that
  #                                      can legitimately be absent
  #   VpnClientRootCertificates    L339  expandVpnServerConfigurationClientRootCertificates
  #                                      L644-L656, `make(..., 0)` then `return &slice`
  #   VpnClientRevokedCertificates L340  expandVpnServerConfigurationClientRevokedCertificates
  #                                      L684-L696, same shape
  #   VpnClientIPsecPolicies       L341  expandVpnServerConfigurationIPSecPolicies L720-L737,
  #                                      same shape
  #   VpnProtocols                 L342  expandVpnServerConfigurationVPNProtocols L888-L896,
  #                                      same shape
  #
  # So `vpnClientRevokedCertificates: []`, `vpnClientIpsecPolicies: []` and `vpnProtocols: []`
  # were part of EVERY create request AzureRM sent, even though this module exposes no input
  # for any of them, and they stay part of this one. Dropping them would be a silent
  # behaviour change on the first apply after the provider migration.
  #
  # 🔴 `vpnProtocols` is Optional AND Computed on the AzureRM schema (L256-L264). AzureRM sent
  # `[]` at create and then, because `d.HasChange("vpn_protocols")` was never true for a
  # consumer of THIS module, never touched it again -- ARM's computed value was left alone
  # from that point on. The merge writer below reproduces that by NOT declaring it. See the
  # note there; declaring it as `[]` would WIPE the live protocol list.
  #
  # 🔴 RADIUS IS NOT REPRODUCED AND CANNOT BE. `var.p2s_gateway_vpn_server_configurations`
  # exposes no `radius` block, so `expandVpnServerConfigurationRadius` always returned nil for
  # a consumer of this module and the whole `if supportsRadius` branch (L353-L366) was dead.
  # `radiusServerSecret`, `radiusServerAddress`, `radiusServers`,
  # `radiusClientRootCertificates` and `radiusServerRootCertificates` are therefore absent
  # here for the same reason they were absent before: there is no input that produces them.
  # Setting `vpn_authentication_types = ["Radius"]` failed under AzureRM with
  # "`radius` must be specified..." (L355) and now fails at ARM instead. Unchanged behaviour,
  # different error text.
  #
  # `publicCertData` is NOT in this body. It is lifted into `sensitive_body`; see
  # `p2s_gateway_vpn_server_configuration_client_root_certificates` below.
  p2s_gateway_vpn_server_configuration_bodies = {
    for key, value in(local.p2s_gateway_vpn_server_configurations != null ? local.p2s_gateway_vpn_server_configurations : {}) : key => {
      properties = {
        vpnAuthenticationTypes = value.vpn_authentication_types
        # The only nil-able one. Emitted as a whole-object null rather than as `{}` so that
        # `ignore_null_property` prunes the KEY: `ignore_null_property` removes null VALUES but
        # leaves an emptied object behind, and `"aadAuthenticationParameters": {}` is not the
        # same request as no key at all.
        aadAuthenticationParameters = try(value.azure_active_directory_authentication, null) != null ? {
          aadAudience = value.azure_active_directory_authentication.audience
          aadIssuer   = value.azure_active_directory_authentication.issuer
          aadTenant   = value.azure_active_directory_authentication.tenant
        } : null
        # Name only. The certificate data is write-only, see `sensitive_body` on the writers.
        vpnClientRootCertificates = try(value.client_root_certificate, null) != null ? [
          { name = value.client_root_certificate.name }
        ] : []
        # No input on this module; AzureRM still sent all three as empty arrays.
        vpnClientRevokedCertificates = []
        vpnClientIpsecPolicies       = []
        vpnProtocols                 = []
      }
    }
  }

  # ------------------------------------------------------------------ the certificate data
  # 🔴 `public_cert_data` IS CARRIED IN `sensitive_body`, WITH `sensitive_body_version` LEFT
  # NULL -- the same treatment `shared_key` gets in `modules/site-to-site-gateway-connection`.
  #
  #
  # ⚠️ AND IT IS A DELIBERATE DEPARTURE FROM AZURERM, NOT PARITY. `public_cert_data` is NOT
  # marked `Sensitive` on the AzureRM schema -- the ONLY `Sensitive: true` in
  # `vpn_server_configuration_resource.go` is at L205, on `radius.server.secret`, which this
  # module does not expose. AzureRM stored the certificate data in plain state and printed it
  # in plans. Moving it to `sensitive_body` is strictly more conservative, and the cost is
  # stated where it is paid:
  #
  #   1. Supplying `client_root_certificate` now requires TERRAFORM 1.11 OR LATER, because
  #      `sensitive_body` is write-only. Leaving it unset does not. `terraform.tf` still
  #      declares `required_version = "~> 1.7"`, so a consumer on 1.7-1.10 who sets a root
  #      certificate gets a Terraform-level error rather than a quiet downgrade.
  #   2. The value leaves state, so `terraform state show` no longer returns it.
  #
  # AzAPI merges `sensitive_body` into `body` before the request is built, matching list items
  # by their `name` property (`utils/json.go` `mergeObjectAtPath` L79-L104, identifier key
  # defaulted to `"name"` by `listIdentifierKeyForPath` L270-L279). The body above already
  # carries the matching `name`, so the two halves rejoin on the wire.
  #
  # ⭐ `sensitive_body_version` IS DELIBERATELY NOT SET AND NOT EXPOSED AS AN INPUT. Measured
  # for `shared_key` in testing: with the version NULL, azapi hashes the sensitive body into
  # Terraform private state and detects rotation on its own; with a version SET and not
  # bumped, a later apply that changes anything else sends an EMPTY array for the path and
  # wipes the live list. The null regime is both the detecting one and the safe one. The full
  # write-up is in `modules/site-to-site-gateway-connection/main.tf`.
  p2s_gateway_vpn_server_configuration_client_root_certificates = {
    for key, value in(local.p2s_gateway_vpn_server_configurations != null ? local.p2s_gateway_vpn_server_configurations : {}) : key => (
      try(value.client_root_certificate, null) != null ? [
        {
          name           = value.client_root_certificate.name
          publicCertData = value.client_root_certificate.public_cert_data
        }
      ] : []
    )
  }

  # ------------------------------------------------------------------ the day-2 subset
  # Exactly the properties AzureRM's Update was able to change in place, and no others.
  # `resourceVPNServerConfigurationUpdate` (L462-L580) is a GET-then-modify-then-PUT over
  # `payload := existing.Model`, with every field behind `d.HasChange`:
  #
  #   azure_active_directory_authentication  L487-L489 -> properties.aadAuthenticationParameters
  #   client_revoked_certificate             L491-L493 -> no input on this module
  #   client_root_certificate                L495-L497 -> properties.vpnClientRootCertificates
  #   ipsec_policy                           L499-L501 -> no input on this module
  #   vpn_protocols                          L503-L505 -> no input on this module
  #   vpn_authentication_types               L529-L531 -> properties.vpnAuthenticationTypes
  #   radius                                 L533-L558 -> no input on this module
  #   tags                                   L571-L573 -> tags
  #
  # The four rows with no input on this module are NOT declared here. That is parity, not an
  # omission: `d.HasChange` could never be true for them, so AzureRM never wrote them after
  # create either. It is also the SAFE choice, and for `vpnProtocols` it is the only safe one:
  #
  # 🔴 DECLARING `vpnProtocols: []` HERE WOULD WIPE THE LIVE PROTOCOL LIST. `mergeObjectAtPath`
  # short-circuits on an empty array -- `if len(oldValue) == 0 || len(newArr) == 0 { return
  # newArr }` (`utils/json.go` L62-L64) -- so an empty new array REPLACES the live one rather
  # than merging into it. `vpnProtocols` is Computed, so ARM populates it; sending `[]` on
  # every day-2 edit would clear it every time.
  #
  # Everything else on this resource is ForceNew and so could never appear in an AzureRM
  # update: `name` (L47), `resource_group_name` (L51, `commonschema.ResourceGroupName()`) and
  # `location` (L53, `commonschema.Location()`). All three are native replacement triggers on
  # `azapi_resource` and none of them is in the ignore list below, so parity holds without any
  # extra machinery. See the "NO PRECONDITIONS" note on the merge writer.
  # 🔴 `tags` IS DELIBERATELY ABSENT FROM THIS BODY AS OF 0.19.0. It used to be spliced in
  # below with `try(value.tags, null) != null ? { tags = value.tags } : {}` -- carried as a
  # BODY KEY because `azapi_update_resource` has no `tags` attribute -- and that is what made
  # REG-1: the merge is additive PER KEY and preserves every undeclared key of the live object
  # unconditionally (`utils/json.go` L52-L53), so it could add and change a tag but never
  # REMOVE one, while AzureRM's Update assigned the WHOLE tag map (`tags.Expand`, L571-L573).
  # Observed in testing on the vpnGateway. ✅ FIXED IN 0.19.0: tags now travel on
  # `azapi_resource_action.p2s_gateway_vpn_server_configuration_tags` in `main.p2s_vpn_gateway.tf`,
  # which
  # PUTs at `Microsoft.Resources/tags/default` and REPLACES the whole tag set. There is exactly
  # one tag writer per address after create, and it is not this one. The `merge()` wrapper is
  # kept because the splice was its only other argument and a future conditional key would want
  # it back.
  p2s_gateway_vpn_server_configuration_update_bodies = {
    for key, value in(local.p2s_gateway_vpn_server_configurations != null ? local.p2s_gateway_vpn_server_configurations : {}) : key => merge(
      {
        properties = {
          vpnAuthenticationTypes = value.vpn_authentication_types
          # 🔴 A NULL HERE IS LOAD-BEARING AND IS NOT A BUG. AzureRM assigned the expander's
          # result unconditionally under `d.HasChange`, and the expander returns NIL when the
          # block is removed (L603-L606); the field carries `omitempty`, so the key vanished
          # from the readback model AzureRM then PUT, and ARM cleared it. Reproduced here by
          # sending an explicit null: `mergeObjectAtPath` returns `new` immediately when `new
          # == nil` (`utils/json.go` L40-L42), and `azapi_update_resource` has NO
          # `ignore_null_property` attribute to prune it (`AzapiUpdateResourceModel`,
          # `azapi_update_resource.go` -- the field does not exist on the model), so the null
          # reaches ARM and clears the parameters. Omitting the key instead would PRESERVE
          # stale AAD settings on a live gateway after the consumer deleted the block, which
          # is the opposite of what AzureRM did.
          aadAuthenticationParameters = try(value.azure_active_directory_authentication, null) != null ? {
            aadAudience = value.azure_active_directory_authentication.audience
            aadIssuer   = value.azure_active_directory_authentication.issuer
            aadTenant   = value.azure_active_directory_authentication.tenant
          } : null
          # Name only; the data rides in `sensitive_body` on the writer. An unset certificate
          # sends `[]`, which CLEARS the live list (`utils/json.go` L62-L64) -- exactly what
          # AzureRM's unconditional assignment of an empty expander slice did.
          #
          # 🔴 KNOWN DEVIATION, REG-1 CLASS: RENAMING the certificate does not remove the old
          # one. With a non-empty list on both sides the merge takes the IDENTIFIER branch
          # (`utils/json.go` L79-L104) and every live item the new list does not name is
          # APPENDED BACK (L96: `res = append(res, oldItem)`). AzureRM assigned the whole list
          # and so dropped the old entry. Here `{name = "old"}` live plus `{name = "new"}`
          # configured yields BOTH certificates on the gateway, the plan shows only the new
          # one, and the apply succeeds. Rotating a certificate IN PLACE -- same `name`, new
          # `public_cert_data` -- is unaffected and merges correctly. Removing the block
          # entirely is also unaffected, because of the empty-array short-circuit above.
          vpnClientRootCertificates = try(value.client_root_certificate, null) != null ? [
            { name = value.client_root_certificate.name }
          ] : []
        }
      },
    )
  }

  # =========================================================================
  # THE FULL WRITER'S SILENCE CONTRACT. Enumerated against azapi v2.12.0
  # `internal/services/azapi_resource.go`, struct `AzapiResourceModel` L58-L91,
  # re-verified against the v2.12.0 tag. THIS LIST IS THE MODULE'S
  # SAFETY PROPERTY, not a style choice, and `tests/p2s_vpn_gateway.tftest.hcl`
  # asserts its contents so a silent edit to the `lifecycle` block below fails
  # the test run.
  #
  # WHY IT EXISTS. `azapi_resource`'s update path is guarded by
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
  #   type                        L82
  #   update_headers              L85
  #   update_query_parameters     L86
  #
  # NON-SKIPPABLE but DELIBERATELY NOT LISTED, with the reason:
  #   id L62, output L73          Computed-only. Not configurable, so they
  #                               cannot diff from config and `ignore_changes`
  #                               cannot name them.
  #   name L72, parent_id L74, location L70
  #                               ForceNew. A change REPLACES rather than
  #                               updates, so the create-only guarantee is not
  #                               what protects them, and listing them would
  #                               HIDE a replacement. These three are ALSO the
  #                               entire ForceNew surface of
  #                               `azurerm_vpn_server_configuration` -- see the
  #                               "NO PRECONDITIONS" note on the merge writer.
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
  # A future azapi bump can add an 18th entry. The list was enumerated, not
  # guessed, and this comment is where the next change starts.
  # =========================================================================
  # tflint-ignore: terraform_unused_declarations // referenced only from comments and from the `lifecycle.ignore_changes` literal below, which HCL will not let a local drive. It is the audited silence-contract list and is deliberately kept next to the thing it documents.
  vpn_server_configuration_full_writer_ignored_attributes = [
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

  # ------------------------------------------------------------------ p2sVpnGateways
  # AzureRM's Create builds `P2SVpnGatewayProperties` as a STRUCT LITERAL
  # (`point_to_site_vpn_gateway_resource.go` L215-L226) -- every field is sent with
  # `pointer.To(d.Get(...))`, unconditionally, whatever the consumer passed, and the schema
  # defaults were applied before Create ran. A migrated gateway has to send the same literals
  # or the first apply after the upgrade would silently reset live values:
  #
  #   isRoutingPreferenceInternet  L217  from `routing_preference_internet_enabled`,
  #                                      schema L171-L176, ForceNew, Default false. This
  #                                      module exposes no input for it, so the literal
  #                                      AzureRM sent was always FALSE.
  #   p2SConnectionConfigurations  L218  expandPointToSiteVPNGatewayConnectionConfiguration
  #                                      L378-L412
  #   vpnServerConfiguration.id    L219  from `vpn_server_configuration_id`, Required
  #   virtualHub.id                L222  from `virtual_hub_id`, Required
  #   vpnGatewayScaleUnit          L225  from `scale_unit`, Required
  #   tags                         L227  `tags.Expand(...)`, carried on the resource's own
  #                                      `tags` argument rather than in `body`
  #
  # `customDnsServers` is the ONE guarded field: L228-L231 sends it only when the expanded
  # slice is non-empty, so an unset `dns_servers` means an ABSENT key, not `[]`.
  #
  # Inside each connection configuration (L406-L411):
  #   vpnClientAddressPool.addressPrefixes   always, from `address_prefixes`
  #   enableInternetSecurity                 always, `pointer.To(raw[...].(bool))`; the schema
  #                                          defaults it to false (L155-L159) and this module
  #                                          exposes no input, so the literal is FALSE
  #   routingConfiguration                   expandPointToSiteVPNGatewayConnectionRouteConfiguration
  #                                          L414-L418 returns NIL for an empty `route` list,
  #                                          and this module exposes no `route` input. A fresh
  #                                          gateway therefore has no routing key to send;
  #                                          however, AzureRM's Optional+Computed read could
  #                                          carry existing ARM routing into a later update.
  #                                          The data read below preserves that existing value.
  p2s_gateway_existing_routing_configurations = {
    for key, value in(local.p2s_gateways != null ? local.p2s_gateways : {}) : key => try(
      one([
        for configuration in try(data.azapi_resource.existing_p2s_gateway[key].output.properties.p2SConnectionConfigurations, []) :
        configuration.properties.routingConfiguration
        if configuration.name == value.connection_configuration.name && try(configuration.properties.routingConfiguration, null) != null
      ]),
      null,
    )
  }
  p2s_gateway_preserved_routing_configurations = {
    for key, routing_configuration in local.p2s_gateway_existing_routing_configurations : key => routing_configuration != null ? merge(
      routing_configuration,
      try(routing_configuration.vnetRoutes, null) != null ? {
        vnetRoutes = {
          for property, property_value in routing_configuration.vnetRoutes : property => property_value
          if property != "bgpConnections"
        }
      } : {},
    ) : null
  }

  p2s_gateway_bodies = {
    for key, value in(local.p2s_gateways != null ? local.p2s_gateways : {}) : key => {
      properties = merge(
        {
          isRoutingPreferenceInternet = false
          p2SConnectionConfigurations = [
            {
              # ARM spells this `p2SConnectionConfigurations`, with a capital S. Easy to get
              # wrong; confirmed against the classifier output L128 and against
              # `spec-2025-07-01/virtualWan.json`.
              name = value.connection_configuration.name
              properties = merge(
                {
                  vpnClientAddressPool   = { addressPrefixes = value.connection_configuration.vpn_client_address_pool.address_prefixes }
                  enableInternetSecurity = false
                },
                local.p2s_gateway_preserved_routing_configurations[key] != null ? {
                  routingConfiguration = local.p2s_gateway_preserved_routing_configurations[key]
                } : {},
              )
            }
          ]
          vpnServerConfiguration = { id = azapi_resource.p2s_gateway_vpn_server_configuration[value.p2s_gateway_vpn_server_configuration_key].id }
          virtualHub             = { id = module.virtual_hubs.resource[value.virtual_hub_key].id }
          vpnGatewayScaleUnit    = value.scale_unit
        },
        # `dns_servers` is `optional(list(string))` with no default, so it is NULL when
        # omitted. `length(try(x, []))` would NOT catch that -- `try` only catches ERRORS, and
        # `length(null)` fails with "argument must not be null". That exact mistake cost an
        # long-running apply in an earlier test, so the null is tested explicitly.
        length(try(value.dns_servers, null) != null ? value.dns_servers : []) > 0 ? {
          customDnsServers = value.dns_servers
        } : {},
      )
    }
  }
}
