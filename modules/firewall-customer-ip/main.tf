data "azapi_resource" "virtual_hub" {
  resource_id = var.virtual_hub_id
  type        = var.resource_types.network_virtual_hubs
  response_export_values = {
    location       = "location"
    virtual_wan_id = "properties.virtualWan.id"
  }
}

# The hub's own properties.sku is not reliably populated by the Virtual Hub RP; the
# Standard/Basic designation is authoritative only on the parent Virtual WAN's properties.type,
# which governs every hub attached to it.
data "azapi_resource" "virtual_wan" {
  resource_id = data.azapi_resource.virtual_hub.output.virtual_wan_id
  type        = var.resource_types.network_virtual_wans
  response_export_values = {
    type = "properties.type"
  }
}

data "azapi_resource_list" "firewalls" {
  parent_id = var.parent_id
  type      = var.resource_types.network_azure_firewalls
  response_export_values = {
    firewalls = "value[].{id:id,name:name,properties:properties}"
  }

  depends_on = [data.azapi_resource.virtual_hub]
}

data "azapi_resource" "public_ips" {
  for_each = var.ip_configurations

  resource_id = each.value.public_ip_address_id
  type        = var.resource_types.network_public_ip_addresses
  response_export_values = {
    address           = "properties.ipAddress"
    allocation_method = "properties.publicIPAllocationMethod"
    association       = "properties.ipConfiguration.id"
    ip_version        = "properties.publicIPAddressVersion"
    location          = "location"
    sku               = "sku.name"
    tier              = "sku.tier"
    zones             = "zones"
  }
}

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = var.parent_id
  type      = var.resource_types.network_azure_firewalls
  body = {
    # zones participates in replace_triggers_refs below. Sorting normalises caller
    # ordering so that semantically identical input ([1,2,3] vs [3,1,2]) produces an
    # identical body and does not trigger firewall replacement.
    zones = sort([for zone in coalesce(var.zones, []) : tostring(zone)])
    properties = {
      sku = {
        name = "AZFW_Hub"
        tier = var.sku_tier
      }
      virtualHub = {
        id = var.virtual_hub_id
      }
      firewallPolicy = var.firewall_policy_id == null ? null : { id = var.firewall_policy_id }
      # threatIntelMode is intentionally not set here: Azure rejects it directly on an
      # AZFW_Hub-SKU firewall (AzureFirewallDoesNotAcceptThreatIntelModeInSku). For secured
      # virtual hub firewalls, threat intelligence mode is configured on the attached
      # Firewall Policy instead (see the firewall_policy_threat_intelligence_mode input on
      # the root module's firewall-policy submodule). properties.threatIntelMode stays in
      # response_export_values below purely as a read-only reflection of whatever value
      # Azure/the policy resolves it to.
      ipConfigurations = [
        for key in sort(keys(var.ip_configurations)) : {
          name = var.ip_configurations[key].name
          properties = {
            publicIPAddress = {
              id = var.ip_configurations[key].public_ip_address_id
            }
          }
        }
      ]
    }
  }
  ignore_body_changes = length(var.ignore_body_changes.network_azure_firewalls) > 0 ? var.ignore_body_changes.network_azure_firewalls : null
  replace_triggers_refs = [
    "properties.sku.name",
    "zones",
  ]
  response_export_values = [
    "properties.additionalProperties",
    "properties.firewallPolicy",
    "properties.hubIPAddresses",
    "properties.ipConfigurations",
    "properties.provisioningState",
    "properties.sku",
    "properties.threatIntelMode",
    "properties.virtualHub",
  ]
  retry                     = var.retry
  schema_validation_enabled = true
  tags                      = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  lifecycle {
    precondition {
      # See modules/firewall/locals.tf's existing_customer_mode for the full rationale: this
      # condition is character-identical in shape to that one (both guard a managed<->customer transition
      # based on whether a pre-existing firewall's real ipConfigurations response already carries a
      # customer-owned public IP). Deliberately does NOT pre-filter the source through coalesce(): real
      # Azure ipConfigurations responses are a heterogeneous tuple that can be unification-impossible for
      # coalesce(), silently degrading to [] via the enclosing try() and misclassifying a genuine
      # customer-mode firewall as managed (confirmed against real Azure). Wrapping the entire
      # for-expression in try(..., []) instead avoids ever attempting that unification.
      condition = local.existing_firewall == null ? true : length(try([
        for configuration in local.existing_firewall.properties.ipConfigurations : configuration
        if try(configuration.properties.publicIPAddress.id, null) != null
      ], [])) > 0
      error_message = "An existing managed-IP firewall cannot be converted to customer IP mode by normal apply."
    }
    precondition {
      condition = lower(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id).subscription_id) == lower(
        provider::azapi::parse_resource_id("Microsoft.Network/virtualHubs", var.virtual_hub_id).subscription_id
      )
      error_message = "The firewall and virtual hub must be in the same subscription."
    }
    precondition {
      condition = data.azapi_resource.virtual_wan.output.type == "Standard" && (
        replace(lower(data.azapi_resource.virtual_hub.output.location), " ", "") == replace(lower(var.location), " ", "")
      )
      error_message = "A customer-IP firewall requires a Standard Virtual WAN hub in the same region."
    }
    precondition {
      condition = alltrue([
        for configuration in var.ip_configurations :
        lower(provider::azapi::parse_resource_id("Microsoft.Network/publicIPAddresses", configuration.public_ip_address_id).subscription_id) ==
        lower(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id).subscription_id)
      ])
      error_message = "Every customer public IP must be in the firewall's subscription."
    }
    precondition {
      condition = alltrue([
        for ip in data.azapi_resource.public_ips :
        ip.output.sku == "Standard" && ip.output.allocation_method == "Static" &&
        ip.output.ip_version == "IPv4" && ip.output.tier == "Regional" &&
        replace(lower(ip.output.location), " ", "") == replace(lower(var.location), " ", "")
      ])
      error_message = "Customer public IPs must be Standard/Regional, static IPv4 addresses in the firewall and hub region."
    }
    precondition {
      # A zone-redundant (or zonal) firewall cannot reference a public IP with no configured zones; Azure
      # rejects this at apply time with ZonalAzureFirewallCannotReferenceNoZonePublicIp. Surface it as a clear
      # plan-time error instead, since a customer's existing public IP may predate zone redundancy.
      #
      # This is deliberately a LENGTH check, not a set comparison. Verified against Azure with API version
      # 2024-10-01: a firewall zoned [1,2,3] referencing an IP zoned [1] is rejected with
      # AzureFirewallZoneConstraintDoesNotMatchPublicIpAddressZoneConstraint, so this check does NOT catch a
      # mismatched (as opposed to absent) zone set. Tightening to set equality is NOT justified on the
      # evidence: only IP-zones-narrower-than-firewall was tested, and if the real ARM rule is
      # firewall-zones subset-of IP-zones, equality would falsely reject a configuration Azure accepts.
      condition = length(coalesce(var.zones, [])) == 0 ? true : alltrue([
        for ip in data.azapi_resource.public_ips : length(try(coalesce(ip.output.zones, []), [])) > 0
      ])
      error_message = "This firewall is configured with availability zones (var.zones), but at least one customer public IP has no configured zones. Either set var.zones = [] to deploy a non-zonal firewall matching the existing public IP(s), or use zone-redundant public IPs. Note this check only detects ABSENT zones: an IP whose zones differ from the firewall's is rejected later by Azure at apply time with AzureFirewallZoneConstraintDoesNotMatchPublicIpAddressZoneConstraint."
    }
    precondition {
      # This precondition deliberately checks only `ipConfiguration`, not `natGateway`.
      #
      # A public IP attached to a NAT Gateway presents `ipConfiguration = null` with a non-null
      # `natGateway`, so this check treats it as unassociated. A client-side `natGateway == null` check
      # adds no safety: Azure rejects attaching a NAT-Gateway-owned public IP to a secured-hub firewall
      # (`Microsoft.Network/azureFirewalls`, api-version 2024-10-01) synchronously and before any mutation,
      # with `400 PublicIPAddressInUse` naming the conflicting `natGateways/...` resource. The firewall is
      # left `Succeeded` with its existing ipConfigurations unchanged.
      #
      # Azure's rejection is also more informative than this precondition could be, because it names the
      # owning resource. A natGateway-only check would cover just one of several possible
      # non-`ipConfiguration` association surfaces while implying a completeness it does not have.
      # `ipConfiguration` is still checked here because it is schema-generic across every consumer type
      # that attaches through that field (NIC, Load Balancer frontend, Application Gateway frontend,
      # VPN/ExpressRoute Gateway, Bastion, Route Server, and NIC-attached APIM/VMSS, per the ARM template
      # reference for this API version).
      #
      # Supplying a public IP that is not attached elsewhere is therefore a documented prerequisite, which
      # Azure's control plane enforces on the firewall-attach path.
      condition = alltrue([
        for key, ip in data.azapi_resource.public_ips : ip.output.association == null ? true : (
          lower(local.public_ip_association_parents[key]) == lower(local.firewall_id)
        )
      ])
      error_message = "A supplied public IP is associated with another resource. Only unassociated IPs or IPs already associated with this same firewall are accepted. (This is a plan-time convenience check; it does not detect NAT Gateway ownership - Azure's own control plane independently and synchronously rejects an already-owned public IP, including one owned by a NAT Gateway, with a named PublicIPAddressInUse error before any mutation.)"
    }
    postcondition {
      # Re-derives local.virtual_hub[0].private_ip_address's own null-degradation logic independently from
      # self.output (a postcondition cannot reference a local that itself depends on this same resource -
      # that is a disallowed self-referential dependency - so the search-every-ipConfiguration-and-treat-
      # empty-string-as-absent logic is intentionally duplicated here, not shared). properties.hubIPAddresses
      # is checked first for managed-mode/legacy compatibility, but is a mode-exclusive branch, not a normal
      # fallback: real customer-mode Azure GETs were observed to omit it entirely, making the
      # ipConfigurations scan the sole practical source in customer mode. If still null after searching
      # hubIPAddresses and every ipConfiguration, degrade to a clear, named apply-time error identifying this
      # firewall, instead of letting local.virtual_hub's private_ip_address silently resolve to null and
      # surface a confusing error from whatever consumes the private_ip_address output later. Terraform's
      # `coalesce` itself raises when every argument is null; the enclosing `try(..., null)` catches that,
      # so this is not a bare/unguarded coalesce - it degrades to `false` below (via `!= null`), which is
      # exactly the intended failure signal for this postcondition's own named error_message.
      condition = try(coalesce(
        try(self.output.properties.hubIPAddresses.privateIPAddress, null),
        try(compact([
          for configuration in try(self.output.properties.ipConfigurations, []) : try(configuration.properties.privateIPAddress, "")
        ])[0], null)
      ), null) != null
      error_message = "Firewall '${var.name}' (${self.id}) has no private IP address reported on properties.hubIPAddresses or on any properties.ipConfigurations[*].properties.privateIPAddress. This may indicate the firewall is not yet fully provisioned, or that Azure's response shape has changed unexpectedly."
    }
  }
}

module "avm_interfaces" {
  source  = "Azure/avm-utl-interfaces/azure"
  version = "0.6.0"

  diagnostic_settings_v2 = {
    for key, setting in var.diagnostic_settings : key => merge(setting, {
      name = coalesce(setting.name, "diag-${var.name}")
    })
  }
  enable_telemetry                 = var.enable_telemetry
  lock                             = var.lock
  role_assignment_definition_scope = azapi_resource.this.id
  role_assignments                 = var.role_assignments
}

resource "azapi_resource" "diagnostic_settings" {
  for_each = var.diagnostic_settings

  name                      = coalesce(each.value.name, "diag-${var.name}")
  parent_id                 = azapi_resource.this.id
  type                      = var.resource_types.insights_diagnostic_settings
  body                      = module.avm_interfaces.diagnostic_settings_azapi_v2[each.key].body
  ignore_body_changes       = length(var.ignore_body_changes.insights_diagnostic_settings) > 0 ? var.ignore_body_changes.insights_diagnostic_settings : null
  response_export_values    = []
  retry                     = var.retry
  schema_validation_enabled = true

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}
