# Why this file exists
# --------------------
# `main.p2s_vpn_gateway.tf` migrates the last two AzureRM resources in this module, and it
# does so with TWO DIFFERENT SHAPES:
#
#   `Microsoft.Network/vpnServerConfigurations`  candidate 1 -- a create-only `azapi_resource`
#                                                plus an `azapi_update_resource` merge writer,
#                                                because it owns a child collection
#                                                (`properties.configurationPolicyGroups`) that
#                                                a full PUT would DELETE.
#   `Microsoft.Network/p2sVpnGateways`           a plain `azapi_resource`, because it owns none.
#
# The shape IS the safety property, so it is asserted here rather than left to a comment: an
# edit that collapses the pair into a single writer, or that adds a needless second writer to
# the gateway, has to fail a test rather than a live deployment.
#
# The second thing this file exists for is the apply-time bug class: an apply failed in an earlier test
# after 85 minutes because `length(try(x, []))` let a NULL reach `length()`. `terraform
# validate` is a type check, not an evaluation, and `terraform plan` never evaluated the `for`
# body because the collection was unknown. Every run below gives every input a KNOWN value, so
# the locals are forced to evaluate at plan time.
#
# 🔴 A NOTE ON `command = plan`, BECAUSE IT IS A KNOWN TRAP AND NOT AN OVERSIGHT.
# A `precondition` that reads a resource attribute reads STATE, so inside a plan-only run
# there is no prior state and the check compares the configuration against itself and passes
# unconditionally -- a green plan-only suite would be a FALSE NEGATIVE. That trap does not
# apply here, because this module declares NO preconditions on either P2S resource. It
# declares none because `azurerm_vpn_server_configuration` has NO body-level ForceNew field:
# `grep -n ForceNew internal/services/network/vpn_server_configuration_resource.go` at
# 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa returns a single hit, L47 (`name`), plus
# `resource_group_name` L51 and `location` L53 via commonschema -- all three of which map to
# native AzAPI ForceNew attributes (`name`, `parent_id`, `location`) that are deliberately
# ABSENT from the full writer's ignore list. The assertion on that absence is below, and it is
# what keeps this reasoning true.
#
# The file still OPENS with a `command = apply` run, because plan-only cannot prove the graph
# converges, and the apply-time bug this file targets was an APPLY-time evaluation failure that
# plan never reached. Every later run is `plan` and executes against the state that run leaves
# behind.
#
# `mock_provider` means no Azure calls, no credentials and no cost.

mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "11111111-1111-1111-1111-111111111111"
    }
  }

  # ⚠️ REQUIRED FOR `command = apply`, AND IT IS A LIE THAT HAS TO BE UNDERSTOOD.
  # Without this block the mock provider invents an 8-character random string for every
  # computed `id`, and `azapi_update_resource.resource_id` -- which reads
  # `azapi_resource.this[each.key].id` -- rejects it at apply with
  # "invalid resource ID: resource id 'huel7v0x' must start with '/'". Measured; it fails on
  # `main.p2s_vpn_gateway.tf` L566 AND on the pre-existing `modules/virtual-hub/main.tf` L357,
  # so it is a property of the candidate-1 pattern under mocks, not of this migration.
  #
  # The override gives EVERY `azapi_resource` in the module the SAME well-formed ARM ID -- a
  # vpnServerConfigurations one, handed out to resource groups, Virtual WANs and hubs alike. So
  # NO ASSERTION IN THIS FILE MAY READ `.id` AND EXPECT IT TO MEAN ANYTHING. It exists solely
  # to let the apply reach completion.
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnServerConfigurations/mock"
    }
  }
}

mock_provider "modtm" {}

mock_provider "random" {}

variables {
  enable_telemetry    = false
  location            = "eastus"
  resource_group_name = "rg-test"
  virtual_wan_name    = "vwan-test"
  virtual_hubs = {
    hub_a = {
      name                = "vhub-a"
      location            = "eastus"
      resource_group_name = "rg-test"
      address_prefix      = "10.0.0.0/23"
    }
  }
}

# ⭐ THE ONLY `apply` RUN IN THIS MODULE, AND IT EARNS ITS PLACE.
#
# `terraform plan` is not a proof that `terraform apply` works. The earlier apply failure
# got 85 minutes into an apply before `length(null)` blew up, because the plan had deferred
# that expression: `validate` is a type check and `plan` skipped an unknown collection. A
# plan-only suite is structurally incapable of catching that class of bug.
#
# This run also exercises the one thing the candidate-1 pair cannot show at plan time: that the
# merge writer's `resource_id` -- which references the full writer's computed `id` and is
# therefore UNKNOWN in every plan -- is actually accepted once it resolves. That check found a
# real failure the first time it was run; see the `mock_resource` note above.
#
# Every later run in this file is `plan` and executes against the state this run leaves behind.
run "genesis" {
  command = apply

  variables {
    p2s_gateway_vpn_server_configurations = {
      cfg_bare = {
        name                     = "vpnsc-bare"
        virtual_hub_key          = "hub_a"
        vpn_authentication_types = ["Certificate"]
      }
    }
    p2s_gateways = {
      gw_bare = {
        name                                     = "p2sgw-bare"
        virtual_hub_key                          = "hub_a"
        scale_unit                               = 1
        p2s_gateway_vpn_server_configuration_key = "cfg_bare"
        connection_configuration = {
          name = "conn-bare"
          vpn_client_address_pool = {
            address_prefixes = ["10.100.0.0/24"]
          }
        }
      }
    }
  }

  # The reference is what ORDERS the two writers, and it is the only thing guaranteeing the
  # configuration exists before the merge PUT is attempted. A constructed ID would apply in the
  # wrong order and fail against real ARM.
  assert {
    condition     = azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].resource_id == azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].id
    error_message = "The merge writer's resource_id must come from the full writer's id, not be constructed -- that reference is what orders the two writers."
  }

  # Both P2S resources have to survive an apply, not merely a plan.
  assert {
    condition     = length(azapi_resource.p2s_gateway) == 1 && length(azapi_resource.p2s_gateway_vpn_server_configuration) == 1 && length(azapi_update_resource.p2s_gateway_vpn_server_configuration) == 1
    error_message = "The candidate-1 pair and the plain gateway must all apply cleanly."
  }
}

# The minimum viable pair: no certificate, no AAD, no DNS servers, no tags. Everything
# AzureRM's Create sent unconditionally must still be on the wire, and everything its
# expanders returned nil for must be absent.
run "p2s_optionals_all_null" {
  command = plan

  override_data {
    target = data.azapi_resource.existing_p2s_gateway["gw_bare"]
    values = {
      output = {
        properties = {
          p2SConnectionConfigurations = []
        }
      }
    }
  }

  variables {
    p2s_gateway_vpn_server_configurations = {
      cfg_bare = {
        name                     = "vpnsc-bare"
        virtual_hub_key          = "hub_a"
        vpn_authentication_types = ["Certificate"]
      }
    }
    p2s_gateways = {
      gw_bare = {
        name                                     = "p2sgw-bare"
        virtual_hub_key                          = "hub_a"
        scale_unit                               = 1
        p2s_gateway_vpn_server_configuration_key = "cfg_bare"
        connection_configuration = {
          name = "conn-bare"
          vpn_client_address_pool = {
            address_prefixes = ["10.100.0.0/24"]
          }
        }
      }
    }
  }

  # THE SHAPE ITSELF. The VPN server configuration gets a merge writer because a full PUT that
  # omits `properties.configurationPolicyGroups` would DELETE the live policy groups.
  assert {
    condition     = length(azapi_update_resource.p2s_gateway_vpn_server_configuration) == 1
    error_message = "The VPN server configuration owns a child collection (properties.configurationPolicyGroups) and must be written by the candidate-1 pair, not by a lone full writer."
  }

  # AzureRM took the resource group by NAME plus the provider's implicit subscription; AzAPI
  # needs an ID. Both P2S resources parent on the hub's resource group.
  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    error_message = "The VPN server configuration must parent on the hub's resource group, composed from the provider subscription."
  }

  assert {
    condition     = azapi_resource.p2s_gateway["gw_bare"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    error_message = "The P2S gateway must parent on the hub's resource group, composed from the provider subscription."
  }

  # --- the VPN server configuration body -------------------------------------------------
  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.vpnAuthenticationTypes == tolist(["Certificate"])
    error_message = "vpn_authentication_types must map to properties.vpnAuthenticationTypes."
  }

  # `expandVpnServerConfigurationAADAuthentication` (L603-L606) returns NIL for an empty list
  # and the field carries omitempty, so the key was ABSENT from AzureRM's request -- not `{}`.
  # `ignore_null_property = true` is what turns the local's whole-object null into an absent
  # key; emitting `{}` instead would be a different request.
  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.aadAuthenticationParameters == null
    error_message = "aadAuthenticationParameters must be null, and so pruned by ignore_null_property, when no AAD block is supplied -- matching the AzureRM expander returning nil."
  }

  # The three AzureRM sent as EMPTY ARRAYS rather than omitting. Their expanders all do
  # `make(..., 0)` then `return &slice` (L644-L656, L684-L696, L720-L737, L888-L896), so `[]`
  # was part of every create request even though this module exposes no input for any of them.
  # Dropping them would silently change the create request on the first post-migration apply.
  assert {
    condition     = length(azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.vpnClientRevokedCertificates) == 0
    error_message = "vpnClientRevokedCertificates must be sent as an empty array at create; the AzureRM expander returned a non-nil empty slice."
  }

  assert {
    condition     = length(azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.vpnClientIpsecPolicies) == 0
    error_message = "vpnClientIpsecPolicies must be sent as an empty array at create; the AzureRM expander returned a non-nil empty slice."
  }

  assert {
    condition     = length(azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.vpnProtocols) == 0
    error_message = "vpnProtocols must be sent as an empty array at create; the AzureRM expander returned a non-nil empty slice."
  }

  assert {
    condition     = length(azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.vpnClientRootCertificates) == 0
    error_message = "vpnClientRootCertificates must be an empty array when no client_root_certificate is supplied."
  }

  # ⚠️ `sensitive_body` IS A WRITE-ONLY ATTRIBUTE, so Terraform reports it as NULL in the plan
  # and never persists it -- MEASURED here, not assumed: a probe run that configured a
  # certificate and then read `sensitive_body.properties.vpnClientRootCertificates[0]` failed
  # with "azapi_resource...sensitive_body is null". Two consequences, both stated so nobody
  # reads more into the assertions below than they prove:
  #
  #   1. This assertion is VACUOUS IN THIS RUN. It would pass whether or not a certificate were
  #      supplied, because the attribute is null either way. It is kept only as the companion to
  #      the NON-vacuous one in `p2s_optionals_all_set`, where the same `== null` against a
  #      configured certificate is real evidence that the secret stays out of state.
  #   2. NO TEST IN THIS FILE CAN ASSERT THAT THE CERTIFICATE DATA REACHES ARM. The wiring from
  #      `local.p2s_gateway_vpn_server_configuration_client_root_certificates` into both writers
  #      is covered by `terraform validate` and by review, and by nothing else. That is a real
  #      gap in the suite, not a covered case.
  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].sensitive_body == null
    error_message = "sensitive_body must be null in state. Write-only, so this holds regardless of configuration -- see the note above."
  }

  # `sensitive_body_version` is an ORDINARY attribute, not write-only, so this one is real: it
  # would fail if the module ever started setting a version. It must stay NULL. Measured at
  # A version that is SET and not bumped makes a later apply send an EMPTY array for the
  # path and WIPE the live list. Null is both the detecting regime and the safe one.
  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].sensitive_body_version == null
    error_message = "sensitive_body_version must be left null on the full writer; a stale version wipes the live certificate list."
  }

  assert {
    condition     = azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].sensitive_body_version == null
    error_message = "sensitive_body_version must be left null on the merge writer; a stale version wipes the live certificate list."
  }

  # --- the merge writer's day-2 subset ---------------------------------------------------
  # DECLARING `vpnProtocols` HERE WOULD WIPE THE LIVE VALUE. It is Optional AND Computed on the
  # AzureRM schema (L256-L264), ARM populates it, and `mergeObjectAtPath` short-circuits on an
  # empty new array -- `if len(oldValue) == 0 || len(newArr) == 0 { return newArr }`
  # (utils/json.go L62-L64) -- so `[]` REPLACES rather than merges. AzureRM never wrote it after
  # create either, because `d.HasChange("vpn_protocols")` could never be true for a consumer of
  # this module. Same reasoning for the other two.
  assert {
    condition     = !can(azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.vpnProtocols)
    error_message = "The merge writer must NOT declare vpnProtocols -- it is Computed, and an empty array replaces rather than merges, so declaring it would clear ARM's value on every day-2 edit."
  }

  assert {
    condition     = !can(azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.vpnClientIpsecPolicies)
    error_message = "The merge writer must NOT declare vpnClientIpsecPolicies -- no input drives it, so AzureRM never wrote it after create."
  }

  assert {
    condition     = !can(azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.vpnClientRevokedCertificates)
    error_message = "The merge writer must NOT declare vpnClientRevokedCertificates -- no input drives it, so AzureRM never wrote it after create."
  }

  # `properties.configurationPolicyGroups` is the child collection the whole pattern exists to
  # protect. Neither writer may ever declare it.
  assert {
    condition     = !can(azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.configurationPolicyGroups)
    error_message = "configurationPolicyGroups must never appear in the full writer's body -- it is the child collection the candidate-1 pattern protects."
  }

  assert {
    condition     = !can(azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].body.properties.configurationPolicyGroups)
    error_message = "configurationPolicyGroups must never appear in the merge writer's body."
  }

  assert {
    condition     = azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].type == azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].type
    error_message = "Both writers must target the same resource type."
  }

  # --- the P2S gateway body --------------------------------------------------------------
  assert {
    condition     = azapi_resource.p2s_gateway["gw_bare"].body.properties.vpnGatewayScaleUnit == 1
    error_message = "scale_unit must map to properties.vpnGatewayScaleUnit."
  }

  # AzureRM guarded ONLY this one field on emptiness (L228-L231); everything else went out
  # unconditionally. `dns_servers` is `optional(list(string))` with no default, so it is NULL
  # when omitted -- and `length(null)` is a hard error, which is exactly the class of bug this
  # file exists to catch.
  assert {
    condition     = !can(azapi_resource.p2s_gateway["gw_bare"].body.properties.customDnsServers)
    error_message = "customDnsServers must be absent when dns_servers is null, matching AzureRM's len() != 0 guard."
  }

  # Schema Default false, sent unconditionally by Create (L217 and L409). This module exposes
  # no input for either, so the literal AzureRM sent was always false and must remain so.
  assert {
    condition     = azapi_resource.p2s_gateway["gw_bare"].body.properties.isRoutingPreferenceInternet == false
    error_message = "isRoutingPreferenceInternet must reproduce the AzureRM schema default false, which Create sent unconditionally."
  }

  assert {
    condition     = azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.enableInternetSecurity == false
    error_message = "enableInternetSecurity must reproduce the AzureRM schema default false, which the expander sent unconditionally."
  }

  # ARM spells it `p2SConnectionConfigurations`, with a capital S.
  assert {
    condition     = azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].name == "conn-bare"
    error_message = "The connection configuration must be carried at properties.p2SConnectionConfigurations, spelled with a capital S."
  }

  assert {
    condition     = azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.vpnClientAddressPool.addressPrefixes == tolist(["10.100.0.0/24"])
    error_message = "address_prefixes must map to properties.p2SConnectionConfigurations[*].properties.vpnClientAddressPool.addressPrefixes."
  }

  # `expandPointToSiteVPNGatewayConnectionRouteConfiguration` (L414-L418) returns nil for an
  # empty `route` list and this module exposes no `route` input, so the key was never present.
  assert {
    condition     = !can(azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.routingConfiguration)
    error_message = "routingConfiguration must be absent; the AzureRM expander returned nil and this module exposes no route input."
  }

  # ForceNew parity, and it only WORKS on a plain resource: under candidate 1
  # `ignore_changes = [body]` makes plan.body equal state.body by construction, so
  # `replace_triggers_refs` could never fire. There is no ignore_changes on the gateway, so it
  # can. AzureRM point_to_site_vpn_gateway_resource.go: virtual_hub_id L62,
  # vpn_server_configuration_id L69, routing_preference_internet_enabled L174.
  assert {
    condition     = tolist(azapi_resource.p2s_gateway["gw_bare"].replace_triggers_refs) == tolist(["properties.isRoutingPreferenceInternet", "properties.virtualHub.id", "properties.vpnServerConfiguration.id"])
    error_message = "The P2S gateway must carry replace_triggers_refs for all three body-level ForceNew fields azurerm declared at L62, L69 and L174."
  }

  # `response_export_values` must be DECLARED on every writer and must be EMPTY. AVM spec TFFR4
  # is Severity-MUST and Class-Pattern: the attribute MUST be specified, even if empty. The
  # earlier change that removed it breached that MUST and is retracted.
  #
  # The hazard it was reacting to is real and is handled by `ignore_changes`, not by omission:
  # the attribute carries no skip_on tag (azapi_resource.go L77), so at ADOPTION the imported
  # state holds null while the config holds `[]` -- a difference -- and that alone would drag
  # the resource into ["update"] and PUT the stale state.body. On the VPN server
  # configuration that PUT drops configurationPolicyGroups. Both `azapi_resource` addresses
  # therefore name `response_export_values` in `lifecycle.ignore_changes`; the assertions
  # further down pin the full writer's list, and `tests/unit/tffr4_ignore_changes.tftest.hcl` at
  # the repo root pins the behaviour under a mock apply.
  #
  # A future change to either export list needs its own migration: `ignore_changes` pins the
  # prior value, so a new list is a no-op until a state operation is performed.
  assert {
    condition     = azapi_resource.p2s_gateway["gw_bare"].response_export_values != null && length(azapi_resource.p2s_gateway["gw_bare"].response_export_values) == 0
    error_message = "response_export_values must be declared and EMPTY on the P2S gateway: present per TFFR4 (Severity-MUST), empty because nothing reads .output."
  }

  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].response_export_values != null && length(azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].response_export_values) == 0
    error_message = "response_export_values must be declared and EMPTY on the VPN server configuration full writer."
  }

  assert {
    condition     = azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].response_export_values != null && length(azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].response_export_values) == 0
    error_message = "response_export_values must be declared and EMPTY on the VPN server configuration merge writer."
  }

  # --- the silence contract ---------------------------------------------------------------
  # `lifecycle` blocks cannot reference a local, so the list is written out twice: once in
  # `local.vpn_server_configuration_full_writer_ignored_attributes` with the per-entry audit,
  # once in the `lifecycle` block that actually does the work. These assertions are the only
  # thing keeping the two in step. 17 is the count enumerated against azapi v2.12.0
  # `AzapiResourceModel` L58-L91; a provider bump that adds a non-skippable configurable field
  # makes this number wrong, and that is the point.
  assert {
    condition     = length(local.vpn_server_configuration_full_writer_ignored_attributes) == 17
    error_message = "The full writer's ignore_changes list must hold all 17 non-skippable configurable azapi_resource attributes."
  }

  assert {
    condition     = contains(local.vpn_server_configuration_full_writer_ignored_attributes, "response_export_values")
    error_message = "response_export_values must be in the full writer's ignore_changes list -- it is the attribute that drove the measured spurious update in testing."
  }

  assert {
    condition     = contains(local.vpn_server_configuration_full_writer_ignored_attributes, "sensitive_body")
    error_message = "sensitive_body must be in the full writer's ignore_changes list; certificate rotation has to flow through the merge writer instead."
  }

  # `timeouts` carries skip_on:"update" (azapi_resource.go L81), so a diff on it never reaches
  # ARM. Silencing it would cost real behaviour for no safety gain. Same for `retry` (L78).
  assert {
    condition     = !contains(local.vpn_server_configuration_full_writer_ignored_attributes, "timeouts")
    error_message = "timeouts must NOT be silenced -- it is skip_on:update, so a diff on it makes no ARM call."
  }

  assert {
    condition     = !contains(local.vpn_server_configuration_full_writer_ignored_attributes, "retry")
    error_message = "retry must NOT be silenced -- it is skip_on:update, so a diff on it makes no ARM call."
  }

  # `name`, `location` and `parent_id` are ForceNew on AzAPI and are the ENTIRE ForceNew surface
  # of azurerm_vpn_server_configuration (L47, L51, L53). Listing them would HIDE a replacement
  # the consumer used to get -- and it is their ABSENCE that makes this module's zero
  # preconditions correct rather than a gap. If a future edit adds one of them to the list,
  # this assertion fails and the precondition question reopens.
  assert {
    condition     = !contains(local.vpn_server_configuration_full_writer_ignored_attributes, "name") && !contains(local.vpn_server_configuration_full_writer_ignored_attributes, "location") && !contains(local.vpn_server_configuration_full_writer_ignored_attributes, "parent_id")
    error_message = "name, location and parent_id must NOT be silenced -- they are ForceNew on azapi and are the entire ForceNew surface of azurerm_vpn_server_configuration."
  }

  # --- timeouts ---------------------------------------------------------------------------
  # AzureRM's own per-resource values, not the repo-wide 30m.
  # vpn_server_configuration_resource.go L36-L40, point_to_site_vpn_gateway_resource.go L40-L44.
  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].timeouts.create == "90m" && azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].timeouts.read == "5m" && azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].timeouts.update == "90m" && azapi_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].timeouts.delete == "90m"
    error_message = "azurerm_vpn_server_configuration defaulted to Create 90m, Read 5m, Update 90m, Delete 90m."
  }

  assert {
    condition     = azapi_resource.p2s_gateway["gw_bare"].timeouts.create == "90m" && azapi_resource.p2s_gateway["gw_bare"].timeouts.read == "5m" && azapi_resource.p2s_gateway["gw_bare"].timeouts.update == "90m" && azapi_resource.p2s_gateway["gw_bare"].timeouts.delete == "90m"
    error_message = "azurerm_point_to_site_vpn_gateway defaulted to Create 90m, Read 5m, Update 90m, Delete 90m."
  }

  # The merge writer's create IS the first merge PUT and its Delete is an empty function, so
  # both ARM-facing operations take AzureRM's UPDATE budget.
  assert {
    condition     = azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].timeouts.create == "90m" && azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_bare"].timeouts.update == "90m"
    error_message = "The merge writer's create is the first merge PUT, so it takes azurerm_vpn_server_configuration's 90m update budget."
  }
}

# Everything supplied: certificate, AAD, DNS servers and tags. The secret path is what matters
# here -- `public_cert_data` must be in `sensitive_body` and must NOT be in `body`.
run "p2s_optionals_all_set" {
  command = plan

  variables {
    tags = { env = "test" }
    p2s_gateway_vpn_server_configurations = {
      cfg_full = {
        name                     = "vpnsc-full"
        virtual_hub_key          = "hub_a"
        vpn_authentication_types = ["Certificate", "AAD"]
        tags                     = { owner = "net" }
        client_root_certificate = {
          name             = "root-a"
          public_cert_data = "MIICNotARealCertificateJustTestData"
        }
        azure_active_directory_authentication = {
          audience = "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"
          issuer   = "https://sts.windows.net/11111111-1111-1111-1111-111111111111/"
          tenant   = "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111"
        }
      }
    }
    p2s_gateways = {
      gw_full = {
        name                                     = "p2sgw-full"
        virtual_hub_key                          = "hub_a"
        scale_unit                               = 2
        dns_servers                              = ["10.0.0.4", "10.0.0.5"]
        tags                                     = { owner = "net" }
        p2s_gateway_vpn_server_configuration_key = "cfg_full"
        connection_configuration = {
          name = "conn-full"
          vpn_client_address_pool = {
            address_prefixes = ["10.100.0.0/24", "10.101.0.0/24"]
          }
        }
      }
    }
  }

  # THE SECRET. `public_cert_data` must never reach `body`, on either writer. This is a
  # DELIBERATE DEPARTURE from AzureRM, which did not mark the field Sensitive -- the only
  # `Sensitive: true` in vpn_server_configuration_resource.go is L205, on radius.server.secret,
  # which this module does not expose. The cost is stated in main.p2s_vpn_gateway.tf: supplying
  # a certificate now requires Terraform 1.11 or later.
  assert {
    condition     = !can(azapi_resource.p2s_gateway_vpn_server_configuration["cfg_full"].body.properties.vpnClientRootCertificates[0].publicCertData)
    error_message = "public_cert_data must never appear in body; it belongs in sensitive_body."
  }

  assert {
    condition     = !can(azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_full"].body.properties.vpnClientRootCertificates[0].publicCertData)
    error_message = "public_cert_data must never appear in the merge writer's body either."
  }

  # The `name` has to be in BOTH halves: azapi merges sensitive_body into body by matching list
  # items on their `name` property (utils/json.go mergeObjectAtPath L79-L104, identifier key
  # defaulted to "name" by listIdentifierKeyForPath L270-L279). Without it the two halves would
  # not rejoin on the wire.
  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_full"].body.properties.vpnClientRootCertificates[0].name == "root-a"
    error_message = "The certificate name must be in body so azapi can match the sensitive_body list item to it by name."
  }

  assert {
    condition     = azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_full"].body.properties.vpnClientRootCertificates[0].name == "root-a"
    error_message = "The certificate name must be in the merge writer's body for the same reason."
  }

  # ⭐ THE NON-VACUOUS HALF OF THE SECRET TEST. A certificate IS configured in this run, and
  # `sensitive_body` is STILL null in the plan -- that is the whole point of a write-only
  # attribute, and it is the evidence that `public_cert_data` never lands in state. Under
  # AzureRM it did: `public_cert_data` is not marked Sensitive there (the only `Sensitive: true`
  # in vpn_server_configuration_resource.go is L205, on radius.server.secret), so it sat in
  # plain state and printed in plans.
  #
  # Paired with the two `!can(...body...publicCertData)` assertions above, this covers both
  # halves of "the secret is not in state": not in `body`, and not in `sensitive_body` either.
  # What it does NOT cover is that the value reaches ARM -- see the note in
  # `p2s_optionals_all_null`.
  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_full"].sensitive_body == null
    error_message = "sensitive_body must stay null in state even when a certificate is configured; that is what keeps public_cert_data out of state, unlike azurerm."
  }

  assert {
    condition     = azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_full"].sensitive_body == null
    error_message = "The merge writer's sensitive_body must stay null in state even when a certificate is configured."
  }

  # ARM names these `aadTenant`, `aadAudience` and `aadIssuer`, not `tenant`/`audience`/`issuer`.
  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_full"].body.properties.aadAuthenticationParameters.aadTenant == "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111"
    error_message = "tenant must map to properties.aadAuthenticationParameters.aadTenant."
  }

  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_full"].body.properties.aadAuthenticationParameters.aadAudience == "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"
    error_message = "audience must map to properties.aadAuthenticationParameters.aadAudience."
  }

  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_full"].body.properties.aadAuthenticationParameters.aadIssuer == "https://sts.windows.net/11111111-1111-1111-1111-111111111111/"
    error_message = "issuer must map to properties.aadAuthenticationParameters.aadIssuer."
  }

  # The merge writer has to carry AAD as well: it is the only writer that can change it after
  # create, and AzureRM's Update assigned it under d.HasChange (L487-L489).
  assert {
    condition     = azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_full"].body.properties.aadAuthenticationParameters.aadTenant == "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111"
    error_message = "The merge writer must declare aadAuthenticationParameters; AzureRM's Update wrote it under d.HasChange."
  }

  assert {
    condition     = azapi_resource.p2s_gateway["gw_full"].body.properties.customDnsServers == tolist(["10.0.0.4", "10.0.0.5"])
    error_message = "dns_servers must map to properties.customDnsServers when non-empty."
  }

  # 🔴 REG-1, INVERTED IN 0.19.0. This assertion used to require the OPPOSITE -- that tags rode
  # on the merge writer as a BODY KEY, because `azapi_update_resource` has no `tags` attribute --
  # and that is exactly what made REG-1: the merge is additive PER KEY (`utils/json.go` L52-L53
  # copies every undeclared live key straight back into the request), so DELETING a tag left it
  # live in Azure while the plan showed it going away. AzureRM assigned the whole map
  # (L571-L573). Observed in testing. Tags now travel on
  # `azapi_resource_action.p2s_gateway_vpn_server_configuration_tags`, which PUTs at
  # `Microsoft.Resources/tags/default` and REPLACES the whole set.
  assert {
    condition     = !can(azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_full"].body.tags)
    error_message = "The merge writer must NOT carry a tags body key: a merge writer can never remove a tag (REG-1)."
  }

  assert {
    condition     = azapi_resource_action.p2s_gateway_vpn_server_configuration_tags["cfg_full"].body.properties.tags.owner == "net"
    error_message = "The tag writer must carry the configured tags for the VPN server configuration."
  }

  # A per-resource tags map REPLACES var.tags rather than merging with it; that is what
  # locals.tf specifies, and it is easy to break by reaching for merge().
  assert {
    condition     = azapi_resource.p2s_gateway["gw_full"].tags.owner == "net" && !can(azapi_resource.p2s_gateway["gw_full"].tags.env)
    error_message = "A per-gateway tags map must replace var.tags rather than merge with it, as locals.tf specifies."
  }
}

# var.tags must reach both resources when the per-resource map is null. The null-coalescing
# fallback in locals.tf is easy to break and invisible in a plan that sets tags everywhere.
run "p2s_tags_fall_back_to_var_tags" {
  command = plan

  variables {
    tags = { env = "test" }
    p2s_gateway_vpn_server_configurations = {
      cfg_a = {
        name                     = "vpnsc-a"
        virtual_hub_key          = "hub_a"
        vpn_authentication_types = ["Certificate"]
      }
    }
    p2s_gateways = {
      gw_a = {
        name                                     = "p2sgw-a"
        virtual_hub_key                          = "hub_a"
        scale_unit                               = 1
        p2s_gateway_vpn_server_configuration_key = "cfg_a"
        connection_configuration = {
          name = "conn-a"
          vpn_client_address_pool = {
            address_prefixes = ["10.100.0.0/24"]
          }
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.p2s_gateway_vpn_server_configuration["cfg_a"].tags.env == "test"
    error_message = "var.tags must reach the VPN server configuration when its own tags map is null."
  }

  assert {
    condition     = azapi_resource.p2s_gateway["gw_a"].tags.env == "test"
    error_message = "var.tags must reach the P2S gateway when its own tags map is null."
  }

  # 🔴 REG-1's remedy: the same cascade, now landing on the tag writer rather than on the merge
  # writer's body.
  assert {
    condition     = azapi_resource_action.p2s_gateway_vpn_server_configuration_tags["cfg_a"].body.properties.tags.env == "test"
    error_message = "var.tags must reach the tag writer's body when the per-resource map is null."
  }

  assert {
    condition     = !can(azapi_update_resource.p2s_gateway_vpn_server_configuration["cfg_a"].body.tags)
    error_message = "The merge writer must NOT carry a tags body key: a merge writer can never remove a tag (REG-1)."
  }
}

# Empty maps must create nothing at all. `local.p2s_gateways` is null-able, so the for_each
# guard has to cope with both a null and an empty map.
run "p2s_empty_maps" {
  command = plan

  assert {
    condition     = length(azapi_resource.p2s_gateway) == 0 && length(azapi_resource.p2s_gateway_vpn_server_configuration) == 0 && length(azapi_update_resource.p2s_gateway_vpn_server_configuration) == 0 && length(azapi_resource_action.p2s_gateway_vpn_server_configuration_tags) == 0
    error_message = "Empty p2s_gateways and p2s_gateway_vpn_server_configurations maps must create no resources, the tag writer included: its for_each is the same map as the full writer's, so a tag writer exists if and only if a configuration does."
  }
}

run "omitted_p2s_routing_preserves_existing_arm_value" {
  command = plan

  variables {
    p2s_gateway_vpn_server_configurations = {
      cfg_bare = {
        name                     = "vpnsc-bare"
        virtual_hub_key          = "hub_a"
        vpn_authentication_types = ["Certificate"]
      }
    }
    p2s_gateways = {
      gw_bare = {
        name                                     = "p2sgw-bare"
        virtual_hub_key                          = "hub_a"
        scale_unit                               = 1
        p2s_gateway_vpn_server_configuration_key = "cfg_bare"
        connection_configuration = {
          name = "conn-bare"
          vpn_client_address_pool = {
            address_prefixes = ["10.100.0.0/24"]
          }
        }
      }
    }
  }

  override_data {
    target = data.azapi_resource.existing_p2s_gateway["gw_bare"]
    values = {
      output = {
        properties = {
          p2SConnectionConfigurations = [{
            name = "conn-bare"
            properties = {
              routingConfiguration = {
                associatedRouteTable = {
                  id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/hubRouteTables/defaultRouteTable"
                }
                propagatedRouteTables = {
                  ids    = [{ id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/hubRouteTables/noneRouteTable" }]
                  labels = ["none"]
                }
                inboundRouteMap = {
                  id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/routeMaps/inbound"
                }
                outboundRouteMap = {
                  id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/routeMaps/outbound"
                }
                vnetRoutes = {
                  bgpConnections = [{
                    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/bgpConnections/primary-nva1"
                  }]
                  staticRoutes = []
                  staticRoutesConfig = {
                    propagateStaticRoutes          = true
                    vnetLocalRouteOverrideCriteria = "Contains"
                  }
                }
              }
            }
          }]
        }
      }
    }
  }

  assert {
    condition = (
      azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.routingConfiguration.associatedRouteTable.id ==
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/hubRouteTables/defaultRouteTable" &&
      azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.routingConfiguration.propagatedRouteTables.ids[0].id ==
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/hubRouteTables/noneRouteTable" &&
      azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.routingConfiguration.propagatedRouteTables.labels == ["none"] &&
      azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.routingConfiguration.inboundRouteMap.id ==
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/routeMaps/inbound" &&
      azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.routingConfiguration.outboundRouteMap.id ==
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-a/routeMaps/outbound" &&
      azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.routingConfiguration.vnetRoutes.staticRoutesConfig.propagateStaticRoutes &&
      azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.routingConfiguration.vnetRoutes.staticRoutesConfig.vnetLocalRouteOverrideCriteria == "Contains" &&
      !contains(keys(azapi_resource.p2s_gateway["gw_bare"].body.properties.p2SConnectionConfigurations[0].properties.routingConfiguration.vnetRoutes), "bgpConnections")
    )
    error_message = "Omitted P2S routing must preserve writable ARM routing fields and filter the read-only BGP back-reference."
  }

  assert {
    condition = (
      data.azapi_resource.existing_p2s_gateway["gw_bare"].ignore_not_found &&
      data.azapi_resource.existing_p2s_gateway["gw_bare"].response_export_values == ["properties.p2SConnectionConfigurations"]
    )
    error_message = "The preservation read must tolerate a new gateway's 404 and export only its inline connection configurations."
  }
}
