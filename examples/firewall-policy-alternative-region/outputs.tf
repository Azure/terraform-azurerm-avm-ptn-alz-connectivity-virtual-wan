# Reads back the deployed secondary firewall policy from Azure to prove the
# location override actually took effect, not just that the plan accepted it.
data "azapi_resource" "secondary_firewall_policy" {
  resource_id            = module.test.firewall_policy_resource_ids["secondary"]
  type                   = "Microsoft.Network/firewallPolicies@2024-07-01"
  response_export_values = ["location", "properties.basePolicy.id"]

  depends_on = [module.test]
}

output "actual_secondary_firewall_policy_location" {
  description = "The location Azure reports for the secondary firewall policy, confirming the override was honored."

  precondition {
    condition     = data.azapi_resource.secondary_firewall_policy.output.location == local.primary_location
    error_message = "Expected the secondary firewall policy to be deployed in '${local.primary_location}', but Azure reported '${data.azapi_resource.secondary_firewall_policy.output.location}'. The firewall_policy.location override was not honored."
  }
  value = data.azapi_resource.secondary_firewall_policy.output.location
}

output "actual_secondary_firewall_policy_base_policy_id" {
  description = "The base policy ID Azure reports for the secondary firewall policy, confirming it still links to the shared parent policy."

  precondition {
    condition     = try(data.azapi_resource.secondary_firewall_policy.output.properties.basePolicy.id, null) == azapi_resource.base_policy.id
    error_message = "Expected the secondary firewall policy to reference the shared base policy '${azapi_resource.base_policy.id}', but Azure did not report a matching basePolicy.id."
  }
  value = try(data.azapi_resource.secondary_firewall_policy.output.properties.basePolicy.id, null)
}
