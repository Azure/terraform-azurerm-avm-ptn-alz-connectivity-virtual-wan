# ---------------------------------------------------------------------------
# AzureRM parity references used throughout this module.
#
#   FW   = hashicorp/terraform-provider-azurerm v4.81.0, commit
#          5782a75422c68a0d0804ac16d97dcaf3df5ee2fa,
#          internal/services/firewall/firewall_resource.go
#   DIAG = same commit,
#          internal/services/monitor/monitor_diagnostic_setting_resource.go
#
# Every `FW Lnn` / `DIAG Lnn` below was read out of those two files at that
# commit. Nothing here is inferred from the provider docs.
# ---------------------------------------------------------------------------

locals {
  # Per-resource timeout fallbacks.
  #
  # `var.timeouts` is the flat four-attribute TFFR7 object, because that is what the parent
  # module cascades through unchanged. It carries no inline defaults; each attribute is null
  # when unset and falls back HERE, per resource, to the AzureRM default of the resource it
  # replaced. That is the same arrangement as `local.timeouts` in
  # `modules/virtual-wan/locals.timeouts.tf`, and the same reason: a single blanket number
  # would have been measurably wrong, since the diagnostic setting's delete is 60m and the
  # firewall's is 90m.
  #
  # Every fallback below is transcribed from `hashicorp/terraform-provider-azurerm` v4.81.0 at
  # commit 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa. Nothing is inferred from the docs.
  timeouts = {
    # azapi_resource.fw + azapi_update_resource.fw -> azurerm_firewall
    #   FW L46-51: Create 90m, Read 5m, Update 90m, Delete 90m.
    #
    # ⚠️ Both writers share this one entry, exactly as before. The merge writer has no delete
    # of its own worth timing -- `azapi_update_resource.Delete` is an empty function
    # (`azapi_update_resource.go` L676-678) -- but the attribute is set on it regardless, which
    # is what the previous per-resource-keyed variable did too.
    network_azure_firewalls = {
      create = var.timeouts.create != null ? var.timeouts.create : "90m"
      read   = var.timeouts.read != null ? var.timeouts.read : "5m"
      update = var.timeouts.update != null ? var.timeouts.update : "90m"
      delete = var.timeouts.delete != null ? var.timeouts.delete : "90m"
    }
    # azapi_resource.diagnostic_setting -> azurerm_monitor_diagnostic_setting
    #   DIAG L43-48: Create 30m, Read 5m, Update 30m, Delete 60m.
    #   🔴 The delete is 60m, NOT the firewall's 90m. This asymmetry is the whole reason the
    #   fallbacks are per resource rather than one shared object.
    insights_diagnostic_settings = {
      create = var.timeouts.create != null ? var.timeouts.create : "30m"
      read   = var.timeouts.read != null ? var.timeouts.read : "5m"
      update = var.timeouts.update != null ? var.timeouts.update : "30m"
      delete = var.timeouts.delete != null ? var.timeouts.delete : "60m"
    }
  }
}

locals {
  # Unchanged from the AzureRM-era module. The key is "<hub key>-<setting key>".
  flattened_diagnostic_settings = {
    for v in
    flatten([
      for hub_key, diag_map in var.diagnostic_settings : [
        for setting_key, setting_val in diag_map : {
          value                  = setting_val
          virtual_hub_key        = hub_key
          diagnostic_setting_key = setting_key
        }
      ]
      ]) : "${v.virtual_hub_key}-${v.diagnostic_setting_key}" => {
      data                   = v.value
      virtual_hub_key        = v.virtual_hub_key
      diagnostic_setting_key = v.diagnostic_setting_key
    }
  }

  # `var.firewalls` has no `nullable = false`, so `null` is reachable and the
  # AzureRM-era `for_each` guarded against it. Preserved verbatim.
  all_firewalls = var.firewalls != null ? var.firewalls : {}

  # A firewall with a non-empty `ip_configurations` map is in customer-IP mode and is written by
  # `module.customer_firewalls`; every other firewall is in managed-IP mode. `local.firewalls` is the
  # managed-IP subset, which is what every writer in `main.tf` iterates.
  customer_mode = { for key, firewall in local.all_firewalls : key => length(firewall.ip_configurations) > 0 }
  firewalls     = { for key, firewall in local.all_firewalls : key => firewall if !local.customer_mode[key] }

  # AzAPI addresses the parent by resource ID; AzureRM took a name plus an
  # implicit subscription from the provider block
  # (`commonids.NewResourceGroupID(subscriptionId, resourceGroupName)`). This is
  # a provider migration in place, so the module's public variable shape is
  # preserved and the ID is reconstructed here instead: the subscription comes
  # from `virtual_hub_id`, because a vHub firewall must live in the same
  # subscription as the hub it is attached to. `variables.tf` validates the
  # shape of that ID -- the same check AzureRM made at FW L206
  # (`ValidateFunc: virtualwans.ValidateVirtualHubID`) -- so the index below is
  # checked rather than assumed. Matches the precedent in
  # `modules/site-to-site-vpn-site/main.tf`.
  #
  # 🟡 DEVIATION, recorded: if a consumer ever pointed `virtual_hub_id` at a hub
  # in a DIFFERENT subscription from the `azurerm` provider block, AzureRM put
  # the firewall in the provider's subscription and this puts it in the hub's.
  # Cross-subscription vHub firewalls are not a supported ARM topology, so the
  # case is believed unreachable; it is not verified.
  firewall_parent_ids = {
    for key, value in local.firewalls :
    key => format("/subscriptions/%s/resourceGroups/%s", split("/", value.virtual_hub_id)[2], value.resource_group_name)
  }

  # =========================================================================
  # FIREWALL BODY. Bug-for-bug against `FW` Create/Update (one function,
  # `resourceFirewallCreateUpdate`, FW L236-408).
  # =========================================================================

  # FW L279-282. `zones.ExpandUntyped(d.Get("zones").(*schema.Set).List())`
  # then `if len(zones) > 0 { parameters.Zones = &zones }` -- an EMPTY zone
  # list leaves `Zones` nil, and a nil pointer with `omitempty` is omitted
  # from the request entirely. It is NOT sent as `[]`.
  #
  # The schema is `commonschema.ZonesMultipleOptionalForceNew()` (FW L227), a
  # TypeSet of TypeString, so AzureRM de-duplicated and coerced the module's
  # `list(number)` to strings. `toset()` reproduces the de-duplication; the
  # resulting order is lexicographic rather than AzureRM's set-hash order,
  # which ARM does not care about and which nothing in this module compares.
  firewall_zones = {
    for key, value in local.firewalls :
    key => tolist(toset([for zone in(value.zones != null ? value.zones : []) : tostring(zone)]))
  }

  # FW L212: `public_ip_count` carries `Default: 1`, so AzureRM sent 1 whenever
  # the module left `vhub_public_ip_count` null. The variable is typed
  # `optional(string, null)`, which is the AzureRM-era public shape and is
  # preserved; `tonumber` reproduces the TypeInt coercion the SDK did.
  firewall_public_ip_counts = {
    for key, value in local.firewalls :
    key => value.vhub_public_ip_count != null ? tonumber(value.vhub_public_ip_count) : 1
  }

  # FW L325-337. `Sku` is allocated lazily inside two `!= ""` guards, so an
  # empty `sku_name` AND an empty `sku_tier` leave `Sku` nil and omit the whole
  # `sku` object. Either one alone omits just that member.
  firewall_skus = {
    for key, value in local.firewalls : key => merge(
      value.sku_name != null && value.sku_name != "" ? { name = value.sku_name } : {},
      value.sku_tier != null && value.sku_tier != "" ? { tier = value.sku_tier } : {},
    )
  }

  firewall_bodies = {
    for key, value in local.firewalls : key => merge(
      # FW L279-282: top-level `zones`, omitted when empty.
      length(local.firewall_zones[key]) > 0 ? { zones = local.firewall_zones[key] } : {},
      {
        properties = merge(
          {
            # FW L272 + L594-637. `expandFirewallIPConfigurations` opens with
            # `make([]AzureFirewallIPConfiguration, 0)` (FW L595) and closes
            # with `return &ipConfigs` (FW L636) -- ALWAYS a non-nil pointer.
            # A non-nil pointer to an empty slice still serialises under
            # `omitempty`, so AzureRM sent a literal `"ipConfigurations": []`
            # on every create of a vHub firewall. Reproduced, not tidied away.
            ipConfigurations = []

            # FW L273. `pointer.To(AzureFirewallThreatIntelMode(d.Get(...)))`
            # is UNCONDITIONAL and this module never exposed
            # `threat_intel_mode`, so the zero value went on the wire as
            # `"threatIntelMode": ""`. Verified acceptable to the azapi client
            # schema: the bicep type for this property (bicep-types-az,
            # network/microsoft.network/2025-07-01, node #1568) is a UnionType
            # over the three literals plus plain `StringType` (#2), so azapi's
            # `schema_validation_enabled` does not reject an empty string.
            threatIntelMode = ""

            # FW L274. `pointer.To(make(map[string]string))` -- again
            # unconditional, again a non-nil pointer to an empty value, so
            # AzureRM sent `"additionalProperties": {}`.
            additionalProperties = {}

            # FW L319-323 -> `expandFirewallVirtualHubSetting` (FW L740-787).
            # `virtual_hub` is a MaxItems-1 list that this module always
            # populates, so the expander always returned ok and both members
            # below were always present.
            virtualHub = { id = value.virtual_hub_id }

            # FW L778-784. On CREATE `existing` is nil, so the expander built
            # `hubIPAddresses.publicIPs` with `count` only and NO `addresses`.
            # That is exactly what this create-only writer sends. The
            # carry-forward half of that expander (FW L755-776, which reads
            # the live addresses back out of `existing`) has no analogue here
            # and does not need one -- see the merge writer in main.tf.
            hubIPAddresses = {
              publicIPs = {
                count = local.firewall_public_ip_counts[key]
              }
            }
          },
          # FW L315-317: guarded on a non-empty string, so an unset policy
          # omits the key rather than sending an empty SubResource.
          value.firewall_policy_id != null && value.firewall_policy_id != "" ? {
            firewallPolicy = { id = value.firewall_policy_id }
          } : {},
          length(local.firewall_skus[key]) > 0 ? { sku = local.firewall_skus[key] } : {},
        )
      },
    )
  }

  # FW L262 + L276: `tags.Expand(d.Get("tags").(map[string]interface{}))`
  # returns a non-nil pointer to a (possibly empty) map, so AzureRM sent
  # `"tags": {}` for a firewall with no tags. The module's own
  # `tags = try(each.value.tags, {})` did NOT normalise a null -- `try` catches
  # errors, not nulls -- so the null reached `d.Get`, which returned an empty
  # map, and `{}` went on the wire regardless. Normalised explicitly here.
  firewall_tags = {
    for key, value in local.firewalls : key => value.tags != null ? value.tags : {}
  }

  # =========================================================================
  # FIREWALL DAY-2 BODY (merge writer). Strictly the properties AzureRM
  # allowed to change in place -- i.e. every schema field this module feeds
  # that is NOT ForceNew.
  #
  #   sku_tier              FW L81-89   no ForceNew  -> properties.sku.tier
  #   firewall_policy_id    FW L91-95   no ForceNew  -> properties.firewallPolicy.id
  #   virtual_hub_id        FW L203-207 no ForceNew  -> properties.virtualHub.id
  #   vhub_public_ip_count  FW L208-213 no ForceNew  -> properties.hubIPAddresses.publicIPs.count
  #
  # Deliberately absent because AzureRM marked them ForceNew and a merge PUT
  # would silently no-op instead of replacing:
  #   name      FW L61,  sku_name FW L73,  zones FW L227 (ZonesMultiple*ForceNew),
  #   location  commonschema.Location(),   resource_group_name.
  # See the ForceNew note in main.tf for what that costs.
  #
  # 🔴 `tags` (commonschema.Tags(), FW L276) IS DELIBERATELY ABSENT FROM THIS
  # BODY AS OF 0.19.0. It used to sit here as `tags = local.firewall_tags[key]`,
  # and that is what made REG-1: a merge writer preserves every undeclared key
  # of the live object unconditionally (`utils/json.go` L52-L53), so it can add
  # and change a tag but can NEVER remove one. Tags now travel on
  # `azapi_resource_action.tags` in `main.tf`, which PUTs at
  # `Microsoft.Resources/tags/default` and REPLACES the whole tag set. There is
  # exactly one tag writer per address after create, and it is not this one.
  # `local.firewall_tags` is still the single source of the expression -- the
  # action reads it -- so the `{}` normalisation above is unchanged.
  # =========================================================================
  firewall_update_bodies = {
    for key, value in local.firewalls : key => {
      properties = merge(
        {
          virtualHub = { id = value.virtual_hub_id }
          # 🔴 THE POINT OF THE MERGE WRITER, on this type specifically.
          # `mergeObjectAtPath` takes the MAP branch for `publicIPs`, so
          # declaring `count` and omitting `addresses` PRESERVES the live
          # `addresses` array. AzureRM hand-rolled that carry-forward at
          # FW L764-776 against a GET it issued itself; here the provider's
          # GET-then-merge does it. Same outcome, different mechanism.
          hubIPAddresses = {
            publicIPs = {
              count = local.firewall_public_ip_counts[key]
            }
          }
        },
        value.sku_tier != null && value.sku_tier != "" ? { sku = { tier = value.sku_tier } } : {},
        value.firewall_policy_id != null && value.firewall_policy_id != "" ? {
          firewallPolicy = { id = value.firewall_policy_id }
        } : {},
      )
    }
  }

  # =========================================================================
  # FORCENEW GUARD INPUTS. Feed the `lifecycle.precondition` blocks on
  # `azapi_update_resource.fw`; see the audit in `main.tf` for which AzureRM
  # ForceNew fields these cover and which need no cover at all.
  #
  # ⭐ THE SHAPE OF EVERY PAIR BELOW IS DELIBERATE AND IS THE WHOLE REASON THE
  # CHECK IS NOT VACUOUS: the `_state_` and `_config_` halves are the SAME
  # EXPRESSION, differing only in whether they read
  #   `azapi_resource.fw[key].body`     -- the CREATE- or IMPORT-time body,
  #                                        pinned by `ignore_changes = [body]`
  # or
  #   `local.firewall_bodies[key]`      -- the genesis body this module would
  #                                        build from today's configuration.
  #
  # Reading the config half out of the GENESIS BODY rather than out of
  # `var.firewalls` is what makes absence comparable. Both halves resolve to
  # `null` (or `[]`) by the identical route, so:
  #   absent  vs absent  -> equal   -> pass
  #   absent  vs present -> unequal -> FAIL (a ForceNew property was ADDED)
  #   present vs absent  -> unequal -> FAIL (a ForceNew property was REMOVED)
  #   present vs present -> compared on value
  # The rejected alternative was `state == null || state == config`, which
  # passes whenever the state half is absent and therefore lets an addition
  # through unchecked.
  #
  # 🔴 `lower(null)` RAISES, it does not return null, so every call is inside
  # a `try`. Without that, one absent optional kills the whole plan.
  #
  # Locals may reference resources, and `lifecycle.precondition` may reference
  # locals, so the expressions live here where they can be read.
  # =========================================================================

  # sku_name, FW L73, at `properties.sku.name`.
  #
  # `lower()` on both halves: ARM echoes back the SKU name it was given, and
  # nothing in AzureRM or ARM treats `AZFW_Hub` and `azfw_hub` as different
  # firewalls. Case alone must not fail a plan.
  firewall_state_sku_names = {
    for key, _ in local.firewalls :
    key => try(lower(tostring(azapi_resource.fw[key].body.properties.sku.name)), null)
  }
  firewall_config_sku_names = {
    for key, _ in local.firewalls :
    key => try(lower(tostring(local.firewall_bodies[key].properties.sku.name)), null)
  }

  # zones, FW L227. 🔴 TOP-LEVEL in the ARM body, NOT under `properties`.
  #
  # `toset()` on BOTH halves. Three reasons, in order of weight:
  #   1. AzureRM's schema is `commonschema.ZonesMultipleOptionalForceNew()`, a
  #      TypeSet -- order was never significant to it either;
  #   2. ARM may return the array in any order, so a list comparison would
  #      fail spuriously on an adopted firewall;
  #   3. a bare HCL list literal is a TUPLE, and `tuple == list(string)` is
  #      FALSE with only a warning. Casting both sides removes that whole
  #      class of vacuous pass.
  # An absent `zones` member normalises to the EMPTY SET on both halves, which
  # is what a non-zonal firewall genuinely is -- `locals.tf` omits the key
  # entirely for an empty list, reproducing FW L279-282 -- so `[] vs []`
  # passes while `[] vs [1,2,3]` correctly fails.
  firewall_state_zones = {
    for key, _ in local.firewalls :
    key => toset(try([for zone in azapi_resource.fw[key].body.zones : tostring(zone)], []))
  }
  firewall_config_zones = {
    for key, _ in local.firewalls :
    key => toset(try([for zone in local.firewall_bodies[key].zones : tostring(zone)], []))
  }

  # =========================================================================
  # HUB IP ADDRESSES, read out of the read-only data source in `main.tf`.
  # `outputs.tf` publishes both and `resource_object` embeds both; see the
  # header there for the pre-migration contract these reproduce.
  #
  # ARM SHAPE (azapi v2.12.0 embedded 2025-07-01 type set, nodes #1569-#1571):
  #   properties.hubIPAddresses.privateIPAddress          string
  #   properties.hubIPAddresses.publicIPs.addresses[].address  string
  # Same two paths AzureRM's own flattener walked at FW L804-819.
  #
  # NULL SAFETY. A hub firewall that has not finished provisioning returns
  # `hubIPAddresses` absent or half-populated, and `.output` is unknown until
  # the data source has been read at least once; `try` keeps `terraform plan`
  # from exploding on either. A HEALTHY firewall never reaches the fallback --
  # ARM returns `privateIPAddress` on every vHub firewall GET, so these do not
  # quietly re-null the outputs the way the previous implementation did.
  #
  # 🟡 THE FALLBACKS DIVERGE FROM AZURERM, deliberately. AzureRM's flattener
  # declared `privateIp` as a zero-valued string and `publicIps` as a nil
  # slice (FW L799-803), which reached its schema as `""` and `[]`. Here an
  # unprovisioned firewall yields `null` for the private address rather than
  # `""`, because `""` is indistinguishable from a real answer and `null` is
  # not. The list keeps `[]`, which AzureRM also produced and which callers
  # already iterate.
  firewall_private_ip_addresses = {
    for key, _ in local.firewalls :
    key => try(tostring(data.azapi_resource.fw_hub_ip_addresses[key].output.properties.hubIPAddresses.privateIPAddress), null)
  }

  firewall_public_ip_addresses = {
    for key, _ in local.firewalls :
    key => try(tolist([
      for entry in data.azapi_resource.fw_hub_ip_addresses[key].output.properties.hubIPAddresses.publicIPs.addresses :
      tostring(entry.address)
    ]), tolist([]))
  }

  # =========================================================================
  # DIAGNOSTIC SETTING BODY. Bug-for-bug against `DIAG`
  # `resourceMonitorDiagnosticSettingCreate` (DIAG L228-349).
  # =========================================================================
  diagnostic_setting_bodies = {
    for key, value in local.flattened_diagnostic_settings : key => {
      properties = merge(
        {
          # DIAG L291. `Logs: &logs`, always assigned. Each entry comes from
          # `expandMonitorDiagnosticsSettingsEnabledLogs` (DIAG L627-666),
          # which sets `Enabled: true` (DIAG L637) and then picks EXACTLY ONE
          # of `category` / `categoryGroup` (DIAG L653-660). `enabled` is a
          # non-pointer bool with no `omitempty` in the SDK model, so it is
          # always on the wire.
          #
          # 🟡 DEVIATION, recorded: with both category sets empty AzureRM left
          # `logs` as a nil slice and sent `"logs": null`; this sends `[]`.
          # ARM treats an explicit null and an empty array identically here,
          # and the case is only reachable when metrics alone are enabled.
          logs = concat(
            [for category in(value.data.log_categories != null ? value.data.log_categories : []) : {
              category = category
              enabled  = true
            }],
            [for group in(value.data.log_groups != null ? value.data.log_groups : []) : {
              categoryGroup = group
              enabled       = true
            }],
          )

          # DIAG L292 + L277-281 -> `expandMonitorDiagnosticsSettingsEnabled
          # Metrics` (DIAG L759-774): `Category` set, `Enabled: true` (L767).
          # `results` starts as `make(..., 0)` (DIAG L760) and the pre-5.0
          # branch at DIAG L267-275 runs in v4.x, so `metrics` was never a nil
          # slice and `"metrics": []` was sent even with no metric categories.
          metrics = [for category in(value.data.metric_categories != null ? value.data.metric_categories : []) : {
            category = category
            enabled  = true
          }]
        },
        # DIAG L298-301. BOTH members are gated on the authorization rule id
        # alone, and `EventHubName` is then set UNCONDITIONALLY -- so an
        # authorization rule with no hub name sent `"eventHubName": ""`, not
        # an omitted key. Reproduced.
        value.data.event_hub_authorization_rule_resource_id != null && value.data.event_hub_authorization_rule_resource_id != "" ? {
          eventHubAuthorizationRuleId = value.data.event_hub_authorization_rule_resource_id
          eventHubName                = value.data.event_hub_name != null ? value.data.event_hub_name : ""
        } : {},
        # DIAG L304-306.
        value.data.workspace_resource_id != null && value.data.workspace_resource_id != "" ? {
          workspaceId = value.data.workspace_resource_id
        } : {},
        # DIAG L309-311.
        value.data.storage_account_resource_id != null && value.data.storage_account_resource_id != "" ? {
          storageAccountId = value.data.storage_account_resource_id
        } : {},
        # DIAG L314-316. The schema field is `partner_solution_id`; the ARM
        # member is `marketplacePartnerId`.
        value.data.marketplace_partner_resource_id != null && value.data.marketplace_partner_resource_id != "" ? {
          marketplacePartnerId = value.data.marketplace_partner_resource_id
        } : {},
        # DIAG L318-320.
        value.data.log_analytics_destination_type != null && value.data.log_analytics_destination_type != "" ? {
          logAnalyticsDestinationType = value.data.log_analytics_destination_type
        } : {},
      )
    }
  }

  # =========================================================================
  # THE FULL WRITER'S SILENCE CONTRACT. Audited against azapi v2.12.0
  # `internal/services/azapi_resource.go` on. THIS LIST IS THE
  # MODULE'S SAFETY PROPERTY, not a style choice.
  #
  # WHY IT EXISTS. `azapi_resource`'s update path (L826) is guarded by
  # `skip.CanSkipExternalRequest(plan, state, "update")`, which reflects over
  # EVERY field of `AzapiResourceModel` and returns false the moment any field
  # WITHOUT a `skip_on:"update"` tag differs between plan and state
  # (`internal/skip/skip.go` L14-57). A false there means a FULL PUT of
  # `state.body` -- and by the stale-body behaviour that body is whatever import or the last
  # apply wrote, never a refresh.
  #
  # NON-SKIPPABLE and CONFIGURABLE and NOT ForceNew -> listed below.
  #   body                        L59   (Optional+Computed)
  #   sensitive_body              L60   (Optional, WriteOnly)
  #   sensitive_body_version      L61   (Optional)
  #   identity                    L63   (ListNestedBlock, L432)
  #   ignore_body_changes         L64   (Optional, WriteOnly)
  #   ignore_casing               L65   (Optional+Computed)
  #   ignore_missing_property     L66   (Optional+Computed)
  #   ignore_null_property        L67   (Optional+Computed)
  #   list_unique_id_property     L68   (Optional)
  #   ignore_other_items_in_list  L69   (Optional)
  #   locks                       L71   (Optional)
  #   response_export_values      L77   (Optional)  <- THE ONE THAT BIT US.
  #        TFFR4 (Severity-MUST) forces it to be DECLARED (`[]`), and this
  #        entry is what makes declaring it safe: `ignore_changes` keeps the
  #        prior value, so the null-vs-`[]` adoption difference never reaches
  #        `skip.CanSkipExternalRequest`. Changing the export list in future
  #        therefore needs its own migration -- a new value will not take
  #        effect without a state operation.
  #   schema_validation_enabled   L79   (Optional+Computed)
  #   tags                        L80   (Optional+Computed)
  #   update_headers              L85   (Optional)
  #   update_query_parameters     L86   (Optional)
  #
  # NON-SKIPPABLE but DELIBERATELY NOT LISTED, with the reason:
  #   id L62, output L73 -- Computed-only. Not configurable, so
  #        `ignore_changes` cannot name them.
  #   name L72 (RequiresReplace L188-190), parent_id L74 (L197-199),
  #   location L70 (ModifyPlan L732-735) -- ForceNew. A diff REPLACES rather
  #        than PUTs, and masking a replacement would be worse than the hazard
  #        this list closes.
  #   replace_triggers_refs L76 -- replacement machinery, and not set on the
  #        writer either; see main.tf.
  #   replace_triggers_external_values L75 -- replacement machinery, and
  #        POSITIVELY RULED OUT on rather than merely unused. Its
  #        plan modifier is `RequiresReplaceIfNotNull`
  #        (`planmodifierdynamic/dynamic_requires_replace.go`, wired at L288),
  #        which DOES NOT REPLACE WHEN THE STATE VALUE IS NULL. After
  #        `terraform import` the state value IS null, so at ADOPTION -- the
  #        one moment it would have to work -- it does not fire and the plan
  #        is an UPDATE. And because it carries NO `skip_on:"update"` tag,
  #        that same null-to-value difference defeats
  #        `skip.CanSkipExternalRequest` and forces a full PUT of the stale
  #        `state.body`. It therefore cannot buy a replacement and can only
  #        cost the exact failure this list exists to prevent. Listing it in
  #        `ignore_changes` would not rescue it either: an ignored replacement
  #        trigger is an inert one. The ForceNew body properties are guarded
  #        by `lifecycle.precondition` on the merge writer instead.
  #
  # 🔴 DISCREPANCY WITH THE MIGRATION DESIGN NOTES, raised rather than silently
  # deviated from. The design notes list `type` (L82) among the ForceNew
  # exclusions. It is not: `azapi_resource.go` L206-212 declares `type` with
  # NO `RequiresReplace` plan modifier, and it carries no `skip_on` tag
  # either. The consequence is concrete -- bumping `var.resource_types.*` on
  # an existing deployment would drag this create-only writer into a full PUT
  # of `state.body` instead of replacing the resource. This module follows the
  # document (it does not list `type`) so that such a bump is at least VISIBLE
  # in the plan, but a consumer must treat an API-version bump as a
  # breaking change and not apply it casually.
  #
  # SKIPPABLE (`skip_on:"update"`), so they change STATE ONLY and issue no
  # PUT. Not listed, and they must not be:
  #   retry L78, timeouts L81, create_headers L83, create_query_parameters
  #   L84, delete_headers L87, delete_query_parameters L88, read_headers L89,
  #   read_query_parameters L90.
  # =========================================================================
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

locals {
  # Unknown discovery deliberately makes customer cardinality unplannable, before a legacy instance can be destroyed.
  customer_firewalls = {
    for key, firewall in local.requested_customer_firewalls : key => firewall
    if contains(["absent", "managed", "customer"], local.existing_public_ip_modes[key])
  }
  diagnostic_settings_v2 = {
    for key, setting in local.flattened_diagnostic_settings : key => {
      name = coalesce(setting.data.name, "diag-${local.all_firewalls[setting.virtual_hub_key].name}")
      logs = concat(
        [for category in coalesce(setting.data.log_categories, []) : { category = category, category_group = null }],
        [for group in coalesce(setting.data.log_groups, []) : { category = null, category_group = group }]
      )
      metrics                                  = [for category in coalesce(setting.data.metric_categories, []) : { category = category }]
      log_analytics_destination_type           = setting.data.log_analytics_destination_type
      workspace_resource_id                    = setting.data.workspace_resource_id
      storage_account_resource_id              = setting.data.storage_account_resource_id
      event_hub_authorization_rule_resource_id = setting.data.event_hub_authorization_rule_resource_id
      event_hub_name                           = setting.data.event_hub_name
      marketplace_partner_resource_id          = setting.data.marketplace_partner_resource_id
    }
  }
  existing_customer_mode = {
    # Deliberately does NOT pre-filter the source through coalesce(): real Azure ipConfigurations responses are a
    # heterogeneous tuple (one element carries privateIPAddress as a string, another omits that key), and coalesce()
    # cannot unify that mix; an enclosing try(..., []) would then silently misclassify a customer-mode firewall as
    # managed. Wrapping the whole for-expression in try(..., []) tolerates a null ipConfigurations without unifying
    # the tuple's element types.
    for key, firewall in local.existing_firewalls : key => length(try([
      for configuration in firewall.properties.ipConfigurations : configuration
      if try(configuration.properties.publicIPAddress.id, null) != null
    ], [])) > 0
  }
  existing_firewalls = {
    for key, firewall in local.requested_customer_firewalls : key => one([
      for existing in local.existing_firewalls_by_name[key] : existing
      if lower(provider::azapi::parse_resource_id("Microsoft.Network/azureFirewalls", existing.id).resource_group_name) == lower(firewall.resource_group_name)
    ])
  }
  existing_firewalls_by_name = {
    for key, firewall in local.requested_customer_firewalls : key => [
      for existing in one(data.azapi_resource_list.firewalls).output.firewalls : existing
      if lower(existing.name) == lower(firewall.name)
    ]
  }
  existing_public_ip_modes = {
    for key, firewall in local.existing_firewalls : key =>
    firewall == null ? "absent" : local.existing_customer_mode[key] ? "customer" : "managed"
  }
  # Managed and customer firewalls in one shape, for the id/name outputs.
  firewall_summaries = merge(
    { for key, firewall in azapi_resource.fw : key => { id = firewall.id, name = firewall.name } },
    { for key, firewall in module.customer_firewalls : key => { id = firewall.resource_id, name = firewall.name } }
  )
  parent_ids = {
    for key, firewall in local.requested_customer_firewalls : key =>
    "/subscriptions/${one(data.azapi_client_config.current).subscription_id}/resourceGroups/${firewall.resource_group_name}"
  }
  requested_customer_firewalls = { for key, firewall in local.all_firewalls : key => firewall if local.customer_mode[key] }
}
