# Firewall Policy Alternative Region Example

Deploys a Virtual WAN with two hubs in different regions that share a single parent firewall policy. This is the end-to-end regression example for [Azure/Azure-Landing-Zones#358](https://github.com/Azure/Azure-Landing-Zones/issues/358).

Azure requires a child firewall policy to reside in the same region as its parent. The `secondary` hub's firewall stays in its own region, but `firewall_policy.location` overrides the policy's region so it matches the shared base policy.

After deployment, the example reads the secondary firewall policy back from Azure with AzAPI. The `actual_secondary_firewall_policy_location` and `actual_secondary_firewall_policy_base_policy_id` outputs have preconditions that fail the deployment unless Azure reports the expected values.

> **Cost and duration:** This example creates two chargeable Azure Firewalls and Virtual WAN hubs. Deployment and teardown can each take 30 minutes or longer.