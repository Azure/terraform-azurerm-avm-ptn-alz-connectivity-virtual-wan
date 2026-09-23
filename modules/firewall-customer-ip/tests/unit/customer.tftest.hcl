mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = { output = { firewalls = [], results = [] } }
  }
  mock_data "azapi_resource" {
    defaults = {
      output = {
        address        = "203.0.113.10", allocation_method = "Static", association = null
        ip_version     = "IPv4", location = "eastus", sku = "Standard", tier = "Regional", type = "Standard"
        virtual_wan_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/wan-test"
        zones          = ["1", "2", "3"]
      }
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"
      output = {
        properties = {
          hubIPAddresses = { privateIPAddress = "10.0.0.4" }, threatIntelMode = null, additionalProperties = {}
        }
      }
    }
  }
}

variables {
  enable_telemetry = false
  name             = "fw-test"
  parent_id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test"
  location         = "eastus"
  virtual_hub_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualHubs/hub-test"
  ip_configurations = {
    primary = {
      name                 = "internet-primary"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
    }
  }
}

run "one_customer_ip" {
  command = apply

  assert {
    condition = (
      azapi_resource.this.body.properties.sku.name == "AZFW_Hub" &&
      azapi_resource.this.body.properties.sku.tier == "Standard" &&
      azapi_resource.this.body.properties.virtualHub.id == var.virtual_hub_id &&
      azapi_resource.this.body.properties.ipConfigurations[0].name == "internet-primary" &&
      azapi_resource.this.body.properties.ipConfigurations[0].properties.publicIPAddress.id == var.ip_configurations["primary"].public_ip_address_id
    )
    error_message = "The scalar firewall must receive an explicit customer IP configuration and unchanged hub reference."
  }
  assert {
    condition     = !contains(keys(azapi_resource.this.body.properties), "hubIPAddresses")
    error_message = "Customer-only mode must not request a managed public IP count or an address-retention list."
  }
  assert {
    condition     = output.public_ip_addresses == tolist(["203.0.113.10"]) && output.private_ip_address == "10.0.0.4"
    error_message = "Outputs must contain actual IP strings, not public IP resource IDs."
  }
  assert {
    condition     = azapi_resource.this.type == "Microsoft.Network/azureFirewalls@2024-10-01" && azapi_resource.this.schema_validation_enabled
    error_message = "The default stable API must keep schema validation enabled."
  }
  assert {
    condition     = length(azapi_resource.lock) == 0 && length(azapi_resource.role_assignments) == 0 && output.lock_resource_id == null && output.role_assignment_resource_ids == {}
    error_message = "Canonical optional interfaces must create no locks or assignments by default."
  }
}

run "accept_standard_virtual_wan_type_without_hub_sku" {
  command = apply
  override_data {
    target = data.azapi_resource.virtual_hub
    values = {
      output = {
        location       = "eastus"
        virtual_wan_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualWans/wan-test"
      }
    }
  }
  override_data {
    target = data.azapi_resource.virtual_wan
    values = { output = { type = "Standard" } }
  }
  assert {
    condition     = data.azapi_resource.virtual_wan.resource_id == data.azapi_resource.virtual_hub.output.virtual_wan_id
    error_message = "The Virtual WAN read must resolve from the hub's own parent reference; real Azure hub reads do not reliably populate a hub-level sku."
  }
  assert {
    condition     = azapi_resource.this.body.properties.virtualHub.id == var.virtual_hub_id
    error_message = "Creation must succeed against a Standard Virtual WAN even when the hub response has no sku field at all."
  }
}

run "add_second_ip_in_stable_key_order" {
  command = apply
  variables {
    sku_tier = "Premium"
    ip_configurations = {
      z_second = {
        name                 = "internet-second"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-second"
      }
      a_first = {
        name                 = "internet-first"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary"
      }
    }
  }
  override_data {
    target = data.azapi_resource.public_ips["z_second"]
    values = {
      output = {
        address    = "203.0.113.11", allocation_method = "Static", association = null
        ip_version = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones      = ["1", "2", "3"]
      }
    }
  }
  assert {
    condition     = [for configuration in azapi_resource.this.body.properties.ipConfigurations : configuration.name] == ["internet-first", "internet-second"]
    error_message = "Request ordering must be deterministic by stable caller key, not insertion order, ID or generated name."
  }
  assert {
    condition     = azapi_resource.this.body.properties.sku.tier == "Premium" && output.public_ip_addresses == tolist(["203.0.113.10", "203.0.113.11"])
    error_message = "Premium must support multiple IPs with output ordering matching configuration keys."
  }
}

run "replace_one_ip_and_remove_another" {
  command = apply
  variables {
    ip_configurations = {
      a_first = {
        name                 = "internet-first"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-replacement"
      }
    }
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.ipConfigurations) == 1 && endswith(azapi_resource.this.body.properties.ipConfigurations[0].properties.publicIPAddress.id, "/pip-replacement")
    error_message = "Same-mode replacement/removal must change the actual ARM configuration, with no IP ignore path."
  }
  assert {
    condition     = azapi_resource.this.ignore_body_changes == null && !contains(keys(azapi_resource.this.body.properties), "hubIPAddresses")
    error_message = "IP maintenance must not suppress drift or fall back to managed mode."
  }
}

run "same_firewall_association_readback" {
  command = apply
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address           = "203.0.113.10"
        allocation_method = "Static"
        association       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/RG-TEST/providers/Microsoft.Network/azureFirewalls/FW-TEST/azureFirewallIpConfigurations/internet-primary"
        ip_version        = "IPv4", location = "East US", sku = "Standard", tier = "Regional"
        zones             = ["1", "2", "3"]
      }
    }
  }
  override_data {
    target = data.azapi_resource_list.firewalls
    values = {
      output = {
        firewalls = [{
          name = "FW-TEST"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/FW-TEST"
          properties = {
            ipConfigurations = [{ properties = { publicIPAddress = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ips/providers/Microsoft.Network/publicIPAddresses/pip-primary" } } }]
          }
        }]
      }
    }
  }
  assert {
    condition     = lower(local.public_ip_association_parents["primary"]) == lower(local.firewall_id)
    error_message = "Reapply must accept the exact same firewall parent for the Azure Firewall IP configuration child path."
  }
}

run "same_firewall_alternate_child_path" {
  command = apply
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address           = "203.0.113.10"
        allocation_method = "Static"
        association       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test/ipConfigurations/internet-primary"
        ip_version        = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones             = ["1", "2", "3"]
      }
    }
  }
}

run "api_retry_timeout_policy_and_tags_controls" {
  command = apply
  variables {
    firewall_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/firewallPolicies/policy-test"
    resource_types     = { network_azure_firewalls = "Microsoft.Network/azureFirewalls@2025-01-01" }
    retry              = { error_message_regex = ["Retryable"], interval_seconds = 3, max_interval_seconds = 9 }
    timeouts           = { create = "91m", update = "92m", delete = "93m", read = "6m" }
    tags               = { environment = "test" }
  }
  assert {
    condition = (
      azapi_resource.this.type == var.resource_types.network_azure_firewalls &&
      azapi_resource.this.retry.error_message_regex == var.retry.error_message_regex &&
      azapi_resource.this.retry.interval_seconds == 3 &&
      azapi_resource.this.retry.max_interval_seconds == 9 &&
      azapi_resource.this.timeouts.create == "91m" &&
      azapi_resource.this.timeouts.update == "92m" &&
      azapi_resource.this.timeouts.delete == "93m" &&
      azapi_resource.this.timeouts.read == "6m"
    )
    error_message = "The real primary resource must honor supported managed API/retry/timeout controls."
  }
  assert {
    condition     = azapi_resource.this.body.properties.firewallPolicy.id == var.firewall_policy_id && azapi_resource.this.tags == var.tags
    error_message = "Existing policy references and exact caller tags must pass through unchanged."
  }
}

run "diagnostics_preserve_legacy_names_destinations_and_ids" {
  command = apply
  variables {
    diagnostic_settings = {
      audit = {
        logs                                     = [{ category_group = "allLogs" }, { category = "AzureFirewallApplicationRule" }]
        metrics                                  = [{ category = "AllMetrics" }]
        workspace_resource_id                    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/logs"
        storage_account_resource_id              = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/audit"
        event_hub_authorization_rule_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.EventHub/namespaces/audit/authorizationRules/send"
        event_hub_name                           = "events"
        marketplace_partner_resource_id          = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Datadog/monitors/audit"
      }
    }
  }
  assert {
    condition     = azapi_resource.diagnostic_settings["audit"].name == "diag-fw-test" && azapi_resource.diagnostic_settings["audit"].parent_id == output.resource_id
    error_message = "The generated diagnostic name and target identity must match the old helper's contract."
  }
  assert {
    condition = (
      azapi_resource.diagnostic_settings["audit"].body.properties.workspaceId == var.diagnostic_settings["audit"].workspace_resource_id &&
      azapi_resource.diagnostic_settings["audit"].body.properties.storageAccountId == var.diagnostic_settings["audit"].storage_account_resource_id &&
      azapi_resource.diagnostic_settings["audit"].body.properties.eventHubAuthorizationRuleId == var.diagnostic_settings["audit"].event_hub_authorization_rule_resource_id &&
      azapi_resource.diagnostic_settings["audit"].body.properties.eventHubName == "events" &&
      azapi_resource.diagnostic_settings["audit"].body.properties.marketplacePartnerId == var.diagnostic_settings["audit"].marketplace_partner_resource_id &&
      length(azapi_resource.diagnostic_settings["audit"].body.properties.logs) == 2 &&
      azapi_resource.diagnostic_settings["audit"].body.properties.metrics[0].category == "AllMetrics"
    )
    error_message = "The AVM diagnostic adapter must preserve all destinations and requested categories."
  }
  assert {
    condition     = output.legacy_diagnostic_settings_resource_ids["audit"] == "${output.resource_id}|diag-fw-test"
    error_message = "The compatibility output must retain the AzureRM composite-ID shape."
  }
}

run "firewall_scoped_roles_and_lock" {
  command = apply
  variables {
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = {
        name                                   = "11111111-1111-1111-1111-111111111111"
        role_definition_id_or_name             = "Reader"
        principal_id                           = "22222222-2222-2222-2222-222222222222"
        principal_type                         = "ServicePrincipal"
        description                            = "Firewall reader"
        condition                              = "test-condition"
        condition_version                      = "2.0"
        delegated_managed_identity_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/delegated"
      }
    }
    retry    = { error_message_regex = ["ScopeLocked"], interval_seconds = 2, max_interval_seconds = 8 }
    timeouts = { create = "7m", read = "2m", update = "8m", delete = "9m" }
  }
  override_data {
    target = module.avm_interfaces.data.azapi_resource_list.role_definitions[0]
    values = {
      output = {
        results = [{
          role_name = "Reader"
          id        = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
        }]
      }
    }
  }
  assert {
    condition = (
      azapi_resource.role_assignments["reader"].parent_id == output.resource_id &&
      azapi_resource.role_assignments["reader"].name == var.role_assignments["reader"].name &&
      azapi_resource.role_assignments["reader"].body.properties.principalId == var.role_assignments["reader"].principal_id &&
      endswith(azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId, "/acdd72a7-3385-48ef-bd42-f606fba81ae7") &&
      azapi_resource.role_assignments["reader"].body.properties.principalType == "ServicePrincipal" &&
      azapi_resource.role_assignments["reader"].body.properties.condition == "test-condition" &&
      azapi_resource.role_assignments["reader"].body.properties.conditionVersion == "2.0" &&
      azapi_resource.role_assignments["reader"].body.properties.delegatedManagedIdentityResourceId == var.role_assignments["reader"].delegated_managed_identity_resource_id
    )
    error_message = "The real utility must resolve role names and preserve every canonical role assignment property at the firewall scope."
  }
  assert {
    condition = (
      azapi_resource.lock[0].parent_id == output.resource_id &&
      azapi_resource.lock[0].name == "lock-CanNotDelete" &&
      azapi_resource.lock[0].body.properties.level == "CanNotDelete" &&
      azapi_resource.lock[0].type == "Microsoft.Authorization/locks@2020-05-01" &&
      azapi_resource.role_assignments["reader"].type == "Microsoft.Authorization/roleAssignments@2022-04-01" &&
      azapi_resource.lock[0].schema_validation_enabled &&
      azapi_resource.role_assignments["reader"].schema_validation_enabled
    )
    error_message = "The lock and role assignment must use their owned API defaults without changing the primary or disabling schema checks."
  }
  assert {
    condition = (
      azapi_resource.lock[0].retry.interval_seconds == 2 &&
      azapi_resource.role_assignments["reader"].retry.max_interval_seconds == 8 &&
      azapi_resource.lock[0].timeouts.delete == "9m" &&
      azapi_resource.role_assignments["reader"].timeouts.create == "7m" &&
      azapi_resource.lock[0].ignore_body_changes == null &&
      azapi_resource.role_assignments["reader"].ignore_body_changes == null &&
      output.lock_resource_id == azapi_resource.lock[0].id &&
      output.role_assignment_resource_ids["reader"] == azapi_resource.role_assignments["reader"].id
    )
    error_message = "Satellite retry/timeouts, default drift visibility and discrete outputs must be wired to the actual resources."
  }
}

run "read_only_lock_name_and_notes" {
  command = apply
  variables {
    lock = { kind = "ReadOnly", name = "maintenance-lock", notes = "Explicit maintenance window required." }
  }
  assert {
    condition = (
      azapi_resource.lock[0].name == "maintenance-lock" &&
      azapi_resource.lock[0].body.properties.level == "ReadOnly" &&
      azapi_resource.lock[0].body.properties.notes == var.lock.notes &&
      length(azapi_resource.role_assignments) == 0
    )
    error_message = "Canonical lock notes must survive the released utility adapter, and roles remain optional."
  }
}

run "generated_role_name" {
  command = apply
  variables {
    role_assignments = {
      reader = {
        role_definition_id_or_name = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
        principal_id               = "22222222-2222-2222-2222-222222222222"
      }
    }
  }
  override_resource {
    target = module.avm_interfaces.random_uuid.role_assignment_name["reader"]
    values = { result = "33333333-3333-3333-3333-333333333333" }
  }
  assert {
    condition = (
      azapi_resource.role_assignments["reader"].name == "33333333-3333-3333-3333-333333333333" &&
      azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId == var.role_assignments["reader"].role_definition_id_or_name &&
      output.lock_resource_id == null
    )
    error_message = "Omitted assignment names must use the utility's UUID while explicit role IDs remain unchanged."
  }
}

run "accept_non_zonal_firewall_with_non_zonal_public_ip" {
  command = apply
  variables { zones = [] }
  override_data {
    target = data.azapi_resource.public_ips["primary"]
    values = {
      output = {
        address    = "203.0.113.10", allocation_method = "Static", association = null
        ip_version = "IPv4", location = "eastus", sku = "Standard", tier = "Regional"
        zones      = []
      }
    }
  }
  assert {
    condition     = length(azapi_resource.this.body.zones) == 0
    error_message = "A caller-selected non-zonal firewall must be accepted when the customer public IP also has no configured zones, mirroring a pre-zone-redundancy public IP."
  }
}

run "remove_optional_extensions" {
  command = apply
  assert {
    condition     = output.lock_resource_id == null && output.role_assignment_resource_ids == {} && length(azapi_resource.this.body.properties.ipConfigurations) == 1
    error_message = "Removing optional extensions must leave the same customer firewall configuration intact."
  }
}

run "reject_invalid_lock_kind" {
  command = plan
  variables {
    lock = { kind = "None" }
  }
  expect_failures = [var.lock]
}

run "reject_invalid_delegated_identity_id" {
  command = plan
  variables {
    role_assignments = {
      reader = {
        role_definition_id_or_name             = "Reader"
        principal_id                           = "22222222-2222-2222-2222-222222222222"
        delegated_managed_identity_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/not-an-identity"
      }
    }
  }
  expect_failures = [var.role_assignments]
}
