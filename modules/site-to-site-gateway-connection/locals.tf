locals {
  vpn_site_connections = var.vpn_site_connection != null ? var.vpn_site_connection : {}

  vpn_site_connection_existing_routing_configurations = {
    for key, connection in data.azapi_resource.existing_vpn_connection : key => try(connection.output.properties.routingConfiguration, null)
  }
  vpn_site_connection_preserved_routing_configurations = {
    for key, routing_configuration in local.vpn_site_connection_existing_routing_configurations : key => routing_configuration != null ? merge(
      routing_configuration,
      try(routing_configuration.vnetRoutes, null) != null ? {
        vnetRoutes = {
          for property, property_value in routing_configuration.vnetRoutes : property => property_value
          if property != "bgpConnections"
        }
      } : {},
    ) : null
  }

  # AzureRM's schema applies defaults BEFORE the expander runs, and the expander then sends
  # every one of these with `pointer.To(d.Get(...))` -- unconditionally, not only when the
  # consumer set them. A migrated connection therefore has to send the same literals, or the
  # first apply after the upgrade would silently reset live tunnels. Verified against
  # vpn_gateway_connection_resource.go at 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa:
  #   connection_mode                       L176-L179  Default "Default"
  #   route_weight                          L181-L186  Default 0
  #   protocol                              L188-L193  Default "IKEv2"
  #   bandwidth_mbps                        L195-L200  Default 10
  #   bgp_enabled                           L210-L215  Default false
  #   ratelimit_enabled                     L268-L272  Default false
  #   local_azure_ip_address_enabled        L274-L278  Default false
  #   policy_based_traffic_selector_enabled L280-L284  Default false
  #   internet_security_enabled             L68-L71    Default false
  vpn_link_defaults = {
    bandwidth_mbps                        = 10
    connection_mode                       = "Default"
    protocol                              = "IKEv2"
    route_weight                          = 0
    bgp_enabled                           = false
    ratelimit_enabled                     = false
    local_azure_ip_address_enabled        = false
    policy_based_traffic_selector_enabled = false
  }

  # Each nested ARM object is emitted only where AzureRM's expander emitted one, because
  # `ignore_null_property` prunes null VALUES but leaves an emptied object behind.
  # - expandVpnGatewayConnectionVpnSiteLinkConnections L526-L529 returns nil for an empty list
  # - expandVpnGatewayConnectionRoutingConfiguration   L671-L674 returns nil when `routing` is absent
  # - expandVpnGatewayConnectionIpSecPolicies          L626-L629 returns nil for an empty list
  # - expandVpnGatewayConnectionCustomBgpAddresses     L845     returns an EMPTY SLICE, never nil,
  #   so `vpnGatewayCustomBgpAddresses: []` is part of every request AzureRM sent and is kept below
  # - trafficSelectorPolicies is guarded by `if v, ok := d.GetOk(...)` at L381
  vpn_site_connection_bodies = {
    for key, value in local.vpn_site_connections : key => {
      properties = merge(
        {
          enableInternetSecurity = try(value.internet_security_enabled, null) != null ? value.internet_security_enabled : false
          remoteVpnSite          = { id = value.remote_vpn_site_id }
          vpnLinkConnections = length(try(value.vpn_links, null) != null ? value.vpn_links : []) > 0 ? [
            for link in value.vpn_links : {
              name = link.name
              properties = merge(
                {
                  vpnSiteLink                    = { id = link.vpn_site_link_id }
                  connectionBandwidth            = try(link.bandwidth_mbps, null) != null ? link.bandwidth_mbps : local.vpn_link_defaults.bandwidth_mbps
                  enableBgp                      = try(link.bgp_enabled, null) != null ? link.bgp_enabled : local.vpn_link_defaults.bgp_enabled
                  enableRateLimiting             = try(link.ratelimit_enabled, null) != null ? link.ratelimit_enabled : local.vpn_link_defaults.ratelimit_enabled
                  routingWeight                  = try(link.route_weight, null) != null ? link.route_weight : local.vpn_link_defaults.route_weight
                  useLocalAzureIpAddress         = try(link.local_azure_ip_address_enabled, null) != null ? link.local_azure_ip_address_enabled : local.vpn_link_defaults.local_azure_ip_address_enabled
                  usePolicyBasedTrafficSelectors = try(link.policy_based_traffic_selector_enabled, null) != null ? link.policy_based_traffic_selector_enabled : local.vpn_link_defaults.policy_based_traffic_selector_enabled
                  vpnConnectionProtocolType      = try(link.protocol, null) != null ? link.protocol : local.vpn_link_defaults.protocol
                  vpnLinkConnectionMode          = try(link.connection_mode, null) != null ? link.connection_mode : local.vpn_link_defaults.connection_mode
                  # Always an array, never absent -- see the expander note above.
                  vpnGatewayCustomBgpAddresses = [
                    for custom_bgp_address in(try(link.custom_bgp_addresses, null) != null ? link.custom_bgp_addresses : []) : {
                      customBgpIpAddress = custom_bgp_address.ip_address
                      ipConfigurationId  = custom_bgp_address.ip_configuration_id
                    }
                  ]
                  # `sa_data_size_kb` and `sa_lifetime_sec` are declared as `string` on this
                  # module's variable but AzureRM's schema types them TypeInt and ARM's
                  # `IPsecPolicy` model types them int64, so the conversion AzureRM did
                  # implicitly has to be explicit here.
                  ipsecPolicies = try(link.ipsec_policy, null) != null ? [
                    {
                      dhGroup             = link.ipsec_policy.dh_group
                      ikeEncryption       = link.ipsec_policy.ike_encryption_algorithm
                      ikeIntegrity        = link.ipsec_policy.ike_integrity_algorithm
                      ipsecEncryption     = link.ipsec_policy.encryption_algorithm
                      ipsecIntegrity      = link.ipsec_policy.integrity_algorithm
                      pfsGroup            = link.ipsec_policy.pfs_group
                      saDataSizeKilobytes = tonumber(link.ipsec_policy.sa_data_size_kb)
                      saLifeTimeSeconds   = tonumber(link.ipsec_policy.sa_lifetime_sec)
                    }
                  ] : null
                },
                # AzureRM guards this on `!= 0`, and the schema carries no default, so an
                # unset DPD timeout is absent from the request rather than sent as 0.
                try(link.dpd_timeout_seconds, null) != null && try(link.dpd_timeout_seconds, 0) != 0 ? {
                  dpdTimeoutSeconds = link.dpd_timeout_seconds
                } : {},
                # 🔴 `length(try(x, []))` is WRONG and was an observed apply failure.
                # `try` only catches ERRORS, not nulls: an `optional(list(string))` with no
                # default is null, `try` returns that null unchanged, and `length(null)` fails
                # with "argument must not be null". The null has to be tested explicitly.
                # It survived `terraform validate` AND a gate-PASSing `terraform plan` because
                # `vpn_links` was unknown at plan time, so the `for` body was never evaluated --
                # the error only appeared after 85 minutes of gateway provisioning.
                length(try(link.egress_nat_rule_ids, null) != null ? link.egress_nat_rule_ids : []) > 0 ? {
                  egressNatRules = [for nat_rule_id in link.egress_nat_rule_ids : { id = nat_rule_id }]
                } : {},
                length(try(link.ingress_nat_rule_ids, null) != null ? link.ingress_nat_rule_ids : []) > 0 ? {
                  ingressNatRules = [for nat_rule_id in link.ingress_nat_rule_ids : { id = nat_rule_id }]
                } : {},
              )
            }
          ] : null
        },
        try(value.routing, null) != null ? {
          routingConfiguration = merge(
            # `associated_route_table` is Required on the AzureRM schema, so it was always sent.
            {
              associatedRouteTable = { id = value.routing.associated_route_table }
            },
            # 🔴 DELIBERATE BUG-FOR-BUG PARITY: `variables.tf` accepts `inbound_route_map_id`
            # and `outbound_route_map_id`, the root module plumbs them all the way down, and
            # AzureRM's expander supports them (L684-L695) -- but this module's `routing`
            # block never wired them into the resource, so they have always been dropped.
            # Wiring them up here would make the FIRST apply after the provider migration
            # attach route maps to live connections that never had them, which is exactly
            # the unintended-write class this migration exists to avoid. The drop is
            # preserved; the fix belongs in a separate, deliberate change.
            try(value.routing.propagated_route_table, null) != null ? {
              propagatedRouteTables = merge(
                # AzureRM builds this list unconditionally, so an empty `route_table_ids`
                # still sends `ids: []`. ARM takes SubResource objects, not bare ID strings.
                {
                  ids = [
                    for route_table_id in(try(value.routing.propagated_route_table.route_table_ids, null) != null ? value.routing.propagated_route_table.route_table_ids : []) : { id = route_table_id }
                  ]
                },
                length(try(value.routing.propagated_route_table.labels, null) != null ? value.routing.propagated_route_table.labels : []) > 0 ? {
                  labels = value.routing.propagated_route_table.labels
                } : {},
              )
            } : {},
          )
          } : (lookup(local.vpn_site_connection_preserved_routing_configurations, key, null) != null ? {
            routingConfiguration = local.vpn_site_connection_preserved_routing_configurations[key]
        } : {}),
        try(value.traffic_selector_policy, null) != null ? {
          trafficSelectorPolicies = [
            {
              localAddressRanges  = value.traffic_selector_policy.local_address_ranges
              remoteAddressRanges = value.traffic_selector_policy.remote_address_ranges
            }
          ]
        } : {},
      )
    }
  }

  # The pre-shared key is the one secret this module handles. It is lifted out of `body` into
  # the write-only `sensitive_body` so it is neither persisted in state nor printed in a plan.
  # AzAPI merges `sensitive_body` into `body` before the request is built, matching list items
  # by their `name` property (utils/json.go mergeObjectAtPath), so only the links that
  # actually carry a key need to appear here -- unmatched body items are kept untouched.
  # AzureRM guarded the key on `!= ""` (L565-L567), so a link without one omits `sharedKey`
  # entirely and lets ARM generate it, matching the Optional+Computed schema.
  #
  # This list is also the ADDRESS SPACE for `sensitive_body_version` below, so it is built
  # once, here, and both consumers index into the same list.
  vpn_site_connection_keyed_links = {
    for key, value in local.vpn_site_connections : key => [
      for link in(try(value.vpn_links, null) != null ? value.vpn_links : []) : link
      if try(link.shared_key, null) != null && try(link.shared_key, "") != ""
    ]
  }
  vpn_site_connection_shared_keys = {
    for key, links in local.vpn_site_connection_keyed_links : key => [
      for link in links : {
        name       = link.name
        properties = { sharedKey = link.shared_key }
      }
    ]
  }

  # ⭐⭐ OPTION A (per-link `shared_key_version`) WAS REMOVED HERE.
  #
  # It was added on 2025-09-25 to solve a problem THAT DOES NOT EXIST. The premise was:
  # "rotation is SILENT, because `sensitive_body` is write-only so Terraform cannot diff it."
  # That premise was never measured. It is false.
  #
  # MEASURED (live): with NO version set, changing
  # `shared_key` alone plans `0 to add, 1 to change, 0 to destroy`, while the identical config
  # with the key left alone plans `No changes`. AzAPI detects the rotation on its own.
  # `ephemeralBodyChangeInPlan` (internal/services/resource.go:291) has THREE branches, and the
  # third hashes the sensitive body into Terraform PRIVATE STATE and diffs against it. Setting
  # a version does not add detection -- it REPLACES it: azapi_resource.go:1106-1114 stores the
  # hash only `if plan.SensitiveBodyVersion.IsNull()`, and DELETES it otherwise.
  #
  # 🔴 AND SETTING A VERSION IS ACTIVELY DESTRUCTIVE. With a version set and NOT bumped, a
  # later apply that changes anything else on the connection sends
  # `properties.vpnLinkConnections: []` and wipes every link. Measured:
  # `400 MissingLinkConnectionForVpnConnection` -- only ARM's minimum-one-link rule prevented
  # data loss, and every static gate had passed, because the emptying happens inside the
  # provider at APPLY time. The chain: an unbumped version makes `paths` empty, so
  # `FilterFields` (utils/json.go:422) returns `{properties:{vpnLinkConnections:[]}}` -- its
  # map branch collapses an emptied map to nil at L438-440, but its ARRAY branch at L442-450
  # has NO such guard, so `[]` survives as non-nil -- and `mergeObjectAtPath` then sees an
  # empty array with no identifier whose length differs from the live list, and takes the
  # `return newArr` branch, REPLACING the real links with nothing.
  #
  # So the null regime is both the detecting one and the safe one, and it is now the only one
  # this module offers.
  #
  # ⭐⭐ `var.sensitive_body_version` WAS REMOVED TOO.
  # It was kept for one commit on the argument that it is normative -- SKILL.md L222 says to
  # "use `sensitive_body_version` to make changes detectable without persisting secret values"
  # -- and that removing a normative attribute is a larger deviation than documenting a
  # hazardous one. That argument was overruled, correctly:
  #
  #   1. PARITY DOES NOT NEED IT. The azurerm module had no equivalent input. Removing it
  #      restores parity rather than departing from it, and nothing in this repo ever set it.
  #   2. IT CARRIES THE SAME DEFECT. Any stale entry a consumer leaves in the map reproduces
  #      exactly the wipe above; the hazard is in the attribute, not in how we derived it.
  #   3. IT HAS A WORSE VARIANT. A leaf path such as
  #      `"properties.vpnLinkConnections[0].properties.sharedKey"` -- the intuitive thing to
  #      write -- makes `FilterFields` strip every sibling it was not told to keep, INCLUDING
  #      `name`. The merge then has no identifier to match on and replaces the whole live list
  #      with that one stripped element. No staleness required, no empty array involved, and
  #      the documentation does not warn against it.
  #   4. THE PREMISE OF L222 IS ALREADY SATISFIED. "Make changes detectable" is the goal; with
  #      the version null, azapi detects them by itself. Measured: rotating the
  #      key with no version planned `1 to change`, while the same edit with a version set
  #      planned `No changes`. Null is not a weaker form of compliance here; it is the only
  #      form that works.
  #
  # Recorded as a deliberate deviation from `.github/skills/avm-tf-azapi/SKILL.md` L222 in
  # `MIGRATION-DEVIATIONS.md`. The provider defect is written up separately.

  # Per-resource timeout defaults. `var.timeouts` keeps its published shape -- same name, same
  # four attributes, same types -- but its attributes no longer carry a blanket `30m`/`5m`
  # default. An attribute the consumer leaves unset now falls back to the default of the
  # AzureRM resource this module replaced. A consumer who sets `var.timeouts` today is
  # unaffected.
  #
  # Cited against terraform-provider-azurerm@5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0).
  #
  # azapi_resource.this -> azurerm_vpn_gateway_connection
  #   vpn_gateway_connection_resource.go L38-L43: Create 30m, Read 5m, Update 30m, Delete 30m
  timeouts = {
    create = try(var.timeouts.create, null) != null ? var.timeouts.create : "30m"
    read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
    update = try(var.timeouts.update, null) != null ? var.timeouts.update : "30m"
    delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "30m"
  }
}
