# 🔴 THIS MODULE HAD AN OBSERVED APPLY FAILURE. See the comment at `main.tf` line 87.
#
# The `all_optionals_null` run below is the exact input shape that failed an earlier test apply on
#  after 85 minutes: `vpn_links` present, `egress_nat_rule_ids` and
# `ingress_nat_rule_ids` omitted, so both arrive as null and reach `length()`. In a test
# that cost 85 minutes of gateway provisioning to discover. Here it costs about a second,
# because the input is KNOWN at plan time and the locals actually evaluate.
#
# `mock_provider` means no Azure calls, no credentials and no cost.
#
# ⚠️ The pre-shared key never appears in this file. `sensitive_body` is write-only, so a
# key set here would not be persisted -- but the rule is that no key literal enters the
# repo outside the declared placeholders, so the key paths are exercised with an
# obvious non-secret and asserted only indirectly: `sensitive_body` cannot be read from an
# assertion at all, and `sensitive_body_version` is asserted to be NULL on every run that
# creates a resource. That last assertion is an INVARIANT of the module, not a default --
# see the long note at the `all_optionals_set` run.

mock_provider "azapi" {}

variables {
  resource_types = {
    network_vpn_gateways_vpn_connections = "Microsoft.Network/vpnGateways/vpnConnections@2025-07-01"
  }
}

# 🔴 THE APPLY-FAILURE REGRESSION CASE. Every `optional()` attribute without a default is omitted.
run "all_optionals_null" {
  command = plan

  variables {
    vpn_site_connection = {
      conn_a = {
        name               = "conn-null"
        remote_vpn_site_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/vpnsite-test"
        vpn_gateway_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/vpngw-test"
        vpn_links = [
          {
            name             = "linkconn-a"
            vpn_site_link_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/vpnsite-test/vpnSiteLinks/link-a"
          }
        ]
      }
    }
  }

  # The four errors the failed apply hit, in one place.
  assert {
    condition     = !can(azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.egressNatRules)
    error_message = "egressNatRules must be absent when egress_nat_rule_ids is null. This is the observed apply failure."
  }

  assert {
    condition     = !can(azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.ingressNatRules)
    error_message = "ingressNatRules must be absent when ingress_nat_rule_ids is null. This is the observed apply failure."
  }

  # Every AzureRM schema default, sent unconditionally by the expander via
  # `pointer.To(d.Get(...))`. If any of these stops being emitted, the first apply after a
  # customer's provider migration resets that property on a LIVE tunnel.
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.connectionBandwidth == 10
    error_message = "connectionBandwidth must reproduce AzureRM's schema default 10."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.vpnConnectionProtocolType == "IKEv2"
    error_message = "vpnConnectionProtocolType must reproduce AzureRM's schema default IKEv2."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.vpnLinkConnectionMode == "Default"
    error_message = "vpnLinkConnectionMode must reproduce AzureRM's schema default \"Default\"."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.routingWeight == 0 && azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.enableBgp == false && azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.enableRateLimiting == false && azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.useLocalAzureIpAddress == false && azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.usePolicyBasedTrafficSelectors == false
    error_message = "Every remaining AzureRM schema default must be reproduced on the link."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.enableInternetSecurity == false
    error_message = "enableInternetSecurity must reproduce AzureRM's schema default false."
  }

  # `expandVpnGatewayConnectionCustomBgpAddresses` returns an EMPTY SLICE, never nil, so
  # `vpnGatewayCustomBgpAddresses: []` was part of every request AzureRM sent.
  assert {
    condition     = can(azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.vpnGatewayCustomBgpAddresses) && length(azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.vpnGatewayCustomBgpAddresses) == 0
    error_message = "vpnGatewayCustomBgpAddresses must be an empty list, not absent: the AzureRM expander never returned nil."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.ipsecPolicies == null
    error_message = "ipsecPolicies must be null (and so pruned) when ipsec_policy is unset."
  }

  assert {
    condition     = !can(azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.dpdTimeoutSeconds)
    error_message = "dpdTimeoutSeconds must be absent when unset: AzureRM guarded it on != 0 and the schema has no default."
  }

  assert {
    condition     = !can(azapi_resource.this["conn_a"].body.properties.routingConfiguration)
    error_message = "routingConfiguration must be absent when routing is null."
  }

  assert {
    condition     = !can(azapi_resource.this["conn_a"].body.properties.trafficSelectorPolicies)
    error_message = "trafficSelectorPolicies must be absent when traffic_selector_policy is null."
  }

  # ⭐ INVARIANT, NOT A DEFAULT. No link carries a key here.
  assert {
    condition     = azapi_resource.this["conn_a"].sensitive_body_version == null
    error_message = "sensitive_body_version must be null on every plan this module produces. There is no input that can set it, and null is what keeps azapi's private-state hash alive."
  }
}

# Every optional supplied, so the opposite branch of each conditional evaluates.
run "all_optionals_set" {
  command = plan

  variables {
    vpn_site_connection = {
      conn_a = {
        name                      = "conn-full"
        remote_vpn_site_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/vpnsite-test"
        vpn_gateway_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/vpngw-test"
        internet_security_enabled = true
        vpn_links = [
          {
            name                                  = "linkconn-a"
            vpn_site_link_id                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/vpnsite-test/vpnSiteLinks/link-a"
            egress_nat_rule_ids                   = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/vpngw-test/natRules/egress-a"]
            ingress_nat_rule_ids                  = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/vpngw-test/natRules/ingress-a"]
            bandwidth_mbps                        = 200
            bgp_enabled                           = true
            connection_mode                       = "InitiatorOnly"
            dpd_timeout_seconds                   = 45
            protocol                              = "IKEv1"
            ratelimit_enabled                     = true
            route_weight                          = 5
            local_azure_ip_address_enabled        = true
            policy_based_traffic_selector_enabled = true
            shared_key                            = "placeholder-not-a-secret"
            ipsec_policy = {
              dh_group                 = "DHGroup14"
              ike_encryption_algorithm = "AES256"
              ike_integrity_algorithm  = "SHA256"
              encryption_algorithm     = "AES256"
              integrity_algorithm      = "SHA256"
              pfs_group                = "PFS14"
              sa_data_size_kb          = "102400000"
              sa_lifetime_sec          = "27000"
            }
            custom_bgp_addresses = [
              {
                ip_address          = "169.254.21.1"
                ip_configuration_id = "Instance0"
              }
            ]
          },
          {
            name             = "linkconn-b"
            vpn_site_link_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnSites/vpnsite-test/vpnSiteLinks/link-b"
          }
        ]
        routing = {
          associated_route_table = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/defaultRouteTable"
          propagated_route_table = {
            route_table_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/noneRouteTable"]
            labels          = ["default"]
          }
        }
        traffic_selector_policy = {
          local_address_ranges  = ["10.0.0.0/24"]
          remote_address_ranges = ["192.168.0.0/24"]
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.egressNatRules[0].id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/vpnGateways/vpngw-test/natRules/egress-a"
    error_message = "egressNatRules must wrap each NAT rule ID in a SubResource object."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.dpdTimeoutSeconds == 45
    error_message = "dpdTimeoutSeconds must be emitted when set to a non-zero value."
  }

  # `sa_data_size_kb` and `sa_lifetime_sec` are declared `string` on this module but ARM's
  # IPsecPolicy model types them int64, so the conversion AzureRM did implicitly must be
  # explicit here. A string would be a type error at ARM, not a Terraform error.
  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.ipsecPolicies[0].saDataSizeKilobytes == 102400000
    error_message = "saDataSizeKilobytes must be converted from the module's string input to a number."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.vpnLinkConnections[0].properties.vpnGatewayCustomBgpAddresses[0].customBgpIpAddress == "169.254.21.1"
    error_message = "vpnGatewayCustomBgpAddresses must carry the configured custom BGP addresses."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.routingConfiguration.propagatedRouteTables.ids[0].id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/vhub-test/hubRouteTables/noneRouteTable"
    error_message = "propagatedRouteTables.ids must wrap each route table ID in a SubResource object."
  }

  assert {
    condition     = azapi_resource.this["conn_a"].body.properties.trafficSelectorPolicies[0].localAddressRanges == tolist(["10.0.0.0/24"])
    error_message = "trafficSelectorPolicies must carry the configured ranges."
  }

  # 🔴 Deliberate bug-for-bug parity: `variables.tf` accepts the route map IDs and
  # AzureRM's expander supports them, but this module never wired them. Wiring them now
  # would attach route maps to LIVE connections at the first post-migration apply. The
  # drop is preserved on purpose, and this assertion is what stops it being "fixed" by
  # accident. It must fail loudly if someone wires them without a deliberate decision.
  assert {
    condition     = !can(azapi_resource.this["conn_a"].body.properties.routingConfiguration.inboundRouteMap) && !can(azapi_resource.this["conn_a"].body.properties.routingConfiguration.outboundRouteMap)
    error_message = "the inbound/outbound route map drop is deliberate parity with the pre-migration module. Changing it is a behaviour change for live connections and needs its own decision, not a drive-by fix."
  }

  # 🔴🔴 THE LOAD-BEARING ASSERTION OF THIS FILE. `sensitive_body_version` must be null on
  # EVERY plan this module can produce -- not "null by default", not "null unless asked".
  # There is no longer any input that can set it: a per-link `shared_key_version` and a
  # whole-resource `var.sensitive_body_version` both existed on the migration branch and were
  # both removed on, never released.
  #
  # This run is the strongest case for the invariant: every optional is supplied, and this
  # connection has two links, ONE of which carries a `shared_key` and one of which does not.
  # If the module ever synthesised a version from link input again, this is the shape that
  # would produce a PARTIAL map -- the exact stale-entry condition that wipes a collection.
  #
  # Why null rather than a version, measured rather than argued:
  #   (b1-null)  rotate the key, version null  -> `1 to change`. Detected.
  #   (b1-set)   rotate the key, version set   -> `No changes`.  Silent.
  #   (b2-set)   change a bandwidth integer, version set and unbumped
  #                   -> the PUT carries `properties.vpnLinkConnections: []` and ARM rejects
  #                      it, `400 MissingLinkConnectionForVpnConnection`. On any type ARM
  #                      permits to be empty, that apply SUCCEEDS and deletes silently.
  #
  # Deliberate deviation from `.github/skills/avm-tf-azapi/SKILL.md` L222. If this assertion
  # ever fails, the hazard has been reintroduced -- do not relax it, read MIGRATION-DEVIATIONS
  # that analysis first.
  assert {
    condition     = azapi_resource.this["conn_a"].sensitive_body_version == null
    error_message = "sensitive_body_version must be null on every plan this module produces, whatever the links carry. No input may set it, and no local may derive it: see the removal note in main.tf."
  }

  # Both links must survive in `body` regardless of which one carries a key.
  assert {
    condition     = length(azapi_resource.this["conn_a"].body.properties.vpnLinkConnections) == 2
    error_message = "Both configured links must appear in the body."
  }
}

run "empty_map" {
  command = plan

  variables {
    vpn_site_connection = {}
  }

  assert {
    condition     = length(azapi_resource.this) == 0
    error_message = "An empty vpn_site_connection map must create no resources."
  }
}
