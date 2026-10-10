# See `modules/site-to-site-vpn-site/tests/null_optionals.tftest.hcl` for why this exists:
# An earlier test apply failed at apply, not at plan, because the inputs were unknown at plan
# time and the locals were never evaluated. Known inputs force evaluation.
#
# `try()` catches ERRORS, not nulls, so a null that reaches `length()` or `tonumber()`
# survives `terraform validate` AND a passing plan and only detonates at apply. Every
# optional in this module is therefore exercised BOTH null and set.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

mock_provider "azapi" {}

variables {
  resource_types = {
    insights_diagnostic_settings = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
    network_azure_firewalls      = "Microsoft.Network/azureFirewalls@2025-07-01"
  }
}

# ---------------------------------------------------------------------------
# Every optional explicitly NULL. Terraform applies an `optional(T, default)`
# default to a null as well as to an omission, so this run pins the AzureRM
# schema defaults the module reproduces, not just the "unset" path.
# ---------------------------------------------------------------------------
run "all_optionals_null" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location             = "uksouth"
        resource_group_name  = "rg-test"
        sku_tier             = "Standard"
        name                 = "fw-null"
        sku_name             = null
        zones                = null
        firewall_policy_id   = null
        vhub_public_ip_count = null
        tags                 = null
      }
    }
    diagnostic_settings = {
      fw_a = {
        diag_a = {
          name                                     = null
          log_categories                           = null
          log_groups                               = null
          metric_categories                        = null
          log_analytics_destination_type           = null
          workspace_resource_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
          storage_account_resource_id              = null
          event_hub_authorization_rule_resource_id = null
          event_hub_name                           = null
          marketplace_partner_resource_id          = null
        }
      }
    }
  }

  # --- the three unconditional AzureRM create-body members (FW L272-274) ---

  # FW L272 + L595/L636: a non-nil pointer to an empty slice still serialises.
  assert {
    condition     = length(azapi_resource.fw["fw_a"].body.properties.ipConfigurations) == 0
    error_message = "ipConfigurations must be sent as a literal empty array, as AzureRM's always-non-nil expander did."
  }

  # FW L273: `pointer.To(AzureFirewallThreatIntelMode(""))`, unconditional.
  assert {
    condition     = azapi_resource.fw["fw_a"].body.properties.threatIntelMode == ""
    error_message = "threatIntelMode must be the empty string AzureRM sent unconditionally, not omitted."
  }

  # FW L274: `pointer.To(make(map[string]string))`, unconditional.
  assert {
    condition     = length(azapi_resource.fw["fw_a"].body.properties.additionalProperties) == 0
    error_message = "additionalProperties must be sent as a literal empty object, as AzureRM did."
  }

  # --- schema defaults that survive an explicit null ---

  assert {
    condition     = azapi_resource.fw["fw_a"].body.properties.sku.name == "AZFW_Hub"
    error_message = "sku.name must fall back to the variable default AZFW_Hub when sku_name is null."
  }

  assert {
    condition     = azapi_resource.fw["fw_a"].body.properties.sku.tier == "Standard"
    error_message = "sku.tier must carry the configured tier."
  }

  # FW L212: `public_ip_count` carries `Default: 1`.
  assert {
    condition     = azapi_resource.fw["fw_a"].body.properties.hubIPAddresses.publicIPs.count == 1
    error_message = "publicIPs.count must reproduce AzureRM's schema default of 1 when vhub_public_ip_count is null."
  }

  assert {
    condition     = tolist(azapi_resource.fw["fw_a"].body.zones) == tolist(["1", "2", "3"])
    error_message = "zones must fall back to the variable default [1,2,3], coerced to strings for ARM."
  }

  # FW L262 + L276: `tags.Expand` always returned a non-nil pointer.
  assert {
    condition     = length(azapi_resource.fw["fw_a"].tags) == 0
    error_message = "A null tags map must normalise to {} the way AzureRM's tags.Expand did."
  }

  # --- guarded members that must be ABSENT, not empty ---

  # FW L315-317.
  assert {
    condition     = !can(azapi_resource.fw["fw_a"].body.properties.firewallPolicy)
    error_message = "firewallPolicy must be absent when firewall_policy_id is null, not an empty SubResource."
  }

  # FW L778-784: on create, `existing` is nil so no `addresses` is sent.
  assert {
    condition     = !can(azapi_resource.fw["fw_a"].body.properties.hubIPAddresses.publicIPs.addresses)
    error_message = "publicIPs.addresses must be absent on create, matching the nil `existing` branch of expandFirewallVirtualHubSetting."
  }

  # --- parent_id reconstruction ---

  assert {
    condition     = azapi_resource.fw["fw_a"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    error_message = "parent_id must be rebuilt from the hub ID's subscription plus the firewall's own resource group."
  }

  # --- the day-2 merge writer carries ONLY the non-ForceNew subset ---

  assert {
    condition     = azapi_update_resource.fw["fw_a"].body.properties.sku.tier == "Standard"
    error_message = "The merge writer must carry sku.tier, which AzureRM allowed to change in place (FW L81-89)."
  }

  assert {
    condition     = !can(azapi_update_resource.fw["fw_a"].body.properties.sku.name)
    error_message = "The merge writer must NOT carry sku.name; AzureRM marked sku_name ForceNew (FW L73)."
  }

  assert {
    condition     = !can(azapi_update_resource.fw["fw_a"].body.zones)
    error_message = "The merge writer must NOT carry zones; AzureRM marked them ForceNew (FW L227)."
  }

  assert {
    condition     = !can(azapi_update_resource.fw["fw_a"].body.properties.ipConfigurations)
    error_message = "The merge writer must not re-send create-only scaffolding such as ipConfigurations."
  }

  # The undeclared path the merge exists to preserve must stay undeclared.
  assert {
    condition     = !can(azapi_update_resource.fw["fw_a"].body.properties.hubIPAddresses.publicIPs.addresses)
    error_message = "The merge writer must omit publicIPs.addresses so the GET-then-merge preserves the live array."
  }

  # --- diagnostic settings: generated name and AzureRM schema defaults ---

  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].name == "diag-fw-null"
    error_message = "A null diagnostic setting name must fall back to diag-<firewall name>."
  }

  # NOT asserted here, deliberately: `parent_id == azapi_resource.fw["fw_a"].id`
  # cannot be evaluated under `command = plan` because the firewall's `id` is
  # unknown until apply, and Terraform fails the run rather than skipping the
  # assertion. Switching this run to `apply` would make the comparison
  # tautological under `mock_provider` (both sides come from the same mocked
  # value), so it would prove nothing either. The wiring is covered by
  # `terraform validate` instead.

  # `log_groups` defaults to ["allLogs"], `log_categories` to [].
  assert {
    condition     = length(azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.logs) == 1
    error_message = "A null log_groups must fall back to [\"allLogs\"] and produce exactly one log entry."
  }

  # DIAG L637 + L653-660: `Enabled: true`, and exactly one of category /
  # categoryGroup.
  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.logs[0].categoryGroup == "allLogs" && azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.logs[0].enabled == true
    error_message = "A log group entry must be {categoryGroup, enabled=true}, never a category."
  }

  # DIAG L767.
  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.metrics[0].category == "AllMetrics" && azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.metrics[0].enabled == true
    error_message = "A null metric_categories must fall back to [\"AllMetrics\"], enabled true."
  }

  # DIAG L318-320.
  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.logAnalyticsDestinationType == "Dedicated"
    error_message = "A null log_analytics_destination_type must fall back to the variable default Dedicated."
  }

  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.workspaceId == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
    error_message = "workspaceId must carry the configured workspace (DIAG L304-306)."
  }

  # DIAG L298-301 / L309-311 / L314-316: every destination is guarded, so an
  # unset one is absent rather than an empty string.
  assert {
    condition     = !can(azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.eventHubAuthorizationRuleId)
    error_message = "eventHubAuthorizationRuleId must be absent when no authorization rule is set."
  }

  assert {
    condition     = !can(azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.eventHubName)
    error_message = "eventHubName must be absent when no authorization rule is set; AzureRM gates BOTH on the rule ID."
  }

  assert {
    condition     = !can(azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.storageAccountId)
    error_message = "storageAccountId must be absent when no storage account is set."
  }

  assert {
    condition     = !can(azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.marketplacePartnerId)
    error_message = "marketplacePartnerId must be absent when no partner resource is set."
  }

  # --- outputs that must not depend on a response ---

  # --- the response-only outputs come from the DATA SOURCE, not the writer ---
  #
  # The values themselves are unknown under `command = plan` (the data source
  # keys off the firewall's not-yet-created `id`), so they are asserted in
  # `hub_ip_outputs.tftest.hcl`, which applies first. What IS checkable here
  # is the wiring, and it is the part that regresses silently:
  #   - both writers must declare `response_export_values`, because AVM spec
  #     TFFR4 is Severity-MUST and Class-Pattern, and both must declare it
  #     EMPTY. The attribute is non-skippable (`azapi_resource.go` L77), so a
  #     non-empty list -- or the attribute without the matching
  #     `ignore_changes` entry asserted further down -- is what caused the
  #     testing stale PUT. The data source's non-empty export list must not
  #     leak onto either writer.
  assert {
    condition     = azapi_resource.fw["fw_a"].response_export_values != null && length(azapi_resource.fw["fw_a"].response_export_values) == 0
    error_message = "The full writer must declare response_export_values = [] -- present per TFFR4, and empty. A non-empty list here forces a full PUT of the stale state.body at adoption."
  }

  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].response_export_values != null && length(azapi_resource.diagnostic_setting["fw_a-diag_a"].response_export_values) == 0
    error_message = "The diagnostic setting writer must declare response_export_values = [] too."
  }

  #   - the data source must export exactly the ONE narrow path, never ["*"].
  #     `tolist()` on both sides: a bare literal is a TUPLE and
  #     `tuple == list(string)` is false with only a warning.
  assert {
    condition     = tolist(data.azapi_resource.fw_hub_ip_addresses["fw_a"].response_export_values) == tolist(["properties.hubIPAddresses"])
    error_message = "The hub IP data source must export only properties.hubIPAddresses -- never [\"*\"], which would pull the whole firewall body into state."
  }

  assert {
    condition     = output.resource_object["fw_a"].virtual_hub[0].virtual_hub_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
    error_message = "resource_object.virtual_hub must keep AzureRM's one-element shape; modules/virtual-wan indexes it positionally."
  }

  # --- the silence contract ---
  #
  # 🔴 `tolist()` ON BOTH SIDES IS LOAD-BEARING. A bare list literal is a
  # TUPLE, and `tuple == list(string)` is FALSE with nothing but a warning, so
  # the naive form of this assertion passes vacuously in the wrong direction.
  assert {
    condition = tolist(output.full_writer_ignored_attributes) == tolist([
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
    ])
    error_message = "The full writer's silence contract must be exactly the 17 audited attributes. If azapi added an 18th, audit it before changing this list."
  }
}

# ---------------------------------------------------------------------------
# Every optional SET. This is the run that catches type-unification bugs: the
# null run never evaluates most of these branches.
# ---------------------------------------------------------------------------
run "all_optionals_set" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_name            = "AZFW_Hub"
        sku_tier            = "Premium"
        name                = "fw-full"
        # Unordered AND duplicated on purpose: AzureRM's schema is a TypeSet,
        # so it de-duplicated. `toset()` must reproduce that.
        zones                = [3, 1, 1]
        firewall_policy_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/firewallPolicies/afwp-test"
        vhub_public_ip_count = "3"
        tags                 = { env = "test" }
      }
    }
    diagnostic_settings = {
      fw_a = {
        diag_a = {
          name                                     = "diag-custom"
          log_categories                           = ["AzureFirewallApplicationRule", "AzureFirewallNetworkRule"]
          log_groups                               = ["allLogs"]
          metric_categories                        = ["AllMetrics"]
          log_analytics_destination_type           = "AzureDiagnostics"
          workspace_resource_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
          storage_account_resource_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest"
          event_hub_authorization_rule_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.EventHub/namespaces/ehn-test/authorizationRules/RootManageSharedAccessKey"
          event_hub_name                           = "eh-test"
          marketplace_partner_resource_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Datadog/monitors/dd-test"
        }
      }
    }
  }

  # De-duplicated to two entries and coerced to strings. `tolist()` on both
  # sides for the tuple-vs-list reason noted above.
  assert {
    condition     = tolist(azapi_resource.fw["fw_a"].body.zones) == tolist(["1", "3"])
    error_message = "zones must be de-duplicated and stringified, reproducing AzureRM's TypeSet of TypeString."
  }

  # The public shape is a STRING; ARM needs a number.
  assert {
    condition     = azapi_resource.fw["fw_a"].body.properties.hubIPAddresses.publicIPs.count == 3
    error_message = "vhub_public_ip_count must reach ARM as a JSON number, reproducing AzureRM's TypeInt coercion."
  }

  assert {
    condition     = azapi_resource.fw["fw_a"].body.properties.firewallPolicy.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/firewallPolicies/afwp-test"
    error_message = "firewallPolicy must be a SubResource wrapping the configured policy ID (FW L315-317)."
  }

  assert {
    condition     = azapi_resource.fw["fw_a"].body.properties.sku.name == "AZFW_Hub" && azapi_resource.fw["fw_a"].body.properties.sku.tier == "Premium"
    error_message = "Both sku members must be present when both inputs are non-empty (FW L325-337)."
  }

  assert {
    condition     = azapi_resource.fw["fw_a"].tags["env"] == "test"
    error_message = "Configured tags must reach the firewall."
  }

  # --- merge writer carries the full day-2 subset ---

  assert {
    condition     = azapi_update_resource.fw["fw_a"].body.properties.firewallPolicy.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/firewallPolicies/afwp-test"
    error_message = "The merge writer must carry firewallPolicy; AzureRM allowed it to change in place (FW L91-95)."
  }

  assert {
    condition     = azapi_update_resource.fw["fw_a"].body.properties.hubIPAddresses.publicIPs.count == 3
    error_message = "The merge writer must carry the public IP count; AzureRM allowed it to change in place (FW L208-213)."
  }

  # 🔴 REG-1's remedy, and the inversion of what this assertion used to say. The merge writer
  # USED to own tags on day 2, and that is what made REG-1: `mergeObjectAtPath` copies every key
  # of the live object the new body does not mention straight into the request (`utils/json.go`
  # L52-L53, unconditional), so a merge writer can add and change a tag but never REMOVE one.
  # Tags now travel on `azapi_resource_action.tags`, which PUTs at
  # `Microsoft.Resources/tags/default` and REPLACES the whole set, as AzureRM's FW L262 + L276
  # `tags.Expand` assignment did.
  assert {
    condition     = !can(azapi_update_resource.fw["fw_a"].body.tags)
    error_message = "The merge writer must NOT carry a tags key: a merge writer can never remove a tag (REG-1). Tags belong on azapi_resource_action.tags."
  }

  assert {
    condition     = azapi_resource_action.tags["fw_a"].body.properties.tags["env"] == "test"
    error_message = "The tag writer owns tags on day 2 and must carry them."
  }

  # --- diagnostic settings, every destination populated ---

  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].name == "diag-custom"
    error_message = "An explicit diagnostic setting name must win over the generated one."
  }

  # Two categories plus one group. `logs` is a heterogeneous tuple by
  # construction: {category,enabled} and {categoryGroup,enabled} are different
  # object types and must NOT be unified into one shape with nulls in it.
  assert {
    condition     = length(azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.logs) == 3
    error_message = "log_categories and log_groups must both contribute entries to the single ARM logs array."
  }

  assert {
    condition     = !can(azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.logs[0].categoryGroup)
    error_message = "A log CATEGORY entry must not also carry a categoryGroup key; AzureRM's switch sets exactly one (DIAG L653-660)."
  }

  assert {
    condition     = !can(azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.logs[2].category)
    error_message = "A log GROUP entry must not also carry a category key; AzureRM's switch sets exactly one (DIAG L653-660)."
  }

  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.eventHubAuthorizationRuleId != null && azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.eventHubName == "eh-test"
    error_message = "Both event hub members must be emitted together (DIAG L298-301)."
  }

  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.storageAccountId != null && azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.marketplacePartnerId != null
    error_message = "storageAccountId and marketplacePartnerId must be emitted when configured."
  }

  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.logAnalyticsDestinationType == "AzureDiagnostics"
    error_message = "The configured log_analytics_destination_type must win over the default."
  }
}

# ---------------------------------------------------------------------------
# FW L279-282: an EMPTY zone set left `Zones` nil, and a nil pointer with
# `omitempty` is omitted. It is NOT sent as `[]`, and this is the branch the
# all-null run cannot reach, because a null `zones` gets the [1,2,3] default.
# ---------------------------------------------------------------------------
run "zones_empty_omits_the_key" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Basic"
        name                = "fw-nozones"
        zones               = []
      }
    }
    diagnostic_settings = {}
  }

  assert {
    condition     = !can(azapi_resource.fw["fw_a"].body.zones)
    error_message = "An empty zones list must omit the zones key entirely, not send []."
  }

  assert {
    condition     = length(azapi_resource.diagnostic_setting) == 0
    error_message = "An empty diagnostic_settings map must create no diagnostic settings."
  }
}

# ---------------------------------------------------------------------------
# DIAG L298-301 gates BOTH members on the authorization rule ID alone and then
# assigns `EventHubName` unconditionally, so an authorization rule with no hub
# name put a literal `"eventHubName": ""` on the wire. Bug-for-bug.
# ---------------------------------------------------------------------------
run "event_hub_name_null_still_emits_empty_string" {
  command = plan

  variables {
    firewalls = {
      fw_a = {
        virtual_hub_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualHubs/vhub-test"
        location            = "uksouth"
        resource_group_name = "rg-test"
        sku_tier            = "Standard"
        name                = "fw-eh"
      }
    }
    diagnostic_settings = {
      fw_a = {
        diag_a = {
          event_hub_authorization_rule_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.EventHub/namespaces/ehn-test/authorizationRules/RootManageSharedAccessKey"
          event_hub_name                           = null
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.diagnostic_setting["fw_a-diag_a"].body.properties.eventHubName == ""
    error_message = "A null event_hub_name alongside an authorization rule must send an empty string, not omit the key (DIAG L298-301)."
  }
}

# ---------------------------------------------------------------------------
# The empty-map case. `var.firewalls` has no `nullable = false`, so the null
# path is reachable too and is covered by the guards in outputs.tf.
# ---------------------------------------------------------------------------
run "empty_map" {
  command = plan

  variables {
    firewalls           = {}
    diagnostic_settings = {}
  }

  assert {
    condition     = length(azapi_resource.fw) == 0
    error_message = "An empty firewalls map must create no firewalls."
  }

  assert {
    condition     = length(azapi_update_resource.fw) == 0
    error_message = "An empty firewalls map must create no merge writers."
  }

  assert {
    condition     = length(azapi_resource.diagnostic_setting) == 0
    error_message = "An empty diagnostic_settings map must create no diagnostic settings."
  }

  assert {
    condition     = length(output.resource) == 0 && length(output.resource_id) == 0 && length(output.diagnostic_settings_resource_ids) == 0
    error_message = "The outputs must degrade to empty collections rather than erroring on an empty input map."
  }
}
